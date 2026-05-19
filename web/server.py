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
html, body { height: 100%; margin: 0; }
body { font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
       background: #0e1116; color: #c9d1d9; font-size: 13px; line-height: 1.5;
       display: flex; flex-direction: column; }

header { display: flex; justify-content: space-between; align-items: center;
         border-bottom: 1px solid #30363d; padding: 12px 20px;
         background: #161b22; flex-shrink: 0; }
header h1 { font-size: 16px; margin: 0; color: #58a6ff; }
.header-mid { color: #8b949e; font-size: 12px; }
.header-mid .active-name { color: #56d364; font-weight: 600; }
.header-right { display: flex; gap: 12px; align-items: center; font-size: 11px; color: #8b949e; }
.header-right label { display: flex; align-items: center; gap: 4px; cursor: pointer; user-select: none; }
.header-right input[type=checkbox] { cursor: pointer; }

.layout { display: flex; flex: 1; min-height: 0; }
aside { width: 260px; flex-shrink: 0; border-right: 1px solid #30363d;
        background: #0e1116; display: flex; flex-direction: column; }
aside .filter-row { padding: 10px; border-bottom: 1px solid #21262d; }
aside .filter-row input { width: 100%; background: #0d1117; color: #c9d1d9;
                          border: 1px solid #30363d; padding: 6px 8px;
                          border-radius: 3px; font-family: inherit; font-size: 12px; }
aside .filter-row input:focus { outline: none; border-color: #58a6ff; }
#scenario-list { list-style: none; padding: 0; margin: 0; overflow-y: auto; flex: 1; }
#scenario-list li { padding: 8px 12px; cursor: pointer; border-left: 3px solid transparent;
                    display: flex; justify-content: space-between; align-items: center;
                    gap: 8px; font-size: 12px; }
#scenario-list li:hover { background: #161b22; }
#scenario-list li.selected { background: #161b22; border-left-color: #58a6ff; }
#scenario-list li.active .name { color: #56d364; font-weight: 600; }
#scenario-list li.archived .name { color: #6e7681; font-style: italic; }
#scenario-list li .counts { color: #6e7681; font-size: 10px; flex-shrink: 0; }

main { flex: 1; overflow-y: auto; padding: 20px 24px; }
main h2 { font-size: 11px; color: #8b949e; text-transform: uppercase;
          letter-spacing: 0.5px; margin: 20px 0 6px; font-weight: 600; }
main h2:first-child { margin-top: 0; }
main .scen-title { font-size: 18px; color: #58a6ff; margin: 0 0 4px;
                   font-weight: 600; text-transform: none; letter-spacing: 0; }
main .scen-meta { color: #8b949e; font-size: 11px; margin-bottom: 8px; }
main .scen-meta .badge { display: inline-block; padding: 1px 6px; border-radius: 3px;
                         margin-right: 6px; font-size: 10px; }
main .scen-meta .badge.active { background: #1f3a1f; color: #56d364; }
main .scen-meta .badge.archived { background: #2a2a2a; color: #8b949e; }
main .scen-actions { margin: 8px 0 16px; display: flex; gap: 6px; }

table { border-collapse: collapse; width: 100%; margin-bottom: 8px; }
th, td { text-align: left; padding: 5px 8px; border-bottom: 1px solid #21262d; font-size: 12px; }
th { color: #8b949e; font-weight: 600; font-size: 10px;
     text-transform: uppercase; letter-spacing: 0.5px; }
tr:hover td { background: #161b22; }
td.active { color: #56d364; font-weight: 600; }
td.active::before { content: "★ "; }
td .reveal { cursor: pointer; color: #6e7681; text-decoration: underline; font-size: 11px; }
td .reveal:hover { color: #c9d1d9; }
td .pw-value { color: #f85149; }

button { background: #21262d; color: #c9d1d9; border: 1px solid #30363d;
         padding: 3px 8px; cursor: pointer; font-family: inherit;
         font-size: 10px; border-radius: 3px; }
button:hover { background: #30363d; }
button.primary { background: #1f6feb; border-color: #1f6feb; color: white; }
button.primary:hover { background: #388bfd; }
button.refresh { padding: 4px 10px; font-size: 11px; }

.toast { position: fixed; bottom: 20px; right: 20px; background: #21262d;
         border: 1px solid #30363d; padding: 8px 12px; border-radius: 4px;
         opacity: 0; transition: opacity 0.2s; max-width: 400px;
         font-size: 12px; z-index: 100; }
.toast.show { opacity: 1; }
.toast.error { border-color: #f85149; }
.toast.success { border-color: #56d364; }
.empty { color: #6e7681; font-style: italic; padding: 8px 0; font-size: 12px; }
.placeholder { color: #6e7681; font-style: italic; text-align: center; padding: 40px; }
</style>
</head>
<body>

<header>
  <h1>tgt</h1>
  <div class="header-mid" id="active-info"></div>
  <div class="header-right">
    <label><input type="checkbox" id="show-archived"> show archived</label>
    <button class="refresh" onclick="refresh(true)">↻ refresh</button>
  </div>
</header>

<div class="layout">
  <aside>
    <div class="filter-row"><input id="filter" placeholder="filter scenarios…" autocomplete="off"></div>
    <ul id="scenario-list"></ul>
  </aside>
  <main id="detail"><div class="placeholder">Select a scenario from the list.</div></main>
</div>

<div id="toast" class="toast"></div>

<script>
// ────────────────────────── state + cache ─────────────────────────────
const state = {
  selected: null,        // scenario name currently shown in detail pane
  filter: '',            // sidebar substring filter
  showArchived: false,   // toggle for hiding archived scenarios
  scenariosHash: '',     // for skip-render-on-no-change
  detailHash: '',
  scenariosData: [],     // cache so filter/toggle don't refetch
  detailData: null,
};

// ────────────────────────── helpers ───────────────────────────────────
async function api(path, opts) {
  const r = await fetch(path, opts);
  if (!r.ok) throw new Error(await r.text());
  return r.json();
}

function djb2(s) {
  let h = 5381;
  for (let i = 0; i < s.length; i++) h = ((h << 5) + h) ^ s.charCodeAt(i);
  return h.toString(16);
}

function toast(msg, kind) {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.className = 'toast show ' + (kind || '');
  setTimeout(() => { t.className = 'toast'; }, 2500);
}

function el(tag, attrs, ...children) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (k === 'onclick') e.onclick = v;
    else if (k === 'class') e.className = v;
    else e.setAttribute(k, v);
  }
  for (const c of children) {
    if (c == null || c === false) continue;
    e.append(typeof c === 'string' ? document.createTextNode(c) : c);
  }
  return e;
}

async function act(name, params) {
  try {
    const r = await api('/api/action', {
      method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({ action: name, params: params || {} }),
    });
    if (r.rc === 0) toast('✓ ' + (r.stdout.trim().split('\\n').pop() || name), 'success');
    else toast('error: ' + (r.stderr || '').trim(), 'error');
    await refresh(true);
  } catch (e) { toast('error: ' + e.message, 'error'); }
}

async function revealPassword(scenario, alias, span) {
  try {
    const r = await api(`/api/scenarios/${encodeURIComponent(scenario)}/creds/${encodeURIComponent(alias)}/password`);
    span.outerHTML = `<span class="pw-value"></span>`;
    span.parentNode.querySelector('.pw-value').textContent = r.password || '(empty)';
  } catch (e) { toast('reveal failed: ' + e.message, 'error'); }
}

// ────────────────────────── render: sidebar ───────────────────────────
function renderSidebar() {
  const list = document.getElementById('scenario-list');
  list.innerHTML = '';
  const filtered = state.scenariosData.filter(s => {
    if (!state.showArchived && s.archived) return false;
    if (state.filter && !s.name.toLowerCase().includes(state.filter.toLowerCase())) return false;
    return true;
  });
  if (filtered.length === 0) {
    list.append(el('li', {class: 'empty'}, '(no matches)'));
    return;
  }
  for (const s of filtered) {
    const li = el('li', {
      class: [
        s.active ? 'active' : '',
        s.archived ? 'archived' : '',
        s.name === state.selected ? 'selected' : '',
      ].filter(Boolean).join(' '),
      onclick: () => {
        state.selected = s.name;
        refresh(true);
      },
    },
      el('span', {class: 'name'}, s.name),
      el('span', {class: 'counts'},
         `${s.target_count}t · ${s.cred_count}c · ${s.dc_count}d`));
    list.append(li);
  }
}

function renderActiveInfo() {
  const el2 = document.getElementById('active-info');
  const active = state.scenariosData.find(s => s.active);
  if (active) {
    el2.innerHTML = 'active: <span class="active-name">' + active.name + '</span>';
  } else {
    el2.textContent = '(no active scenario)';
  }
}

// ────────────────────────── render: detail ────────────────────────────
function renderDetail() {
  const main = document.getElementById('detail');
  main.innerHTML = '';
  const d = state.detailData;
  if (!d) {
    main.append(el('div', {class: 'placeholder'}, 'Select a scenario from the list.'));
    return;
  }

  // Title + meta
  main.append(el('div', {class: 'scen-title'}, d.name));
  const meta = el('div', {class: 'scen-meta'});
  if (d.active) meta.append(el('span', {class: 'badge active'}, 'ACTIVE'));
  if (d.archived) meta.append(el('span', {class: 'badge archived'}, 'ARCHIVED'));
  meta.append(document.createTextNode(
    `${d.targets.length} target(s), ${d.creds.length} cred(s), ${d.dcs.length} DC(s)`));
  main.append(meta);

  // Scenario-level actions
  const actions = el('div', {class: 'scen-actions'});
  if (d.active) {
    actions.append(el('button', {onclick: () => act('scenario_unload')}, 'unload'));
  } else {
    actions.append(el('button', {class: 'primary',
      onclick: () => act('scenario_switch', {name: d.name})}, 'switch to'));
  }
  actions.append(el('button', {
    onclick: () => act(d.archived ? 'scenario_unarchive' : 'scenario_archive', {name: d.name})
  }, d.archived ? 'unarchive' : 'archive'));
  main.append(actions);

  // Targets
  main.append(el('h2', {}, `targets (${d.targets.length})`));
  if (d.targets.length === 0) main.append(el('div', {class: 'empty'}, '(none)'));
  else main.append(el('table', {},
    el('thead', {}, el('tr', {}, el('th', {}, 'alias'), el('th', {}, 'host'),
                        el('th', {}, 'hostnames'), el('th', {}, ''))),
    el('tbody', {}, ...d.targets.map(t => el('tr', {},
      el('td', {}, t.alias),
      el('td', {}, t.host || '—'),
      el('td', {}, t.hosts.join(', ') || '—'),
      el('td', {}, d.active
        ? el('button', {onclick: () => act('target_switch', {alias: t.alias})}, 'switch')
        : ''))))));

  // Creds
  main.append(el('h2', {}, `credentials (${d.creds.length})`));
  if (d.creds.length === 0) main.append(el('div', {class: 'empty'}, '(none)'));
  else main.append(el('table', {},
    el('thead', {}, el('tr', {}, el('th', {}, 'alias'), el('th', {}, 'username'),
                        el('th', {}, 'password'), el('th', {}, 'domain'),
                        el('th', {}, 'notes'), el('th', {}, ''))),
    el('tbody', {}, ...d.creds.map(c => {
      const pwCell = c.has_password
        ? el('span', {class: 'reveal', onclick: function() { revealPassword(d.name, c.alias, this); }}, 'reveal')
        : document.createTextNode('—');
      return el('tr', {},
        el('td', {class: c.active ? 'active' : ''}, c.alias),
        el('td', {}, c.username),
        el('td', {}, pwCell),
        el('td', {}, c.domain || '—'),
        el('td', {}, c.notes || '—'),
        el('td', {},
          d.active && !c.active
            ? el('button', {onclick: () => act('cred_switch', {alias: c.alias})}, 'switch')
            : (c.active ? el('button', {onclick: () => act('cred_unset')}, 'unset') : '')));
    }))));

  // DCs
  main.append(el('h2', {}, `DCs (${d.dcs.length})`));
  if (d.dcs.length === 0) main.append(el('div', {class: 'empty'}, '(none)'));
  else main.append(el('table', {},
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
}

// ────────────────────────── refresh orchestrator ──────────────────────
// `force=true` always re-renders. Without force, we hash the new data
// and skip the DOM rebuild when nothing changed — that kills the flicker
// during idle polling, while still picking up cross-shell state changes.
async function refresh(force) {
  try {
    const scenarios = await api('/api/scenarios');
    const sHash = djb2(JSON.stringify(scenarios));
    if (force || sHash !== state.scenariosHash) {
      state.scenariosData = scenarios;
      state.scenariosHash = sHash;
      renderSidebar();
      renderActiveInfo();
    }
    // If nothing's selected yet, fall back to the active scenario.
    const target = state.selected
      || (state.scenariosData.find(s => s.active) || {}).name;
    if (target) {
      const detail = await api(`/api/scenarios/${encodeURIComponent(target)}`);
      const dHash = djb2(JSON.stringify(detail));
      if (force || dHash !== state.detailHash) {
        state.detailData = detail;
        state.detailHash = dHash;
        state.selected = target;       // sync selection if it came from active
        renderDetail();
        // Re-render sidebar so the "selected" highlight tracks the detail pane.
        renderSidebar();
      }
    }
  } catch (e) {
    toast('refresh failed: ' + e.message, 'error');
  }
}

// ────────────────────────── input wiring ──────────────────────────────
document.getElementById('filter').addEventListener('input', (e) => {
  state.filter = e.target.value;
  renderSidebar();
});
document.getElementById('show-archived').addEventListener('change', (e) => {
  state.showArchived = e.target.checked;
  renderSidebar();
});

// Initial load + polite poll (every 10s, no DOM churn unless data changed).
refresh(true);
setInterval(() => refresh(false), 10000);
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
