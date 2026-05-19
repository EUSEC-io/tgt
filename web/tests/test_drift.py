"""Drift contract: every mutating fish verb has a matching web action.

Skipped when `fish` or the `tgt` function isn't available — the test
needs the real plugin loaded. CI runs this in a job that installs
both fish and the plugin via `make dev`.
"""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

import pytest

from tgt_web.actions import ACTIONS

REPO_ROOT = Path(__file__).resolve().parents[2]


def _fish_with_plugin_sourced(cmd: str) -> subprocess.CompletedProcess:
    """Run `cmd` in fish after sourcing every function in the repo.

    Bypasses the need for `make dev` / Fisher install so this test
    works on a clean checkout.
    """
    funcs_dir = REPO_ROOT / "functions"
    source_block = " ".join(
        f"source {f.as_posix()};" for f in sorted(funcs_dir.glob("*.fish"))
    )
    return subprocess.run(
        ["fish", "-c", source_block + " " + cmd],
        capture_output=True, text=True, timeout=10,
    )


@pytest.fixture(scope="module")
def fish_available() -> bool:
    return shutil.which("fish") is not None


@pytest.fixture(scope="module")
def mutating_verbs(fish_available) -> list[dict]:
    if not fish_available:
        pytest.skip("fish not on PATH")
    funcs = REPO_ROOT / "functions"
    if not (funcs / "tgt.fish").is_file():
        pytest.skip("functions/tgt.fish not found")
    r = _fish_with_plugin_sourced("tgt --list-mutating-verbs --json")
    if r.returncode != 0:
        pytest.skip(f"`tgt --list-mutating-verbs --json` failed: {r.stderr}")
    return json.loads(r.stdout)


def test_every_fish_verb_has_a_web_action(mutating_verbs):
    fish_names = {v["action"] for v in mutating_verbs}
    web_names = set(ACTIONS)
    missing = fish_names - web_names
    assert not missing, (
        f"fish lists {sorted(missing)} as mutating verbs but no matching "
        f"action exists in tgt_web/actions.py::ACTIONS — mirror the new verb."
    )


def test_no_orphan_web_actions(mutating_verbs):
    """Every web ACTIONS entry must have a matching fish enumeration
    row. The contract is strict in both directions — adding an
    ACTIONS entry without the bookkeeping line in
    `tgt --list-mutating-verbs --json` is a CI fail.
    """
    fish_names = {v["action"] for v in mutating_verbs}
    orphans = set(ACTIONS) - fish_names
    assert not orphans, (
        f"web ACTIONS {sorted(orphans)} have no fish enumeration entry — "
        "add the matching row to `tgt --list-mutating-verbs --json` "
        "in functions/tgt.fish."
    )
