"""Dispatch tests: argv-building correctness with subprocess mocked."""

from __future__ import annotations

from unittest.mock import patch

import pytest

from tgt_web import actions


def _fake_run(rc=0, stdout="", stderr=""):
    class R:
        returncode = rc
        def __init__(self, *a, **kw): pass

    class Recorder:
        captured = None
        def __call__(self, argv, **kw):
            Recorder.captured = (argv, kw)
            class Result:
                pass
            r = Result()
            r.returncode = rc
            r.stdout = stdout
            r.stderr = stderr
            return r
    return Recorder()


def test_unknown_action_returns_400():
    status, body = actions.dispatch_action("does_not_exist", {})
    assert status == 400
    assert "unknown action" in body["error"]


def test_missing_param_returns_400():
    status, body = actions.dispatch_action("scenario_switch", {})
    assert status == 400
    assert "missing param" in body["error"]
    assert "name" in body["error"]


@pytest.mark.parametrize(
    "action,params,expected_tail",
    [
        ("scenario_new",       {"name": "lab"},   ["scenario", "new", "lab"]),
        ("scenario_switch",    {"name": "acme"},  ["scenario", "switch", "acme"]),
        ("scenario_unload",    {},                ["scenario", "unload"]),
        ("scenario_archive",   {"name": "old"},   ["scenario", "archive", "old"]),
        ("scenario_unarchive", {"name": "old"},   ["scenario", "unarchive", "old"]),
        ("target_switch",      {"alias": "web"},  ["switch", "web"]),
        ("target_revoke",      {},                ["revoke"]),
        ("cred_switch",        {"alias": "adm"},  ["cred", "switch", "adm"]),
        ("cred_unset",         {},                ["cred", "unset"]),
        ("dc_switch",          {"alias": "dc01"}, ["dc", "switch", "dc01"]),
        ("dc_unset",           {},                ["dc", "unset"]),
    ],
)
def test_argv_builders(action, params, expected_tail):
    recorder = _fake_run(rc=0, stdout="ok\n")
    with patch("tgt_web.actions.subprocess.run", recorder):
        status, body = actions.dispatch_action(action, params)
    assert status == 200
    assert body["rc"] == 0
    assert body["argv"] == expected_tail
    # The recorded invocation is `fish -c 'tgt …'`; assert the
    # quoted tail covers every arg.
    argv, _ = recorder.captured
    assert argv[0] == "fish"
    assert argv[1] == "-c"
    for token in expected_tail:
        assert token in argv[2]


def test_preview_unknown_action_returns_400():
    status, body = actions.preview_action("does_not_exist", {})
    assert status == 400
    assert "unknown action" in body["error"]


def test_preview_missing_param_returns_400():
    status, body = actions.preview_action("scenario_switch", {})
    assert status == 400
    assert "missing param" in body["error"]


def test_preview_returns_argv_without_subprocess(monkeypatch):
    """preview must not spawn a subprocess. Sentinel: any call to
    subprocess.run during preview fails the test."""
    def _explode(*a, **kw):  # pragma: no cover
        raise AssertionError("preview must not call subprocess")
    monkeypatch.setattr("tgt_web.actions.subprocess.run", _explode)
    status, body = actions.preview_action(
        "cred_new", {"alias": "svc", "username": "svc_user",
                     "domain": "acme.local"}
    )
    assert status == 200
    assert body["argv"] == [
        "cred", "new", "svc", "--username", "svc_user", "--domain", "acme.local",
    ]
    # preview surfaces only the argv — no rc/stdout/stderr noise.
    assert "rc" not in body
    assert "stdout" not in body
    assert "stderr" not in body


def test_nonzero_exit_returns_500():
    recorder = _fake_run(rc=1, stderr="boom\n")
    with patch("tgt_web.actions.subprocess.run", recorder):
        status, body = actions.dispatch_action("scenario_unload", {})
    assert status == 500
    assert body["stderr"] == "boom\n"
    assert body["rc"] == 1


