"""Shared pytest fixtures.

We point `TGT_HOME` at `tests/fixtures/` for the duration of every
test, so `reader.tgt_home()` and friends operate on a fixed, in-repo
dataset. The fixture also clears `TGT_SCENARIO` so tests have a
deterministic "no active scenario" baseline.
"""

from __future__ import annotations

import os
from pathlib import Path

import pytest

FIXTURES = Path(__file__).parent / "fixtures"


@pytest.fixture(autouse=True)
def tgt_home_env(monkeypatch):
    monkeypatch.setenv("TGT_HOME", str(FIXTURES))
    monkeypatch.delenv("TGT_SCENARIO", raising=False)
    yield FIXTURES
