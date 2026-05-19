"""HTTP plumbing for tgt-web.

Localhost-only server (`127.0.0.1`, no auth — same single-user
threat model as `fish_config`). Reads delegate to `reader`; writes
delegate to `actions`; sudo strategy is decided once at startup by
`sudo.probe`.

Static assets ship inside the installed package — we load them via
`importlib.resources` so `pipx install` works without separate
asset-deploy steps.
"""

from __future__ import annotations

import argparse
import http.server
import json
import re
import sys
import threading
import time
import urllib.parse
import webbrowser
from importlib import resources

from tgt_web import __version__, reader, version_check
from tgt_web.actions import dispatch_action
from tgt_web.sudo import status as sudo_status

# Cache static assets in memory at startup so request handlers don't
# hit the filesystem (or zipimporter) on every GET. `pipx install`
# always lays the package out on disk, so `Traversable.read_*` is
# cheap; caching is just hygiene.
_static_cache: dict[str, bytes] = {}


def _load_static(name: str) -> bytes:
    """Load a static asset by name. Accepts either `foo.ext` (top of
    static/) or `vendor/foo.ext` (one level under). Rejects anything
    with `..` or absolute paths so a malicious URL can't escape
    into the package."""
    if ".." in name.split("/") or name.startswith("/"):
        raise FileNotFoundError(name)
    if name not in _static_cache:
        # `MultiplexedPath.joinpath()` in Python 3.10–3.12 takes a
        # single argument — variadic `joinpath(*parts)` raises
        # TypeError on CI. Chain instead. (Python 3.13's Traversable
        # accepts multiple, which is what masked this locally.)
        trav = resources.files("tgt_web.static")
        for part in name.split("/"):
            trav = trav.joinpath(part)
        _static_cache[name] = trav.read_bytes()
    return _static_cache[name]


_CONTENT_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".css":  "text/css; charset=utf-8",
    ".js":   "application/javascript; charset=utf-8",
}


# Startup state surfaced via /api/status.
_startup: dict = {}


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        sys.stderr.write(
            f"[{time.strftime('%H:%M:%S')}] {self.address_string()} - {fmt % args}\n"
        )

    def _send_json(self, status: int, body: object) -> None:
        data = json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _send_static(self, name: str) -> None:
        try:
            data = _load_static(name)
        except (FileNotFoundError, ModuleNotFoundError):
            return self._send_json(404, {"error": "not found"})
        ext = "." + name.rsplit(".", 1)[-1] if "." in name else ""
        self.send_response(200)
        self.send_header("Content-Type", _CONTENT_TYPES.get(ext, "application/octet-stream"))
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self) -> None:
        path = urllib.parse.urlparse(self.path).path
        if path == "/" or path == "/index.html":
            return self._send_static("index.html")
        if path == "/style.css":
            return self._send_static("style.css")
        if path == "/app.js":
            return self._send_static("app.js")
        if path.startswith("/vendor/"):
            return self._send_static("vendor/" + path[len("/vendor/"):])
        if path == "/api/status":
            return self._send_json(200, _startup)
        if path == "/api/scenarios":
            return self._send_json(200, reader.list_scenarios())
        m = re.match(r"^/api/scenarios/([^/]+)$", path)
        if m:
            d = reader.scenario_detail(urllib.parse.unquote(m.group(1)))
            if d is None:
                return self._send_json(404, {"error": "not found"})
            return self._send_json(200, d)
        m = re.match(r"^/api/scenarios/([^/]+)/creds/([^/]+)/password$", path)
        if m:
            scen = urllib.parse.unquote(m.group(1))
            alias = urllib.parse.unquote(m.group(2))
            return self._send_json(200, {"password": reader.cred_password(scen, alias)})
        return self._send_json(404, {"error": "not found"})

    def do_POST(self) -> None:
        path = urllib.parse.urlparse(self.path).path
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length > 0 else b""
        try:
            body = json.loads(raw or b"{}")
        except json.JSONDecodeError:
            return self._send_json(400, {"error": "bad JSON"})
        if path == "/api/action":
            action = body.get("action", "")
            params = body.get("params", {}) or {}
            status, result = dispatch_action(action, params)
            return self._send_json(status, result)
        return self._send_json(404, {"error": "not found"})


def _populate_startup() -> None:
    """Compute startup banner state once. Surfaced via /api/status."""
    s = sudo_status()
    v = version_check.check()
    _startup.update({
        "version": __version__,
        "tgt_version": v.tgt,
        "version_mismatch": v.mismatch,
        "version_note": v.note,
        "sudo": {
            "askpass": s.askpass,
            "nopasswd": s.nopasswd,
            "note": s.note,
        },
    })


def _log_banner() -> None:
    s = sudo_status()
    v = version_check.check()
    print(f"tgt-web {__version__}", file=sys.stderr)
    print(f"  fish-side tgt: {v.tgt or '(not found)'} — {v.note}", file=sys.stderr)
    if s.askpass:
        print(f"  sudo: {s.note}", file=sys.stderr)
    elif s.nopasswd:
        print(f"  sudo: {s.note}", file=sys.stderr)
    else:
        print("  sudo: WARNING — no graphical helper and no NOPASSWD", file=sys.stderr)
        for line in s.note.splitlines():
            print(f"        {line}", file=sys.stderr)


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="tgt-web",
        description="Local browser UI for the tgt fish plugin.",
    )
    parser.add_argument(
        "--port", type=int, default=0,
        help="port to bind (0 = pick an unused one)",
    )
    parser.add_argument(
        "--no-open", action="store_true",
        help="don't auto-open the browser",
    )
    parser.add_argument(
        "--version", action="version", version=f"tgt-web {__version__}",
    )
    args = parser.parse_args()

    _populate_startup()
    _log_banner()

    server = http.server.ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    port = server.server_address[1]
    url = f"http://127.0.0.1:{port}/"
    print(f"  serving: {url}  (Ctrl-C to stop)", file=sys.stderr)

    if not args.no_open:
        threading.Timer(0.3, lambda: webbrowser.open(url)).start()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nshutting down…", file=sys.stderr)
        server.shutdown()


if __name__ == "__main__":
    main()