def test_subprocess_env_disables_gum_and_injects_askpass(monkeypatch):
    """Web is non-interactive — TGT_NO_GUM must reach the fish env."""
    monkeypatch.setattr(
        "tgt_web.actions.sudo.prepare_env",
        lambda env: {**env, "SUDO_ASKPASS": "/tmp/wrapper.sh"},
    )
    recorder = _fake_run(rc=0)
    with patch("tgt_web.actions.subprocess.run", recorder):
        actions.dispatch_action("scenario_unload", {})
    _, kw = recorder.captured
    assert kw["env"]["TGT_NO_GUM"] == "1"
    assert kw["env"]["SUDO_ASKPASS"] == "/tmp/wrapper.sh"


def test_ansi_codes_stripped_from_output():
    """Toast in the UI should never show raw escape sequences. Strip
    them server-side regardless of whether fish suppressed them.

    Covers both CSI (`ESC [ … final`) and charset-designation
    (`ESC ( c` / `ESC ) c`) forms. The charset case was a real
    regression: fish's `set_color normal` emits `\\x1b(B` in some
    builds — falls outside the CSI pattern, leaked through as
    `␛(B` in the action panel until the regex got extended.
    """
    stdout = (
        "\x1b[32m✓ active DC: eusec-silver-lining:dc01\x1b(B\x1b[m\n"
    )
    stderr = "\x1b[1;31mwarning:\x1b[0m something\n"

    recorder = _fake_run(rc=0, stdout=stdout, stderr=stderr)
    with patch("tgt_web.actions.subprocess.run", recorder):
        _, body = actions.dispatch_action("scenario_unload", {})
    # No raw escape bytes survive at all (CSI or charset).
    assert "\x1b" not in body["stdout"]
    assert "\x1b" not in body["stderr"]
    # Useful content (post-strip) is preserved.
    assert "✓ active DC: eusec-silver-lining:dc01" in body["stdout"]
    assert "warning:" in body["stderr"]


def test_strip_ansi_charset_designation_directly():
    """Unit test for the regex itself: covers the four escape
    shapes we care about — CSI with params, CSI bare, G0 select,
    G1 select — and confirms surrounding text is untouched."""
    cases = [
        ("\x1b[32mgreen\x1b[0m", "green"),
        ("\x1b[m", ""),
        ("\x1b(B", ""),
        ("\x1b)0", ""),
        ("before\x1b(Bafter", "beforeafter"),
        ("no escapes here", "no escapes here"),
    ]
    for raw, expected in cases:
        assert actions._strip_ansi(raw) == expected, f"failed on {raw!r}"


def test_subprocess_env_sets_no_color():
    """NO_COLOR=1 must reach the fish env so set_color skips emitting
    sequences in the first place (defense in depth with strip)."""
    recorder = _fake_run(rc=0)
    with patch("tgt_web.actions.subprocess.run", recorder):
        actions.dispatch_action("scenario_unload", {})
    _, kw = recorder.captured
    assert kw["env"]["NO_COLOR"] == "1"


def test_subprocess_env_carries_sudo_reason():
    """dispatch_action computes a per-action reason and injects it
    as TGT_SUDO_REASON in the fish subprocess env, so fish-side
    `sudo -A -p` can label the askpass dialog with what the user
    actually clicked. `TGT_SUDO_REASON` survives the TGT_* scrub
    (same exemption mechanism as TGT_HOME)."""
    recorder = _fake_run(rc=0)
    with patch("tgt_web.actions.subprocess.run", recorder):
        actions.dispatch_action("scenario_switch", {"name": "acme"})
    _, kw = recorder.captured
    env = kw["env"]
    # Reason starts with "Sudo password" so zenity / kdialog /
    # ssh-askpass make it clear the dialog is a password prompt,
    # then carries the action's argv as context.
    reason = env["TGT_SUDO_REASON"]
    assert reason.startswith("Sudo password — tgt-web: ")
    assert "scenario switch acme" in reason


