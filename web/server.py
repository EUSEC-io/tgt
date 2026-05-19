#!/usr/bin/env python3
"""
tgt-web — local web UI for the `tgt` Fisher plugin.

Proof-of-concept. Runs an HTTP server on 127.0.0.1:<port>, renders a
dashboard view of the current `tgt` state (scenarios / targets / creds /
DCs), and exposes write actions by shelling out to the `tgt` CLI itself.
Business logic stays in fish — this is purely a presentation/dispatch
layer.

Design rules (keep stable across iterations):

  1. Localhost only. `127.0.0.1`. No external bind. No auth (single-user
     model, same threat model as `fish_config`).
  2. Reads parse the registry files under $TGT_HOME directly (same shape
     fish writes). No business logic — we walk `scenarios/*/{targets,
     creds, dcs}/*.fish` and unescape values, mirroring _tgt_*_inspect.
  3. Writes ALWAYS shell out: `subprocess.run(["tgt", "scenario", ...])`.
     Never reimplement save/load/krb5/hosts sync — that's fish's job.
  4. New `tgt` commands MUST be mirrored here. Read = add a parser if a
     new field type appears. Write = add a new handler that subprocess-
     calls the new verb. See the action table in handle_action().

Run with: python3 web/server.py [--port 0] [--no-open]
"""

import argparse
import http.server
import json
import os
import re
import shlex
import socket
import subprocess
import sys
import threading
import time
import urllib.parse
import webbrowser
from pathlib import Path


# ───────────────────────────── Registry reader ───────────────────────────

def tgt_home():
    """Resolve $TGT_HOME the same way fish does."""
    return Path(os.environ.get("TGT_HOME") or
                Path.home() / ".config" / "fish" / "tgt")


# `string escape --style=script` adds single-quote wrapping when needed;
# unescape reverses it. For the few special wrappings we care about
# (single-quoted, double-quoted, bare), this is sufficient. We do NOT
# attempt full fish-script tokenization — values are simple strings.
def fish_unescape(s: str) -> str:
    if not s:
        return ""
    # `string escape` outputs: "''" for empty, "'foo bar'" for spaces,
    # '"\'"' for a value containing a single quote, bare for safe tokens.
    s = s.strip()
    if len(s) >= 2 and s[0] == "'" and s[-1] == "'":
        return s[1:-1].replace("\\'", "'").replace("\\\\", "\\")
    if len(s) >= 2 and s[0] == '"' and s[-1] == '"':
        # Double-quoted form is used by fish escape for values
        # containing literal single quotes.
        return s[1:-1].replace('\\"', '"').replace("\\\\", "\\")
    # Bare token — may have backslash escapes (\n, \', etc.). Keep
    # simple: just unescape backslash sequences.
    return s.replace("\\'", "'").replace("\\\\", "\\")


EXPORT_RE = re.compile(r"^_tgt_export\s+(\S+)\s+(.*)$")


def parse_export_file(path: Path) -> dict[str, str]:
    """Parse a `_tgt_export VAR value` file into {VAR: unescaped_value}."""
    out = {}
    if not path.is_file():
        return out
    for line in path.read_text(errors="replace").splitlines():
        m = EXPORT_RE.match(line)
        if not m:
            continue
        out[m.group(1)] = fish_unescape(m.group(2))
    return out


def list_scenarios() -> list[dict]:
    """List all scenarios with summary counts + archived/active flags."""
    home = tgt_home()
    sc_root = home / "scenarios"
    if not sc_root.is_dir():
        return []
    active = os.environ.get("TGT_SCENARIO", "")
    out = []
    for sd in sorted(sc_root.iterdir()):
        if not sd.is_dir():
            continue
        out.append({
            "name": sd.name,
            "active": sd.name == active,
            "archived": (sd / ".archived").exists(),
            "target_count": _count_fish(sd / "targets"),
            "cred_count": _count_fish(sd / "creds"),
            "dc_count": _count_fish(sd / "dcs"),
        })
    return out


def _count_fish(d: Path) -> int:
    if not d.is_dir():
        return 0
    return sum(1 for f in d.iterdir() if f.suffix == ".fish")


