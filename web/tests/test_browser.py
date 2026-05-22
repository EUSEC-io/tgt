"""Headless-browser smoke test.

Loads `/` in chromium via Playwright, scrapes the console and any
uncaught page errors, and fails the test if anything's there.

Skipped when Playwright isn't installed. Add it explicitly:
    pip install playwright && python -m playwright install chromium

Caught the module-split regression on 2026-05-20: Alpine 3 calls
`Alpine.start()` at the end of its script (not on DOMContentLoaded),
so the script-tag ordering matters — module must execute before
Alpine so the alpine:init listener is attached when Alpine fires
the event. The `node --check` CI gate is a static parser; this is
the only thing that catches runtime-only regressions like that.
"""
from __future__ import annotations

import http.server
import threading
import time
from contextlib import contextmanager

import pytest

playwright = pytest.importorskip("playwright.sync_api")

from tgt_web import server  # noqa: E402


@contextmanager
def _running_server():
    server._populate_startup()
    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
    port = httpd.server_address[1]
    t = threading.Thread(target=httpd.serve_forever, daemon=True)
    t.start()
    try:
        yield port
    finally:
        httpd.shutdown()
        httpd.server_close()


def test_dashboard_loads_without_console_errors(monkeypatch):
    """A clean `/` load must produce zero console errors / warnings
    and zero uncaught page errors. Asserting the absence is what
    catches the module-load-order class of bug."""
    from tgt_web import sudo as sudo_mod
    from tgt_web import version_check as vc_mod
    monkeypatch.setattr(sudo_mod, "_cached", sudo_mod.SudoStatus(
        askpass=None, wrapper=None, nopasswd=True, note="(stub) NOPASSWD",
    ))
    monkeypatch.setattr(vc_mod, "check", lambda: vc_mod.VersionInfo(
        web="1.1.1", tgt="1.1.1", mismatch=False, note="(stub) match",
    ))

    console, errors = [], []
    with _running_server() as port:
        with playwright.sync_playwright() as p:
            browser = p.chromium.launch()
            page = browser.new_page()
            page.on("console", lambda m: console.append((m.type, m.text)))
            page.on("pageerror", lambda e: errors.append(str(e)))
            # `networkidle` won't fire because the SSE stream stays
            # open. `load` is the right signal — DOM is parsed,
            # deferred + module scripts have executed.
            page.goto(f"http://127.0.0.1:{port}/", wait_until="load")
            # Give the initial fetches + render a beat to settle.
            time.sleep(1.0)
            browser.close()

    bad_console = [c for c in console if c[0] in ("error", "warning")]
    assert not bad_console, f"console errors / warnings: {bad_console}"
    assert not errors, f"uncaught page errors: {errors}"