def test_subprocess_env_scrubs_stale_tgt_vars(monkeypatch):
    """Regression: tgt-web inherits TGT_SCENARIO / TGT_CRED_* from
    the shell that launched it. Those are fish universal-exported
    vars — fish gives env precedence over the universal store, so
    passing them through means every action runs against the
    launch-time scenario, not the currently-active one. Manifested
    as `tgt cred unset` clearing the wrong scenario's marker and
    `tgt cred switch` failing with "credential 'X' does not exist
    in scenario 'launch-time-name'". Scrub all TGT_* on the way in,
    keep TGT_HOME (user-set, not fish-flipped)."""
    monkeypatch.setenv("TGT_SCENARIO", "launch-time-scenario")
    monkeypatch.setenv("TGT_CRED_NAME", "launch-time-cred")
    monkeypatch.setenv("TGT_CRED_USERNAME", "stale_user")
    monkeypatch.setenv("TGT_HOME", "/tmp/custom-home")
    recorder = _fake_run(rc=0)
    with patch("tgt_web.actions.subprocess.run", recorder):
        actions.dispatch_action("cred_unset", {})
    _, kw = recorder.captured
    env = kw["env"]
    assert "TGT_SCENARIO" not in env
    assert "TGT_CRED_NAME" not in env
    assert "TGT_CRED_USERNAME" not in env
    # User-set TGT_HOME must survive — it's not state fish flips at
    # runtime, and tgt-web's reader honors it for testing/overrides.
    assert env["TGT_HOME"] == "/tmp/custom-home"
    # TGT_NO_GUM still injected (it's set after the scrub).
    assert env["TGT_NO_GUM"] == "1"


def test_subprocess_stdin_is_devnull():
    """Regression: tgt-web inherits the TTY where it was launched, so
    a subprocess without an explicit stdin redirect picks up that
    TTY. `_tgt_ask_confirm` / `_tgt_scenario_followup` would then
    `read -P` from Stefan's terminal and time out the request."""
    import subprocess as _sp
    recorder = _fake_run(rc=0)
    with patch("tgt_web.actions.subprocess.run", recorder):
        actions.dispatch_action("scenario_unload", {})
    _, kw = recorder.captured
    assert kw["stdin"] == _sp.DEVNULL


@pytest.mark.parametrize(
    "params,expected",
    [
        # Required only
        (
            {"alias": "adm", "username": "Administrator"},
            ["cred", "new", "adm", "--username", "Administrator"],
        ),
        # All fields
        (
            {"alias": "adm", "username": "Administrator",
             "password": "P@ss", "domain": "ACME", "notes": "primary"},
            ["cred", "new", "adm", "--username", "Administrator",
             "--password", "P@ss", "--domain", "ACME", "--notes", "primary"],
        ),
        # Empty optional fields must be omitted, not passed as "--password" with empty value
        (
            {"alias": "adm", "username": "u", "password": "", "domain": "", "notes": ""},
            ["cred", "new", "adm", "--username", "u"],
        ),
        # Notes with whitespace + apostrophe — shlex.quote in tgt_cmd handles the quoting;
        # the argv list itself just carries the raw string.
        (
            {"alias": "svc", "username": "svc", "notes": "it's tricky"},
            ["cred", "new", "svc", "--username", "svc", "--notes", "it's tricky"],
        ),
    ],
)
def test_cred_new_argv_builder(params, expected):
    recorder = _fake_run(rc=0)
    with patch("tgt_web.actions.subprocess.run", recorder):
        status, body = actions.dispatch_action("cred_new", params)
    assert status == 200
    assert body["argv"] == expected


def test_cred_new_requires_alias_and_username():
    s1, b1 = actions.dispatch_action("cred_new", {})
    assert s1 == 400 and "missing param" in b1["error"]
    s2, b2 = actions.dispatch_action("cred_new", {"alias": "x"})
    assert s2 == 400 and "username" in b2["error"]


def test_cred_rm_argv():
    recorder = _fake_run(rc=0)
    with patch("tgt_web.actions.subprocess.run", recorder):
        status, body = actions.dispatch_action("cred_rm", {"alias": "old-cred"})
    assert status == 200
    assert body["argv"] == ["cred", "rm", "old-cred"]


def test_cred_rm_requires_alias():
    status, body = actions.dispatch_action("cred_rm", {})
    assert status == 400 and "alias" in body["error"]


def test_cred_rename_argv():
    recorder = _fake_run(rc=0)
    with patch("tgt_web.actions.subprocess.run", recorder):
        status, body = actions.dispatch_action(
            "cred_rename", {"old": "admin", "new": "Administrator"},
        )
    assert status == 200
    assert body["argv"] == ["cred", "rename", "admin", "Administrator"]


