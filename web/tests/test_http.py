"""Integration tests: spin up the real server in a thread, hit endpoints."""

from __future__ import annotations

import http.client
import http.server
import json
import threading
import time
from contextlib import contextmanager
from unittest.mock import patch

import pytest

from tgt_web import server


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


def _get(port: int, path: str) -> tuple[int, dict]:
    c = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    c.request("GET", path)
    r = c.getresponse()
    body = r.read()
    c.close()
    if r.getheader("Content-Type", "").startswith("application/json"):
        return r.status, json.loads(body)
    return r.status, body


def _post_json(port: int, path: str, payload: dict) -> tuple[int, dict]:
    c = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    body = json.dumps(payload)
    c.request("POST", path, body=body,
              headers={"Content-Type": "application/json"})
    r = c.getresponse()
    raw = r.read()
    c.close()
    return r.status, json.loads(raw)


@pytest.fixture
def http_server(monkeypatch):
    """Run a real server backed by the fixtures TGT_HOME."""
    # Stub probe + version_check so the server doesn't actually shell
    # out to fish / probe the user's askpass tools during the test.
    from tgt_web import sudo as sudo_mod
    from tgt_web import version_check as vc_mod
    monkeypatch.setattr(sudo_mod, "_cached", sudo_mod.SudoStatus(
        askpass=None, wrapper=None, nopasswd=True, note="(stub) NOPASSWD",
    ))
    monkeypatch.setattr(vc_mod, "check", lambda: vc_mod.VersionInfo(
        web="1.1.1", tgt="1.1.1", mismatch=False, note="(stub) match",
    ))
    with _running_server() as port:
        yield port


# ── Static + status ──────────────────────────────────────────────────────


def test_index_html_served(http_server):
    status, body = _get(http_server, "/")
    assert status == 200
    assert b"<title>tgt</title>" in body
    assert b"/app.js" in body


def test_css_served(http_server):
    status, body = _get(http_server, "/style.css")
    assert status == 200
    assert b"font-family" in body


@pytest.mark.parametrize("name,marker", [
    ("app.js", b"startEvents"),
    ("state.js", b"export const state"),
    ("helpers.js", b"export function el"),
    ("actions.js", b"export function actionResult"),
    ("render.js", b"export function renderSidebar"),
    ("forms.js", b"Alpine.data('credPw'"),
])
def test_js_modules_served(http_server, name, marker):
    """All ES modules served as static files; the static-file
    allowlist regex covers `[a-z0-9_-]+.js` so each module is
    reachable."""
    status, body = _get(http_server, f"/{name}")
    assert status == 200
    assert marker in body


def test_arbitrary_js_outside_static_404s(http_server):
    """The static-file regex constrains the name charset, so a path
    that doesn't match (uppercase letters, leading dot, etc.) gets
    rejected before the loader runs."""
    status, _ = _get(http_server, "/UPPER.js")
    assert status == 404
    status, _ = _get(http_server, "/.hidden.js")
    assert status == 404


def test_index_html_has_no_inline_event_handlers(http_server):
    """Module-loaded scripts don't put their exports on `window`,
    so HTML attributes like `onclick="refresh(true)"` can't resolve
    the name — every click would throw `refresh is not defined`.
    Caught one of these (the ↻ refresh button) live on the module-
    split PR; this test makes the regression class CI-visible.
    Every interactive control must go through `el(…)` /
    `addEventListener(…)` so the closure captures the import."""
    import re as _re
    _, body = _get(http_server, "/")
    html = body.decode("utf-8", errors="replace")
    # `on<event>=…` attributes — onclick, onsubmit, onmouseenter, etc.
    leftovers = _re.findall(r"\bon[a-z]+\s*=\s*\"[^\"]+\"", html)
    assert not leftovers, (
        "inline event-handler attributes break under "
        "<script type='module'>: " + str(leftovers)
    )


def test_vendor_alpine_served(http_server):
    """Vendored Alpine must be reachable so the <script> tag in
    index.html resolves on offline pentest boxes."""
    status, body = _get(http_server, "/vendor/alpine-3.14.1.min.js")
    assert status == 200
    assert b"Alpine" in body or b"alpine" in body or len(body) > 10000


def test_vendor_path_traversal_rejected(http_server):
    """A malicious URL must not escape the static/ subtree."""
    status, _ = _get(http_server, "/vendor/../actions.py")
    assert status == 404
    status, _ = _get(http_server, "/vendor//etc/passwd")
    assert status == 404


def test_status_endpoint(http_server):
    status, body = _get(http_server, "/api/status")
    assert status == 200
    assert body["version"] == "1.1.1"
    assert body["sudo"]["nopasswd"] is True


# ── Reader endpoints ─────────────────────────────────────────────────────


def test_scenarios_list(http_server):
    status, body = _get(http_server, "/api/scenarios")
    assert status == 200
    names = [s["name"] for s in body]
    assert "acme" in names
    assert "lab" in names


