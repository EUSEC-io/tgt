"""Write dispatch.

Every write goes through the `tgt` CLI — we never touch registry
files directly for writes (that would bypass krb5/hosts sync and
active-marker handling). Each request from the browser names an
action; this module whitelists the action names and maps them to a
concrete argv.

Drift contract: the fish side exposes `tgt --list-mutating-verbs --json`.
`tests/test_drift.py` asserts every entry in that list has a matching
key here. Add new actions in lock-step.
"""

from __future__ import annotations

import os
import re
import shlex
import subprocess
from typing import Callable

from tgt_web import reader, sudo

# CSI escape sequences (color + cursor). Fish's `set_color` should
# skip these when stdout isn't a TTY, but some callsites store the
# value in a variable (`set red (set_color red); echo "$red foo"`)
# and that bypasses the isatty check. Belt-and-suspenders: strip
# server-side too, and pass NO_COLOR=1 in the subprocess env.
_ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")


def _strip_ansi(s: str) -> str:
    return _ANSI_RE.sub("", s)

# action name → (argv builder, list of required params)
def _cred_new_argv(p: dict) -> list[str]:
    argv = ["cred", "new", p["alias"], "--username", p["username"]]
    for key, flag in (("password", "--password"),
                      ("domain",   "--domain"),
                      ("notes",    "--notes")):
        v = p.get(key)
        if v:
            argv += [flag, v]
    return argv


def _cred_edit_argv(p: dict) -> list[str]:
    """Edit semantics differ from new: every flag is optional, and
    we explicitly emit `--flag ''` for fields the caller wants to
    clear. Caller passes the field key when they want to act on it
    (set or clear); omitted keys preserve the current value."""
    argv = ["cred", "edit", p["alias"]]
    for key, flag in (("username", "--username"),
                      ("password", "--password"),
                      ("domain",   "--domain"),
                      ("notes",    "--notes")):
        if key in p:
            argv += [flag, p[key]]
    return argv


def _dc_new_argv(p: dict) -> list[str]:
    argv = ["dc", "new", p["alias"]]
    for key, flag in (("domain",     "--domain"),
                      ("realm",      "--realm"),
                      ("kdc_host",   "--kdc-host"),
                      ("kdc_ip",     "--kdc-ip"),
                      ("admin_host", "--admin-host"),
                      ("admin_ip",   "--admin-ip")):
        v = p.get(key)
        if v:
            argv += [flag, v]
    return argv


ACTIONS: dict[str, tuple[Callable[[dict], list[str]], list[str]]] = {
    "scenario_new":       (lambda p: ["scenario", "new", p["name"]],        ["name"]),
    "scenario_switch":    (lambda p: ["scenario", "switch", p["name"]],     ["name"]),
    "scenario_unload":    (lambda p: ["scenario", "unload"],                []),
    "scenario_archive":   (lambda p: ["scenario", "archive", p["name"]],    ["name"]),
    "scenario_unarchive": (lambda p: ["scenario", "unarchive", p["name"]],  ["name"]),
    "target_switch":      (lambda p: ["switch", p["alias"]],                ["alias"]),
    "target_revoke":      (lambda p: ["revoke"],                            []),
    "cred_new":           (_cred_new_argv,                                  ["alias", "username"]),
    "cred_edit":          (_cred_edit_argv,                                 ["alias"]),
    "cred_rename":        (lambda p: ["cred", "rename", p["old"], p["new"]], ["old", "new"]),
    "cred_rm":            (lambda p: ["cred", "rm", p["alias"]],            ["alias"]),
    "cred_switch":        (lambda p: ["cred", "switch", p["alias"]],        ["alias"]),
    "cred_unset":         (lambda p: ["cred", "unset"],                     []),
    "dc_new":             (_dc_new_argv,                                    ["alias"]),
    "dc_switch":          (lambda p: ["dc", "switch", p["alias"]],          ["alias"]),
    "dc_unset":           (lambda p: ["dc", "unset"],                       []),
}


def tgt_cmd(args: list[str], timeout: float = 15) -> tuple[int, str, str]:
    """Run `tgt <args>` via `fish -c`. Returns (returncode, stdout, stderr).

    The web UI server is non-interactive, so we suppress gum (which
    would block on TTY input). `sudo.prepare_env` adds SUDO_ASKPASS
    when an askpass helper is available, so `_tgt_hosts_write` /
    `_tgt_krb5_write` can prompt graphically instead of hanging.

    `stdin=DEVNULL` is load-bearing: otherwise the subprocess
    inherits tgt-web's controlling TTY, and any fish `read -P`
    (e.g. `_tgt_ask_confirm` falling back to non-gum mode, or
    `_tgt_scenario_followup`'s isatty gate) hangs the request
    until the user types into the terminal where tgt-web was
    launched.

    Env scrubbing is load-bearing too. `TGT_SCENARIO` is a fish
    universal-exported var (`set -Ux`), so tgt-web's process env
    captured it from the launching shell — and that value never
    updates when fish flips the universal. Fish gives precedence
    to env over the universal store, so without scrubbing every
    action would run against the launch-time scenario instead of
    the currently-active one. Same trap caught `read_active_scenario`
    on the read side; we mirror it here. `TGT_HOME` is kept because
    the user may have set it intentionally (e.g. tests) and it's
    not state that fish flips at runtime.
    """
    env = {k: v for k, v in os.environ.items()
           if not k.startswith("TGT_") or k == "TGT_HOME"}
    env = sudo.prepare_env(env)
    env["TGT_NO_GUM"] = "1"
    env["NO_COLOR"] = "1"
    quoted = " ".join(shlex.quote(a) for a in args)
    p = subprocess.run(
        ["fish", "-c", "tgt " + quoted],
        capture_output=True, text=True, env=env,
        stdin=subprocess.DEVNULL, timeout=timeout,
    )
    return p.returncode, _strip_ansi(p.stdout), _strip_ansi(p.stderr)


def _validate_and_build(name: str, params: dict) -> tuple[int, dict]:
    """Shared by `dispatch_action` and `preview_action`: look up `name`,
    enforce required params, build the argv. Returns either an error
    body (status 400) or `(200, {"argv": [...]})` ready for either
    path to act on.
    """
    spec = ACTIONS.get(name)
    if spec is None:
        return 400, {"error": f"unknown action: {name}"}
    builder, required = spec
    for r in required:
        if r not in params:
            return 400, {"error": f"missing param: {r}"}
    return 200, {"argv": builder(params)}


def preview_action(name: str, params: dict) -> tuple[int, dict]:
    """Validate `name` + `params` and return the argv that *would* be
    sent to `tgt`. No subprocess, no side effects. Mirrors
    `dispatch_action`'s input contract so the UI can call either
    endpoint with the same payload — preview from the confirm modal
    before commit, dispatch from the actual click.
    """
    return _validate_and_build(name, params)


def dispatch_action(name: str, params: dict) -> tuple[int, dict]:
    """Look up `name`, validate params, run `tgt`.

    Returns `(http_status, body)`. Status is 400 for unknown action
    or missing param, 500 if `tgt` exits non-zero, 200 otherwise.
    """
    status, body = _validate_and_build(name, params)
    if status != 200:
        return status, body
    argv = body["argv"]
    rc, out, err = tgt_cmd(argv)
    # Drop the cached `$TGT_SCENARIO` value — any action might have
    # flipped it (most obviously `scenario_switch`/`unload`), and we
    # want the immediate post-action refresh to see fresh state.
    reader.invalidate_active_cache()
    return (200 if rc == 0 else 500), {
        "rc": rc,
        "stdout": out,
        "stderr": err,
        "argv": argv,
    }