def test_cred_rename_requires_old_and_new():
    s1, b1 = actions.dispatch_action("cred_rename", {})
    assert s1 == 400 and "old" in b1["error"]
    s2, b2 = actions.dispatch_action("cred_rename", {"old": "a"})
    assert s2 == 400 and "new" in b2["error"]


@pytest.mark.parametrize(
    "params,expected",
    [
        # Alias only — preserves everything fish-side (no flags emitted).
        ({"alias": "adm"}, ["cred", "edit", "adm"]),
        # Single-field update.
        ({"alias": "adm", "domain": "new.local"},
         ["cred", "edit", "adm", "--domain", "new.local"]),
        # Multi-field update.
        ({"alias": "adm", "username": "Alice", "password": "qwerty"},
         ["cred", "edit", "adm", "--username", "Alice", "--password", "qwerty"]),
        # Empty value passes through — fish clears the field on disk.
        # Key MUST be present in `params` for the flag to be emitted.
        ({"alias": "adm", "notes": ""},
         ["cred", "edit", "adm", "--notes", ""]),
        # Mixed clear + set in one call.
        ({"alias": "adm", "domain": "", "username": "Bob"},
         ["cred", "edit", "adm", "--username", "Bob", "--domain", ""]),
    ],
)
def test_cred_edit_argv_builder(params, expected):
    recorder = _fake_run(rc=0)
    with patch("tgt_web.actions.subprocess.run", recorder):
        status, body = actions.dispatch_action("cred_edit", params)
    assert status == 200
    assert body["argv"] == expected


def test_cred_edit_requires_alias():
    status, body = actions.dispatch_action("cred_edit", {})
    assert status == 400 and "alias" in body["error"]


def test_scenario_new_requires_name():
    status, body = actions.dispatch_action("scenario_new", {})
    assert status == 400 and "name" in body["error"]


def test_scenario_clone_argv():
    recorder = _fake_run(rc=0)
    with patch("tgt_web.actions.subprocess.run", recorder):
        status, body = actions.dispatch_action(
            "scenario_clone", {"src": "acme", "new": "acme-copy"})
    assert status == 200
    assert body["argv"] == ["scenario", "clone", "acme", "acme-copy"]


def test_scenario_clone_requires_src_and_new():
    s1, b1 = actions.dispatch_action("scenario_clone", {})
    assert s1 == 400 and "src" in b1["error"]
    s2, b2 = actions.dispatch_action("scenario_clone", {"src": "acme"})
    assert s2 == 400 and "new" in b2["error"]


def test_scenario_rename_argv():
    recorder = _fake_run(rc=0)
    with patch("tgt_web.actions.subprocess.run", recorder):
        status, body = actions.dispatch_action(
            "scenario_rename", {"old": "acme", "new": "acme-2026"})
    assert status == 200
    assert body["argv"] == ["scenario", "rename", "acme", "acme-2026"]


def test_scenario_rename_requires_old_and_new():
    s1, b1 = actions.dispatch_action("scenario_rename", {})
    assert s1 == 400 and "old" in b1["error"]
    s2, b2 = actions.dispatch_action("scenario_rename", {"old": "acme"})
    assert s2 == 400 and "new" in b2["error"]


@pytest.mark.parametrize(
    "params,expected",
    [
        # Alias only — every other flag is optional on the fish side.
        ({"alias": "dc01"}, ["dc", "new", "dc01"]),
        # Full payload.
        (
            {"alias": "dc01", "domain": "acme.local", "realm": "ACME.LOCAL",
             "kdc_host": "dc01.acme.local", "kdc_ip": "10.0.0.10",
             "admin_host": "dc01.acme.local", "admin_ip": "10.0.0.10"},
            ["dc", "new", "dc01",
             "--domain", "acme.local", "--realm", "ACME.LOCAL",
             "--kdc-host", "dc01.acme.local", "--kdc-ip", "10.0.0.10",
             "--admin-host", "dc01.acme.local", "--admin-ip", "10.0.0.10"],
        ),
        # Empty optionals must be dropped, not emitted as "--flag ''".
        (
            {"alias": "dc01", "domain": "", "realm": "", "kdc_host": "",
             "kdc_ip": "", "admin_host": "", "admin_ip": ""},
            ["dc", "new", "dc01"],
        ),
        # Mixed — only what was filled in is on the argv.
        (
            {"alias": "dc02", "realm": "EXT.LOCAL", "admin_ip": "10.0.0.20"},
            ["dc", "new", "dc02", "--realm", "EXT.LOCAL", "--admin-ip", "10.0.0.20"],
        ),
    ],
)
def test_dc_new_argv_builder(params, expected):
    recorder = _fake_run(rc=0)
    with patch("tgt_web.actions.subprocess.run", recorder):
        status, body = actions.dispatch_action("dc_new", params)
    assert status == 200
    assert body["argv"] == expected