def test_scenario_detail(http_server):
    status, body = _get(http_server, "/api/scenarios/acme")
    assert status == 200
    assert body["name"] == "acme"
    creds = {c["alias"] for c in body["creds"]}
    assert creds == {"admin", "guest", "svc"}


def test_scenario_detail_unknown(http_server):
    status, _ = _get(http_server, "/api/scenarios/nope")
    assert status == 404


def test_cred_password_endpoint(http_server):
    status, body = _get(http_server, "/api/scenarios/acme/creds/admin/password")
    assert status == 200
    assert body["password"] == "hunter2"


def test_unknown_path_404(http_server):
    status, _ = _get(http_server, "/api/unknown")
    assert status == 404


# ── Action endpoint (mocked tgt) ─────────────────────────────────────────


def test_action_dispatched(http_server):
    class Result:
        returncode = 0
        stdout = "switched\n"
        stderr = ""

    with patch("tgt_web.actions.subprocess.run", return_value=Result()):
        status, body = _post_json(
            http_server, "/api/action",
            {"action": "scenario_switch", "params": {"name": "acme"}},
        )
    assert status == 200
    assert body["argv"] == ["scenario", "switch", "acme"]


def test_action_cred_new_optional_flags(http_server):
    """End-to-end: cred_new through the HTTP layer must build the
    argv the same way the unit test asserts, including dropping
    empty optional flags."""
    class Result:
        returncode = 0
        stdout = "✓ credential 'svc' created in 'acme' and activated\n"
        stderr = ""

    with patch("tgt_web.actions.subprocess.run", return_value=Result()):
        status, body = _post_json(
            http_server, "/api/action",
            {"action": "cred_new",
             "params": {"alias": "svc", "username": "svc_user",
                        "password": "", "domain": "acme.local", "notes": ""}},
        )
    assert status == 200
    assert body["argv"] == [
        "cred", "new", "svc", "--username", "svc_user", "--domain", "acme.local",
    ]


def test_action_cred_new_missing_required(http_server):
    status, body = _post_json(
        http_server, "/api/action",
        {"action": "cred_new", "params": {"alias": "x"}},
    )
    assert status == 400
    assert "username" in body["error"]


def test_action_bad_json(http_server):
    c = http.client.HTTPConnection("127.0.0.1", http_server, timeout=5)
    c.request("POST", "/api/action", body=b"{not json",
              headers={"Content-Type": "application/json"})
    r = c.getresponse()
    raw = r.read()
    c.close()
    assert r.status == 400
    assert b"bad JSON" in raw


def test_action_preview_returns_argv(http_server):
    """Preview endpoint must return the argv without invoking tgt.
    Patch subprocess.run to a tripwire so we'd notice any drift."""
    def _tripwire(*a, **kw):  # pragma: no cover
        raise AssertionError("preview must not call subprocess")
    with patch("tgt_web.actions.subprocess.run", _tripwire):
        status, body = _post_json(
            http_server, "/api/action/preview",
            {"action": "cred_rm", "params": {"alias": "svc"}},
        )
    assert status == 200
    assert body["argv"] == ["cred", "rm", "svc"]


def test_action_preview_missing_param(http_server):
    status, body = _post_json(
        http_server, "/api/action/preview",
        {"action": "cred_new", "params": {"alias": "x"}},
    )
    assert status == 400
    assert "username" in body["error"]


def test_action_preview_unknown(http_server):
    status, body = _post_json(
        http_server, "/api/action/preview",
        {"action": "does_not_exist", "params": {}},
    )
    assert status == 400
    assert "unknown action" in body["error"]


def test_action_unknown(http_server):
    status, body = _post_json(
        http_server, "/api/action",
        {"action": "does_not_exist", "params": {}},
    )
    assert status == 400
    assert "unknown action" in body["error"]


def test_action_ports_add_round_trips_comment(http_server):
    """Regression: an end-to-end POST of ports_add with both
    service AND comment must reach the fish subprocess with the
    comment intact. The JSON → params → argv → shlex pipeline
    has multiple places a value could get dropped; this test
    asserts the comment lands in the final argv that
    subprocess.run sees (subprocess itself is mocked so we don't
    need fish + a real $TGT_HOME during the test)."""
    class Result:
        returncode = 0
        stdout = "✓ added 22/tcp to test:web\n"
        stderr = ""

    with patch("tgt_web.actions.subprocess.run", return_value=Result()) as run:
        status, body = _post_json(
            http_server, "/api/action",
            {"action": "ports_add",
             "params": {"target": "web", "port": "22", "proto": "tcp",
                        "service": "ssh",
                        "comment": "OpenSSH 8.4 hardened"}},
        )
    assert status == 200
    assert body["argv"] == [
        "ports", "add", "--target", "web", "22/tcp",
        "ssh", "OpenSSH 8.4 hardened",
    ]
    # The subprocess actually got called — and the comment is
    # present in the shell-quoted command string fish receives.
    assert run.call_count == 1
    fish_cmd = run.call_args[0][0][2]   # subprocess.run([…, "-c", "tgt …"])
    assert "OpenSSH 8.4 hardened" in fish_cmd
