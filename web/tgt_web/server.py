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
import os
import re
import sys
import threading
import time
import urllib.parse
import webbrowser
from importlib import resources

from tgt_web import __version__, reader, version_check
from tgt_web.actions import dispatch_action, preview_action
from tgt_web.sudo import status as sudo_status

# Watcher tick interval. Each tick walks $TGT_HOME and re-probes the
# fish universal var `TGT_SCENARIO`. The fish probe is the expensive
# part (~30 ms subprocess); 1.5 s gives sub-2 s cross-shell sync
# without burning a fish per second.
# TODO: when this proves too costly on battery, gate the fish probe
# behind a fish_variables mtime check (the universal-var file lives
# at ~/.config/fish/fish_variables; only re-probe when that ticks).
_WATCH_INTERVAL = 1.5
# Heartbeat cadence on idle SSE connections. Doubles as dead-socket
# detection: a write to a half-open TCP socket raises here, ending
# the handler so the client can reconnect.
_SSE_HEARTBEAT = 25.0

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


class _EventBroker:
    """In-process change-notification fan-out.

    One background thread watches $TGT_HOME + fish universal-var state
    and calls `bump()` when something changes. Each open SSE handler
    calls `wait(last_gen)` to block until the next bump (or timeout
    for heartbeat). The generation counter is monotonic so a client
    that briefly disconnects can resync by comparing its last-seen
    gen to the current one — though in practice EventSource reconnects
    fast enough that a full refresh on every reconnect is fine.
    """
    def __init__(self) -> None:
        self._cond = threading.Condition()
        self._gen = 0
        self._watcher_started = False

    @property
    def gen(self) -> int:
        with self._cond:
            return self._gen

    def bump(self) -> None:
        with self._cond:
            self._gen += 1
            self._cond.notify_all()

    def wait(self, last_seen: int, timeout: float) -> int:
        """Block until the generation moves past `last_seen`, or
        until `timeout` elapses. Returns the current generation
        either way; caller compares to `last_seen` to detect change."""
        with self._cond:
            if self._gen != last_seen:
                return self._gen
            self._cond.wait(timeout=timeout)
            return self._gen

    def start_watcher(self) -> None:
        if self._watcher_started:
            return
        self._watcher_started = True
        t = threading.Thread(target=self._watch_loop, daemon=True,
                             name="tgt-web-watcher")
        t.start()

    def _watch_loop(self) -> None:
        last_sig: tuple | None = None
        while True:
            try:
                sig = _tgt_home_signature()
            except Exception as e:  # pragma: no cover — defensive
                sys.stderr.write(f"[watcher] signature error: {e}\n")
                sig = None
            if last_sig is not None and sig is not None and sig != last_sig:
                self.bump()
            if sig is not None:
                last_sig = sig
            time.sleep(_WATCH_INTERVAL)


_broker = _EventBroker()


def _tgt_home_signature() -> tuple:
    """Cheap-but-complete fingerprint of every input that can change
    what the UI shows. Walks $TGT_HOME for file mtimes + sizes, and
    explicitly re-probes the active scenario (which lives in a fish
    universal var, not on $TGT_HOME). Returns a hashable tuple."""
    home = reader.tgt_home()
    entries: list[tuple] = []
    if home.exists():
        for dirpath, dirnames, filenames in os.walk(home):
            dirnames.sort()
            for name in sorted(filenames):
                p = os.path.join(dirpath, name)
                try:
                    st = os.stat(p)
                except OSError:
                    continue
                rel = os.path.relpath(p, home)
                entries.append((rel, st.st_mtime_ns, st.st_size))
            # Also track empty dirs / dir-only state (e.g. .archived
            # is a file, but a brand-new empty scenario/foo/ dir
            # should still register).
            for name in sorted(dirnames):
                entries.append(("d:" + os.path.relpath(
                    os.path.join(dirpath, name), home),))
    # Bypass the 1 s active-scenario cache: we are the cache invalidator.
    reader.invalidate_active_cache()
    entries.append(("__active__", reader.read_active_scenario()))
    return tuple(entries)


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

    def _send_events(self) -> None:
        """Stream `text/event-stream` to a single client. Returns
        when the socket dies; ThreadingHTTPServer's daemon thread
        gets cleaned up automatically on process exit."""
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        # X-Accel-Buffering disables buffering on nginx-style proxies.
        # Not load-bearing for localhost, but cheap insurance and the
        # canonical SSE header.
        self.send_header("X-Accel-Buffering", "no")
        self.end_headers()
        try:
            # Capture the generation BEFORE we announce readiness so
            # any bump that races with the write is still delivered.
            # If we sampled after the write, a bump in between would
            # advance `_broker.gen` to match `last`, and we'd silently
            # miss it until the next change.
            last = _broker.gen
            # Reconnect after 3 s if the connection dies, then announce
            # we're live so the client can clear any "connecting…" UI.
            self.wfile.write(b"retry: 3000\n\n")
            self.wfile.write(f"event: ready\ndata: {last}\n\n".encode("utf-8"))
            self.wfile.flush()
            while True:
                new_gen = _broker.wait(last, timeout=_SSE_HEARTBEAT)
                if new_gen != last:
                    self.wfile.write(
                        f"event: change\ndata: {new_gen}\n\n".encode("utf-8"))
                    last = new_gen
                else:
                    # SSE comment line. EventSource ignores it; the
                    # write itself is what we care about (raises on
                    # dead socket so we exit cleanly).
                    self.wfile.write(b": heartbeat\n\n")
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, OSError):
            return

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
        if path == "/api/events":
            return self._send_events()
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
            # Notify other connected tabs immediately. The watcher
            # would catch this within ~1.5 s anyway, but bumping here
            # is free and gives same-host multi-tab UIs instant sync.
            if status == 200 and result.get("rc") == 0:
                _broker.bump()
            return self._send_json(status, result)
        if path == "/api/action/preview":
            # Read-only: validates + returns the argv that would be
            # sent to `tgt`, without spawning a subprocess. Used by
            # the confirm modal to surface "$ tgt …" before commit.
            action = body.get("action", "")
            params = body.get("params", {}) or {}
            status, result = preview_action(action, params)
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
    _broker.start_watcher()

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
