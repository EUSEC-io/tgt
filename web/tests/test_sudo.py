"""Sudo strategy probe tests.

We mock `shutil.which` and `subprocess.run` so the tests are
hermetic — they neither call sudo nor touch the user's PATH-resident
askpass tools. The wrapper script is exercised against a tmp_path so
the user's real ~/.cache directory stays untouched.
"""

from __future__ import annotations

from pathlib import Path
from unittest.mock import patch

import pytest

from tgt_web import sudo


@pytest.fixture(autouse=True)
def isolated_cache(monkeypatch, tmp_path):
    """Reroute the wrapper output dir + clear the module's cache."""
    monkeypatch.setattr(sudo, "WRAPPER_PATH", tmp_path / "askpass.sh")
    monkeypatch.setattr(sudo, "_cached", None)


def test_existing_sudo_askpass_wins(monkeypatch):
    monkeypatch.setenv("SUDO_ASKPASS", "/usr/local/bin/my-askpass")
    status = sudo.probe()
    assert status.askpass == "/usr/local/bin/my-askpass"
    assert status.wrapper is None
    assert status.nopasswd is False


def test_zenity_found_writes_wrapper(monkeypatch):
    monkeypatch.delenv("SUDO_ASKPASS", raising=False)
    monkeypatch.setattr(
        sudo.shutil, "which",
        lambda b: "/usr/bin/zenity" if b == "zenity" else None,
    )
    status = sudo.probe()
    assert status.askpass is not None
    assert status.wrapper is not None
    assert status.wrapper.exists()
    script = status.wrapper.read_text()
    assert "/usr/bin/zenity" in script
    assert "tgt-web" in script
    # The wrapper passes sudo's -p prompt through to the helper as $1.
    # Zenity 4.x's --password mode ignores --text, so we use
    # --entry --hide-text (which does honor --text and behaves the
    # same security-wise — input is masked).
    assert "--entry" in script and "--hide-text" in script
    assert '"$1"' in script
    # Executable bit set
    assert status.wrapper.stat().st_mode & 0o111


def test_kdialog_used_when_zenity_missing(monkeypatch):
    monkeypatch.delenv("SUDO_ASKPASS", raising=False)
    monkeypatch.setattr(
        sudo.shutil, "which",
        lambda b: "/usr/bin/kdialog" if b == "kdialog" else None,
    )
    script = sudo.probe().wrapper.read_text()
    assert "kdialog" in script
    # Same prompt-passthrough contract.
    assert '"$1"' in script


def test_falls_back_to_nopasswd(monkeypatch):
    monkeypatch.delenv("SUDO_ASKPASS", raising=False)
    monkeypatch.setattr(sudo.shutil, "which", lambda b: None)

    class Result:
        returncode = 0

    monkeypatch.setattr(sudo.subprocess, "run", lambda *a, **kw: Result())
    status = sudo.probe()
    assert status.askpass is None
    assert status.wrapper is None
    assert status.nopasswd is True
    assert "passwordless" in status.note.lower()


def test_no_helpers_no_nopasswd_surfaces_tips(monkeypatch):
    monkeypatch.delenv("SUDO_ASKPASS", raising=False)
    monkeypatch.setattr(sudo.shutil, "which", lambda b: None)

    class Result:
        returncode = 1

    monkeypatch.setattr(sudo.subprocess, "run", lambda *a, **kw: Result())
    status = sudo.probe()
    assert status.askpass is None
    assert status.nopasswd is False
    assert "zenity" in status.note


def test_prepare_env_injects_askpass(monkeypatch):
    monkeypatch.setattr(sudo, "_cached", sudo.SudoStatus(
        askpass="/tmp/x.sh", wrapper=Path("/tmp/x.sh"), nopasswd=False, note="t"
    ))
    env = sudo.prepare_env({"PATH": "/usr/bin"})
    assert env["SUDO_ASKPASS"] == "/tmp/x.sh"


def test_prepare_env_skips_when_unavailable(monkeypatch):
    monkeypatch.setattr(sudo, "_cached", sudo.SudoStatus(
        askpass=None, wrapper=None, nopasswd=True, note="t"
    ))
    env = sudo.prepare_env({"PATH": "/usr/bin"})
    assert "SUDO_ASKPASS" not in env