def test_dc_new_requires_alias():
    status, body = actions.dispatch_action("dc_new", {})
    assert status == 400 and "alias" in body["error"]


@pytest.mark.parametrize(
    "params,expected",
    [
        ({"alias": "dc01"}, ["dc", "edit", "dc01"]),
        ({"alias": "dc01", "realm": "CUSTOM.LOCAL"},
         ["dc", "edit", "dc01", "--realm", "CUSTOM.LOCAL"]),
        # Empty admin-host + admin-ip clear those fields.
        ({"alias": "dc01", "admin_host": "", "admin_ip": ""},
         ["dc", "edit", "dc01", "--admin-host", "", "--admin-ip", ""]),
        # All six flags at once.
        (
            {"alias": "dc01", "domain": "acme.local", "realm": "ACME.LOCAL",
             "kdc_host": "dc01.acme.local", "kdc_ip": "10.0.0.10",
             "admin_host": "dc01.acme.local", "admin_ip": "10.0.0.10"},
            ["dc", "edit", "dc01",
             "--domain", "acme.local", "--realm", "ACME.LOCAL",
             "--kdc-host", "dc01.acme.local", "--kdc-ip", "10.0.0.10",
             "--admin-host", "dc01.acme.local", "--admin-ip", "10.0.0.10"],
        ),
    ],
)
def test_dc_edit_argv_builder(params, expected):
    recorder = _fake_run(rc=0)
    with patch("tgt_web.actions.subprocess.run", recorder):
        status, body = actions.dispatch_action("dc_edit", params)
    assert status == 200
    assert body["argv"] == expected


def test_dc_edit_requires_alias():
    status, body = actions.dispatch_action("dc_edit", {})
    assert status == 400 and "alias" in body["error"]


@pytest.mark.parametrize(
    "params,expected",
    [
        ({"alias": "web"}, ["edit", "web"]),
        ({"alias": "web", "host": "10.0.0.5"},
         ["edit", "web", "--host", "10.0.0.5"]),
        ({"alias": "web", "hosts": "a.local b.local"},
         ["edit", "web", "--hosts", "a.local b.local"]),
        # Empty hosts → fish clears the field.
        ({"alias": "web", "hosts": ""},
         ["edit", "web", "--hosts", ""]),
        # Both flags together.
        ({"alias": "web", "host": "10.0.0.5", "hosts": "a.local"},
         ["edit", "web", "--host", "10.0.0.5", "--hosts", "a.local"]),
    ],
)
def test_target_edit_argv_builder(params, expected):
    recorder = _fake_run(rc=0)
    with patch("tgt_web.actions.subprocess.run", recorder):
        status, body = actions.dispatch_action("target_edit", params)
    assert status == 200
    assert body["argv"] == expected


def test_target_edit_requires_alias():
    status, body = actions.dispatch_action("target_edit", {})
    assert status == 400 and "alias" in body["error"]


