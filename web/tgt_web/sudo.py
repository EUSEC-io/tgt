"""Sudo strategy for the web UI.

`tgt` modifies `/etc/hosts` and `/etc/krb5.conf` via `sudo install`.
On the CLI that prompts the user in the terminal. The web UI has no
terminal, so we either:

  1. Set `SUDO_ASKPASS` to a graphical helper (zenity / kdialog /
     ssh-askpass) and rely on the fish-side `sudo -A install …`
     fallback to pick it up.
  2. Detect a passwordless sudoers entry (NOPASSWD) and let `sudo`
     run unattended.

If neither path works, the action will still be attempted, but the
error toast surfaces a clear install hint.

Probe order (first hit wins):
  - `$SUDO_ASKPASS` already in env (user override)
  - `zenity`  (gnome / parrot)
  - `kdialog` (kde)
  - `ssh-askpass`, `ssh-askpass-gnome`, `x11-ssh-askpass` (universal)
"""

from __future__ import annotations

import os
import shutil
import stat
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

WRAPPER_PATH = Path.home() / ".cache" / "tgt-web" / "askpass.sh"

# Probed in order; first match wins. Each template uses `"$1"`,
# which is what `sudo -A -p '<reason>'` passes through to the
# wrapper. Fish-side (`_tgt_hosts_write` / `_tgt_krb5_write`) sets
# `-p` from `$TGT_SUDO_REASON` so the user sees *which* tgt action
# wants /etc/hosts modified.
#
# Zenity quirk worth recording: zenity 4.x's `--password` mode
# IGNORES `--text`. The `--entry --hide-text` form does honor it
# and behaves the same security-wise (input is masked). Took
# in-browser testing on 2026-05-20 to find this — switching to
# `--entry --hide-text` is what makes the per-action reason
# visible under zenity.
_HELPERS: list[tuple[str, str]] = [
    ("zenity",           '{bin} --entry --hide-text --title="tgt-web — sudo" --text="$1"'),
    ("kdialog",          '{bin} --password "$1" --title "tgt-web — sudo"'),
    ("ssh-askpass",      '{bin} "$1"'),
    ("ssh-askpass-gnome",'{bin} "$1"'),
    ("x11-ssh-askpass",  '{bin} "$1"'),
]

INSTALL_TIPS = (
    "No graphical sudo prompt found and passwordless sudo is not configured.\n"
    "Install one of: zenity, kdialog, ssh-askpass.\n"
    "  Parrot / Kali / Debian / Ubuntu:  sudo apt install zenity\n"
    "  Arch / Manjaro:                   sudo pacman -S zenity\n"
    "  Fedora:                           sudo dnf install zenity\n"
    "Or add a NOPASSWD sudoers rule for `install`."
)


@dataclass
class SudoStatus:
    """Outcome of the startup probe.

    `wrapper`:  path written to ~/.cache/tgt-web/askpass.sh (or None
                if no graphical helper was found / SUDO_ASKPASS was
                already set in the environment).
    `askpass`:  effective SUDO_ASKPASS value to export to subprocesses.
                None means: don't set it.
    `nopasswd`: True if `sudo -n install --version` succeeded — the
                user has the opt-in passwordless path configured.
    `note`:     human-readable summary for the UI / startup log.
    """

    askpass: Optional[str]
    wrapper: Optional[Path]
    nopasswd: bool
    note: str


def _find_helper() -> Optional[tuple[str, str, str]]:
    """Return `(bin_name, bin_path, command_template)` of the first
    available askpass helper, or None."""
    for name, template in _HELPERS:
        path = shutil.which(name)
        if path:
            return name, path, template
    return None


def _write_wrapper(bin_path: str, template: str) -> Path:
    """Write a tiny shell script that invokes the helper with the
    prompt sudo gives it (`$1`). The template was built with `$1`
    literally embedded; we only fill in the binary path."""
    cmd = template.format(bin=bin_path)
    script = f"#!/bin/sh\nexec {cmd}\n"
    WRAPPER_PATH.parent.mkdir(parents=True, exist_ok=True)
    WRAPPER_PATH.write_text(script)
    WRAPPER_PATH.chmod(
        WRAPPER_PATH.stat().st_mode
        | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH
    )
    return WRAPPER_PATH


def _probe_nopasswd() -> bool:
    """Check whether `sudo -n install --version` works (NOPASSWD path)."""
    try:
        r = subprocess.run(
            ["sudo", "-n", "install", "--version"],
            capture_output=True, timeout=3,
        )
        return r.returncode == 0
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False


def probe(env: Optional[dict[str, str]] = None) -> SudoStatus:
    """Pick the best sudo strategy. Idempotent; safe to call at startup."""
    env = env if env is not None else os.environ
    existing = env.get("SUDO_ASKPASS", "").strip()
    if existing:
        return SudoStatus(
            askpass=existing,
            wrapper=None,
            nopasswd=False,
            note=f"using $SUDO_ASKPASS={existing}",
        )

    helper = _find_helper()
    if helper:
        name, path, template = helper
        wrapper = _write_wrapper(path, template)
        return SudoStatus(
            askpass=str(wrapper),
            wrapper=wrapper,
            nopasswd=False,
            note=f"askpass: {name} → {wrapper}",
        )

    if _probe_nopasswd():
        return SudoStatus(
            askpass=None,
            wrapper=None,
            nopasswd=True,
            note="passwordless sudo (NOPASSWD) detected",
        )

    return SudoStatus(
        askpass=None,
        wrapper=None,
        nopasswd=False,
        note=INSTALL_TIPS,
    )


_cached: Optional[SudoStatus] = None


def status() -> SudoStatus:
    """Return cached probe result, probing once on first call."""
    global _cached
    if _cached is None:
        _cached = probe()
    return _cached


def prepare_env(env: dict[str, str]) -> dict[str, str]:
    """Inject SUDO_ASKPASS into a subprocess env if we have one."""
    s = status()
    if s.askpass:
        env["SUDO_ASKPASS"] = s.askpass
    return env
