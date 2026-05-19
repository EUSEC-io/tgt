"""Tests for the SSE broker + `/api/events` endpoint.

The broker tests exercise wait/bump/timeout semantics without touching
HTTP. The endpoint test opens a streaming connection, calls
`_broker.bump()` from the test thread, and asserts the corresponding
`change` event arrives.
"""

from __future__ import annotations

import http.client
import http.server
import threading
import time
from contextlib import contextmanager
from unittest.mock import patch

import pytest

from tgt_web import server


# ── Broker unit tests ────────────────────────────────────────────────────


def test_broker_wait_returns_immediately_when_already_advanced():
    """A wait() whose `last_seen` is already behind the current gen
    must return at once with the new gen — no need to block for a
    second bump."""
    b = server._EventBroker()
    b.bump()
    assert b.wait(last_seen=0, timeout=1.0) == 1


def test_broker_wait_blocks_until_bump():
    """wait() should block until another thread bumps."""
    b = server._EventBroker()
    seen = []

    def waiter():
        seen.append(b.wait(last_seen=0, timeout=2.0))

    t = threading.Thread(target=waiter)
    t.start()
    # Give the waiter a beat to enter wait()
    time.sleep(0.05)
    b.bump()
    t.join(timeout=1.0)
    assert seen == [1]


def test_broker_wait_times_out_with_no_change():
    """When no bump arrives, wait() returns the unchanged generation
    after `timeout` — that's the heartbeat path in the SSE handler."""
    b = server._EventBroker()
    t0 = time.monotonic()
    gen = b.wait(last_seen=0, timeout=0.05)
    elapsed = time.monotonic() - t0
    assert gen == 0
    assert 0.04 <= elapsed < 0.3  # generous to avoid CI flake


# ── Endpoint integration ─────────────────────────────────────────────────


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


@pytest.fixture
def http_server(monkeypatch):
    from tgt_web import sudo as sudo_mod
    from tgt_web import version_check as vc_mod
    monkeypatch.setattr(sudo_mod, "_cached", sudo_mod.SudoStatus(
        askpass=None, wrapper=None, nopasswd=True, note="(stub) NOPASSWD",
    ))
    monkeypatch.setattr(vc_mod, "check", lambda: vc_mod.VersionInfo(
        web="0.1.0", tgt="0.1.0", mismatch=False, note="(stub) match",
    ))
    # Reset the broker between tests so generations are predictable.
    monkeypatch.setattr(server, "_broker", server._EventBroker())
    with _running_server() as port:
        yield port


def _read_until(fp, marker: bytes, timeout: float) -> bytes:
    """Read line-by-line from a binary file-like until `marker` is
    found in the accumulated bytes or `timeout` elapses."""
    deadline = time.monotonic() + timeout
    buf = b""
    while time.monotonic() < deadline:
        line = fp.readline()
        if not line:
            break
        buf += line
        if marker in buf:
            return buf
    raise AssertionError(
        f"timed out waiting for {marker!r}; got {buf!r}")


def test_events_endpoint_headers_and_ready(http_server):
    """GET /api/events returns 200 with the SSE content-type and an
    initial `ready` event so the client knows the stream is live."""
    c = http.client.HTTPConnection("127.0.0.1", http_server, timeout=5)
    c.request("GET", "/api/events")
    r = c.getresponse()
    assert r.status == 200
    assert r.getheader("Content-Type", "").startswith("text/event-stream")
    assert r.getheader("Cache-Control") == "no-cache"
    body = _read_until(r.fp, b"event: ready", timeout=2.0)
    assert b"retry: 3000" in body
    c.close()


def test_events_endpoint_delivers_change_on_bump(http_server):
    """A `_broker.bump()` from the test thread must produce a
    `change` event on every open SSE connection."""
    c = http.client.HTTPConnection("127.0.0.1", http_server, timeout=5)
    c.request("GET", "/api/events")
    r = c.getresponse()
    assert r.status == 200
    _read_until(r.fp, b"event: ready", timeout=2.0)
    server._broker.bump()
    body = _read_until(r.fp, b"event: change", timeout=2.0)
    assert b"event: change" in body
    c.close()


def test_action_dispatch_bumps_broker(http_server):
    """Successful action dispatch should bump the broker so other
    connected tabs refresh without waiting for the watcher tick."""
    class Result:
        returncode = 0
        stdout = "ok\n"
        stderr = ""

    gen_before = server._broker.gen
    c = http.client.HTTPConnection("127.0.0.1", http_server, timeout=5)
    import json as _json
    body = _json.dumps({"action": "scenario_switch",
                        "params": {"name": "acme"}})
    with patch("tgt_web.actions.subprocess.run", return_value=Result()):
        c.request("POST", "/api/action", body=body,
                  headers={"Content-Type": "application/json"})
        r = c.getresponse()
        r.read()
    c.close()
    assert r.status == 200
    assert server._broker.gen == gen_before + 1


def test_action_dispatch_does_not_bump_on_failure(http_server):
    """A non-zero `tgt` exit must not bump — UI state hasn't actually
    changed, and a bump would trigger a needless refresh."""
    class Result:
        returncode = 1
        stdout = ""
        stderr = "boom\n"

    gen_before = server._broker.gen
    c = http.client.HTTPConnection("127.0.0.1", http_server, timeout=5)
    import json as _json
    body = _json.dumps({"action": "scenario_switch",
                        "params": {"name": "acme"}})
    with patch("tgt_web.actions.subprocess.run", return_value=Result()):
        c.request("POST", "/api/action", body=body,
                  headers={"Content-Type": "application/json"})
        r = c.getresponse()
        r.read()
    c.close()
    # dispatch_action maps rc != 0 onto HTTP 500.
    assert r.status == 500
    assert server._broker.gen == gen_before
