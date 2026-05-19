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
import shlex
import subprocess
from typing import Callable

from tgt_web import reader, sudo

# action name → (argv builder, list of required params)
ACTIONS: dict[str, tuple[Callable[[dict], list[str]], list[str]]] = {
    "scenario_switch":    (lambda p: ["scenario", "switch", p["name"]],     ["name"]),
    "scenario_unload":    (lambda p: ["scenario", "unload"],                []),
    "scenario_archive":   (lambda p: ["scenario", "archive", p["name"]],    ["name"]),
    "scenario_unarchive": (lambda p: ["scenario", "unarchive", p["name"]],  ["name"]),
    "target_switch":      (lambda p: ["switch", p["alias"]],                ["alias"]),
    "target_revoke":      (lambda p: ["revoke"],                            []),
    "cred_switch":        (lambda p: ["cred", "switch", p["alias"]],        ["alias"]),
    "cred_unset":         (lambda p: ["cred", "unset"],                     []),
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
    """
    env = sudo.prepare_env(os.environ.copy())
    env["TGT_NO_GUM"] = "1"
    quoted = " ".join(shlex.quote(a) for a in args)
    p = subprocess.run(
        ["fish", "-c", "tgt " + quoted],
        capture_output=True, text=True, env=env,
        stdin=subprocess.DEVNULL, timeout=timeout,
    )
    return p.returncode, p.stdout, p.stderr


def dispatch_action(name: str, params: dict) -> tuple[int, dict]:
    """Look up `name`, validate params, run `tgt`.

    Returns `(http_status, body)`. Status is 400 for unknown action
    or missing param, 500 if `tgt` exits non-zero, 200 otherwise.
    """
    spec = ACTIONS.get(name)
    if spec is None:
        return 400, {"error": f"unknown action: {name}"}
    builder, required = spec
    for r in required:
        if r not in params:
            return 400, {"error": f"missing param: {r}"}
    argv = builder(params)
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