@pytest.mark.parametrize(
    "params,expected",
    [
        # Minimal: target + port. proto defaults fish-side.
        ({"target": "web", "port": "22"},
         ["ports", "add", "--target", "web", "22"]),
        # Explicit proto.
        ({"target": "web", "port": "53", "proto": "udp"},
         ["ports", "add", "--target", "web", "53/udp"]),
        # Service.
        ({"target": "web", "port": "22", "proto": "tcp", "service": "ssh"},
         ["ports", "add", "--target", "web", "22/tcp", "ssh"]),
        # Service + comment.
        ({"target": "web", "port": "22", "proto": "tcp",
          "service": "ssh", "comment": "OpenSSH 8.4"},
         ["ports", "add", "--target", "web", "22/tcp", "ssh", "OpenSSH 8.4"]),
        # Comment without service: emit an empty string in the
        # service slot so the comment lands in positional[3]
        # fish-side, where it actually gets stored.
        ({"target": "web", "port": "443", "proto": "tcp",
          "service": "", "comment": "https"},
         ["ports", "add", "--target", "web", "443/tcp", "", "https"]),
        # Both empty: no positionals after spec.
        ({"target": "web", "port": "443", "proto": "tcp",
          "service": "", "comment": ""},
         ["ports", "add", "--target", "web", "443/tcp"]),
    ],
)
def test_ports_add_argv_builder(params, expected):
    recorder = _fake_run(rc=0)
    with patch("tgt_web.actions.subprocess.run", recorder):
        status, body = actions.dispatch_action("ports_add", params)
    assert status == 200
    assert body["argv"] == expected


def test_ports_add_requires_target_and_port():
    s1, b1 = actions.dispatch_action("ports_add", {})
    assert s1 == 400 and "target" in b1["error"]
    s2, b2 = actions.dispatch_action("ports_add", {"target": "web"})
    assert s2 == 400 and "port" in b2["error"]


def test_ports_rm_argv():
    recorder = _fake_run(rc=0)
    with patch("tgt_web.actions.subprocess.run", recorder):
        status, body = actions.dispatch_action(
            "ports_rm", {"target": "web", "port": "22", "proto": "tcp"})
    assert status == 200
    assert body["argv"] == ["ports", "rm", "--target", "web", "22/tcp"]


def test_ports_clear_argv():
    recorder = _fake_run(rc=0)
    with patch("tgt_web.actions.subprocess.run", recorder):
        status, body = actions.dispatch_action("ports_clear", {"target": "web"})
    assert status == 200
    assert body["argv"] == ["ports", "clear", "--target", "web"]


def test_ports_comment_argv():
    recorder = _fake_run(rc=0)
    with patch("tgt_web.actions.subprocess.run", recorder):
        status, body = actions.dispatch_action(
            "ports_comment",
            {"target": "web", "port": "22", "proto": "tcp",
             "comment": "rotated key"})
    assert status == 200
    assert body["argv"] == [
        "ports", "comment", "--target", "web", "22/tcp", "rotated key",
    ]


def test_ports_service_argv():
    recorder = _fake_run(rc=0)
    with patch("tgt_web.actions.subprocess.run", recorder):
        status, body = actions.dispatch_action(
            "ports_service",
            {"target": "web", "port": "22", "proto": "tcp",
             "service": "ssh-banner-lied"})
    assert status == 200
    assert body["argv"] == [
        "ports", "service", "--target", "web", "22/tcp", "ssh-banner-lied",
    ]


def test_ports_service_requires_target_port_service():
    s1, b1 = actions.dispatch_action("ports_service", {})
    assert s1 == 400 and "target" in b1["error"]
    s2, b2 = actions.dispatch_action("ports_service", {"target": "web"})
    assert s2 == 400 and "port" in b2["error"]
    s3, b3 = actions.dispatch_action("ports_service", {"target": "web", "port": "22"})
    assert s3 == 400 and "service" in b3["error"]


def test_dispatch_invalidates_active_cache():
    """After every action, the cached `$TGT_SCENARIO` must be dropped —
    most actions can flip it, and the immediate post-action refresh
    needs to see fresh state without waiting out the TTL."""
    recorder = _fake_run(rc=0)
    with patch("tgt_web.actions.subprocess.run", recorder), \
         patch("tgt_web.actions.reader.invalidate_active_cache") as inv:
        actions.dispatch_action("scenario_switch", {"name": "lab"})
    assert inv.call_count == 1


def test_argv_shell_quoting_handles_spaces():
    """A scenario name with whitespace must round-trip through
    `fish -c` without splitting into separate words."""
    recorder = _fake_run(rc=0)
    with patch("tgt_web.actions.subprocess.run", recorder):
        actions.dispatch_action("scenario_switch", {"name": "two words"})
    argv, _ = recorder.captured
    # shlex.quote wraps the value, so the literal "'two words'" must
    # appear in the constructed fish -c string.
    assert "'two words'" in argv[2]