def scenario_detail(name: str) -> dict | None:
    """Detail for one scenario: targets, creds, DCs, active markers."""
    home = tgt_home()
    sd = home / "scenarios" / name
    if not sd.is_dir():
        return None

    active_dc = _read_marker(sd / ".active-dc")
    active_cred = _read_marker(sd / ".active-cred")

    targets = []
    for f in sorted((sd / "targets").glob("*.fish")) if (sd / "targets").is_dir() else []:
        data = parse_export_file(f)
        targets.append({
            "alias": f.stem,
            "host": data.get("TGT", ""),
            "hosts": (data.get("TGT_HOSTS", "") or "").split()
                     if data.get("TGT_HOSTS") else [],
        })

    creds = []
    for f in sorted((sd / "creds").glob("*.fish")) if (sd / "creds").is_dir() else []:
        data = parse_export_file(f)
        creds.append({
            "alias": f.stem,
            "active": f.stem == active_cred,
            "username": data.get("TGT_CRED_USERNAME", ""),
            "has_password": bool(data.get("TGT_CRED_PASSWORD")),
            "domain": data.get("TGT_CRED_DOMAIN", ""),
            "notes": data.get("TGT_CRED_NOTES", ""),
        })

    dcs = []
    for f in sorted((sd / "dcs").glob("*.fish")) if (sd / "dcs").is_dir() else []:
        data = parse_export_file(f)
        dcs.append({
            "alias": f.stem,
            "active": f.stem == active_dc,
            "domain": data.get("TGT_DC_DOMAIN", ""),
            "realm": data.get("TGT_DC_REALM", ""),
            "kdc_host": data.get("TGT_DC_HOST", ""),
            "kdc_ip": data.get("TGT_DC_IP", ""),
            "admin_host": data.get("TGT_DC_ADMIN_HOST", ""),
            "admin_ip": data.get("TGT_DC_ADMIN_IP", ""),
        })

    return {
        "name": name,
        "active": name == os.environ.get("TGT_SCENARIO", ""),
        "archived": (sd / ".archived").exists(),
        "targets": targets,
        "creds": creds,
        "dcs": dcs,
    }


def _read_marker(p: Path) -> str:
    if not p.is_file():
        return ""
    return p.read_text(errors="replace").strip()


def cred_password(scenario: str, alias: str) -> str:
    """Read the actual password value (used by --show-password endpoint)."""
    home = tgt_home()
    f = home / "scenarios" / scenario / "creds" / f"{alias}.fish"
    return parse_export_file(f).get("TGT_CRED_PASSWORD", "")


# ───────────────────────────── Write dispatch ────────────────────────────

# Every write goes through `tgt`. We never touch files for writes —
# that would bypass krb5/hosts sync and active-marker handling.
#
# When you add a new `tgt` verb, add an entry here. The web UI calls
# this with a fixed action name + a dict of params; we map it to a
# concrete argv to subprocess. Whitelist-only — never accept a raw
# argv from the client.

def tgt_cmd(args: list[str]) -> tuple[int, str, str]:
    """Run `tgt <args>`. Returns (returncode, stdout, stderr)."""
    # Force test-mode-off equivalent behaviour and disable gum so we
    # don't accidentally try to prompt the user from a non-TTY server.
    env = os.environ.copy()
    env["TGT_NO_GUM"] = "1"
    p = subprocess.run(
        ["fish", "-c", "tgt " + " ".join(shlex.quote(a) for a in args)],
        capture_output=True, text=True, env=env, timeout=15,
    )
    return p.returncode, p.stdout, p.stderr


ACTIONS = {
    # name → (argv builder, required params)
    "scenario_switch": (lambda p: ["scenario", "switch", p["name"]],          ["name"]),
    "scenario_unload": (lambda p: ["scenario", "unload"],                     []),
    "scenario_archive":  (lambda p: ["scenario", "archive", p["name"]],       ["name"]),
    "scenario_unarchive":(lambda p: ["scenario", "unarchive", p["name"]],     ["name"]),
    "target_switch":  (lambda p: ["switch", p["alias"]],                      ["alias"]),
    "target_revoke":  (lambda p: ["revoke"],                                  []),
    "cred_switch":    (lambda p: ["cred", "switch", p["alias"]],              ["alias"]),
    "cred_unset":     (lambda p: ["cred", "unset"],                           []),
    "dc_switch":      (lambda p: ["dc", "switch", p["alias"]],                ["alias"]),
    "dc_unset":       (lambda p: ["dc", "unset"],                             []),
}


