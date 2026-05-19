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
    them server-side regardless of whether fish suppressed them."""
    class Result:
        returncode = 0
        stdout = "\x1b[32m✓ switched to acme\x1b[0m\n"
        stderr = "\x1b[1;31mwarning:\x1b[0m something\n"

    recorder = _fake_run(rc=0, stdout=Result.stdout, stderr=Result.stderr)
    # The recorder's _fake_run doesn't actually use the Result class
    # above, so override its returned class.
    with patch("tgt_web.actions.subprocess.run", recorder):
        _, body = actions.dispatch_action("scenario_unload", {})
    assert "\x1b[" not in body["stdout"]
    assert "\x1b[" not in body["stderr"]
    assert "✓ switched to acme" in body["stdout"]
    assert "warning:" in body["stderr"]


def test_subprocess_env_sets_no_color():
    """NO_COLOR=1 must reach the fish env so set_color skips emitting
    sequences in the first place (defense in depth with strip)."""
    recorder = _fake_run(rc=0)
    with patch("tgt_web.actions.subprocess.run", recorder):
        actions.dispatch_action("scenario_unload", {})
    _, kw = recorder.captured
    assert kw["env"]["NO_COLOR"] == "1"


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