def dispatch_action(name: str, params: dict) -> tuple[int, dict]:
    spec = ACTIONS.get(name)
    if not spec:
        return 400, {"error": f"unknown action: {name}"}
    builder, required = spec
    for r in required:
        if r not in params:
            return 400, {"error": f"missing param: {r}"}
    argv = builder(params)
    rc, out, err = tgt_cmd(argv)
    return (200 if rc == 0 else 500), {
        "rc": rc, "stdout": out, "stderr": err, "argv": argv,
    }


# ───────────────────────────── HTTP handler ──────────────────────────────

INDEX_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>tgt</title>
<style>
* { box-sizing: border-box; }
body { font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
       background: #0e1116; color: #c9d1d9; margin: 0; padding: 24px;
       font-size: 13px; line-height: 1.5; }
header { display: flex; justify-content: space-between; align-items: baseline;
         border-bottom: 1px solid #30363d; padding-bottom: 8px; margin-bottom: 24px; }
h1 { font-size: 18px; margin: 0; color: #58a6ff; }
h2 { font-size: 14px; color: #8b949e; text-transform: uppercase;
     letter-spacing: 0.5px; margin: 24px 0 8px; }
.muted { color: #6e7681; }
table { border-collapse: collapse; width: 100%; margin-bottom: 16px; }
th, td { text-align: left; padding: 6px 10px; border-bottom: 1px solid #21262d; }
th { color: #8b949e; font-weight: 600; font-size: 11px;
     text-transform: uppercase; letter-spacing: 0.5px; }
tr:hover { background: #161b22; }
.active { color: #56d364; font-weight: 600; }
.active::before { content: "* "; }
.archived { color: #6e7681; font-style: italic; }
button { background: #21262d; color: #c9d1d9; border: 1px solid #30363d;
         padding: 4px 10px; cursor: pointer; font-family: inherit;
         font-size: 11px; border-radius: 3px; }
button:hover { background: #30363d; }
button.primary { background: #1f6feb; border-color: #1f6feb; color: white; }
button.primary:hover { background: #388bfd; }
button.danger { background: #6e1f1f; border-color: #6e1f1f; }
.toast { position: fixed; bottom: 24px; right: 24px; background: #21262d;
         border: 1px solid #30363d; padding: 10px 14px; border-radius: 4px;
         opacity: 0; transition: opacity 0.2s; max-width: 400px; }
.toast.show { opacity: 1; }
.toast.error { border-color: #f85149; }
.toast.success { border-color: #56d364; }
.scenario-row { cursor: pointer; }
.detail { background: #161b22; padding: 16px; border-radius: 4px;
          margin-top: 12px; }
.password-cell { font-family: inherit; }
.password-cell .reveal { cursor: pointer; color: #6e7681; text-decoration: underline; }
code { background: #161b22; padding: 1px 4px; border-radius: 2px; }
.empty { color: #6e7681; font-style: italic; padding: 12px; }
</style>
</head>
<body>
<header>
  <h1>tgt</h1>
  <div id="active" class="muted"></div>
</header>

<div id="app">Loading…</div>

<div id="toast" class="toast"></div>

<script>
let state = { selected: null };

async function api(path, opts) {
  const r = await fetch(path, opts);
  if (!r.ok) throw new Error(await r.text());
  return r.json();
}

function toast(msg, kind) {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.className = 'toast show ' + (kind || '');
  setTimeout(() => { t.className = 'toast'; }, 2500);
}

async function act(name, params) {
  try {
    const r = await api('/api/action', {
      method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({ action: name, params: params || {} }),
    });
    if (r.rc === 0) toast('✓ ' + (r.stdout.trim().split('\\n').pop() || name), 'success');
    else toast('error: ' + r.stderr.trim(), 'error');
    await render();
  } catch (e) { toast('error: ' + e.message, 'error'); }
}

async function revealPassword(scenario, alias, btn) {
  const r = await api(`/api/scenarios/${scenario}/creds/${alias}/password`);
  btn.parentNode.textContent = r.password || '(empty)';
}

function el(tag, attrs, ...children) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (k === 'onclick') e.onclick = v;
    else if (k === 'class') e.className = v;
    else e.setAttribute(k, v);
  }
  for (const c of children) {
    if (c == null) continue;
    e.append(typeof c === 'string' ? document.createTextNode(c) : c);
  }
  return e;
}

function renderScenarios(list) {
  if (list.length === 0) return el('div', {class: 'empty'}, 'No scenarios yet.');
  const tbl = el('table', {},
    el('thead', {}, el('tr', {},
      el('th', {}, 'scenario'), el('th', {}, 'targets'),
      el('th', {}, 'creds'), el('th', {}, 'DCs'), el('th', {}, ''))),
    el('tbody', {}, ...list.map(s => el('tr', {class: 'scenario-row'},
      el('td', {class: (s.active ? 'active ' : '') + (s.archived ? 'archived' : ''),
               onclick: () => { state.selected = s.name; render(); }}, s.name),
      el('td', {}, String(s.target_count)),
      el('td', {}, String(s.cred_count)),
      el('td', {}, String(s.dc_count)),
      el('td', {},
        s.active
          ? el('button', {onclick: () => act('scenario_unload')}, 'unload')
          : el('button', {class: 'primary', onclick: () => act('scenario_switch', {name: s.name})}, 'switch'),
        ' ',
        el('button', {onclick: () => act(s.archived ? 'scenario_unarchive' : 'scenario_archive', {name: s.name})},
           s.archived ? 'unarchive' : 'archive'))))));
  return tbl;
}

function renderDetail(d) {
  if (!d) return el('div', {});
  const container = el('div', {class: 'detail'});
  container.append(el('h2', {}, `scenario: ${d.name}${d.active ? ' (active)' : ''}${d.archived ? ' [archived]' : ''}`));

  // Targets
  container.append(el('h2', {}, 'targets'));
  if (d.targets.length === 0) container.append(el('div', {class: 'empty'}, '(none)'));
  else container.append(el('table', {},
    el('thead', {}, el('tr', {}, el('th', {}, 'alias'), el('th', {}, 'host'), el('th', {}, 'hostnames'), el('th', {}, ''))),
    el('tbody', {}, ...d.targets.map(t => el('tr', {},
      el('td', {}, t.alias),
      el('td', {}, t.host || '—'),
      el('td', {}, t.hosts.join(', ') || '—'),
      el('td', {}, d.active
        ? el('button', {onclick: () => act('target_switch', {alias: t.alias})}, 'switch')
        : ''))))));

  // Creds
  container.append(el('h2', {}, 'credentials'));
  if (d.creds.length === 0) container.append(el('div', {class: 'empty'}, '(none)'));
  else container.append(el('table', {},
    el('thead', {}, el('tr', {}, el('th', {}, 'alias'), el('th', {}, 'username'),
                        el('th', {}, 'password'), el('th', {}, 'domain'),
                        el('th', {}, 'notes'), el('th', {}, ''))),
    el('tbody', {}, ...d.creds.map(c => el('tr', {},
      el('td', {class: c.active ? 'active' : ''}, c.alias),
      el('td', {}, c.username),
      el('td', {class: 'password-cell'},
        c.has_password
          ? el('span', {}, el('span', {class: 'reveal', onclick: (e) => revealPassword(d.name, c.alias, e.target)}, 'reveal'))
          : '—'),
      el('td', {}, c.domain || '—'),
      el('td', {}, c.notes || '—'),
      el('td', {}, d.active && !c.active
        ? el('button', {onclick: () => act('cred_switch', {alias: c.alias})}, 'switch')
        : (c.active ? el('button', {onclick: () => act('cred_unset')}, 'unset') : '')))))));

  // DCs
  container.append(el('h2', {}, 'DCs'));
  if (d.dcs.length === 0) container.append(el('div', {class: 'empty'}, '(none)'));
  else container.append(el('table', {},
    el('thead', {}, el('tr', {}, el('th', {}, 'alias'), el('th', {}, 'domain'),
                        el('th', {}, 'realm'), el('th', {}, 'kdc'),
                        el('th', {}, 'admin'), el('th', {}, ''))),
    el('tbody', {}, ...d.dcs.map(dc => el('tr', {},
      el('td', {class: dc.active ? 'active' : ''}, dc.alias),
      el('td', {}, dc.domain || '—'),
      el('td', {}, dc.realm || '—'),
      el('td', {}, dc.kdc_host || dc.kdc_ip || '—'),
      el('td', {}, dc.admin_host || dc.admin_ip || '—'),
      el('td', {}, d.active && !dc.active
        ? el('button', {onclick: () => act('dc_switch', {alias: dc.alias})}, 'switch')
        : (dc.active ? el('button', {onclick: () => act('dc_unset')}, 'unset') : '')))))));

  return container;
}

async function render() {
  const app = document.getElementById('app');
  const activeEl = document.getElementById('active');
  app.innerHTML = '';
  try {
    const list = await api('/api/scenarios');
    const active = list.find(s => s.active);
    activeEl.textContent = active
      ? `active: ${active.name}`
      : '(no active scenario)';
    app.append(renderScenarios(list));
    if (state.selected) {
      const d = await api(`/api/scenarios/${state.selected}`);
      app.append(renderDetail(d));
    } else if (active) {
      const d = await api(`/api/scenarios/${active.name}`);
      app.append(renderDetail(d));
    }
  } catch (e) {
    app.append(el('div', {class: 'empty'}, 'error: ' + e.message));
  }
}

render();
setInterval(render, 5000); // light auto-refresh; fish state may change from terminal
</script>
</body>
</html>
"""


class Handler(http.server.BaseHTTPRequestHandler):
    # Quieter logs — one line per request, no noisy details.
    def log_message(self, fmt, *args):
        sys.stderr.write(f"[{time.strftime('%H:%M:%S')}] {self.address_string()} - {fmt % args}\n")

    def _send_json(self, status, body):
        data = json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _send_html(self, body):
        data = body.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        if path == "/":
            return self._send_html(INDEX_HTML)
        if path == "/api/scenarios":
            return self._send_json(200, list_scenarios())
        # /api/scenarios/<name>
        m = re.match(r"^/api/scenarios/([^/]+)$", path)
        if m:
            d = scenario_detail(urllib.parse.unquote(m.group(1)))
            if d is None:
                return self._send_json(404, {"error": "not found"})
            return self._send_json(200, d)
        # /api/scenarios/<name>/creds/<alias>/password
        m = re.match(r"^/api/scenarios/([^/]+)/creds/([^/]+)/password$", path)
        if m:
            scen = urllib.parse.unquote(m.group(1))
            alias = urllib.parse.unquote(m.group(2))
            return self._send_json(200, {"password": cred_password(scen, alias)})
        return self._send_json(404, {"error": "not found"})

    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length > 0 else b""
        try:
            body = json.loads(raw or "{}")
        except json.JSONDecodeError:
            return self._send_json(400, {"error": "bad JSON"})
        if path == "/api/action":
            action = body.get("action", "")
            params = body.get("params", {}) or {}
            status, result = dispatch_action(action, params)
            return self._send_json(status, result)
        return self._send_json(404, {"error": "not found"})


# ───────────────────────────── Main ──────────────────────────────────────

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=0,
                        help="port to bind (0 = pick an unused one)")
    parser.add_argument("--no-open", action="store_true",
                        help="don't auto-open the browser")
    args = parser.parse_args()

    server = http.server.ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    port = server.server_address[1]
    url = f"http://127.0.0.1:{port}/"
    print(f"tgt web UI: {url}  (Ctrl-C to stop)", file=sys.stderr)

    if not args.no_open:
        threading.Timer(0.3, lambda: webbrowser.open(url)).start()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nshutting down…", file=sys.stderr)
        server.shutdown()


if __name__ == "__main__":
    main()
