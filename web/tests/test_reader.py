"""Reader unit tests: fish_unescape edge cases + happy-path parsing."""

from __future__ import annotations

from unittest.mock import patch

import pytest

from tgt_web import reader

# Capture the un-patched implementation at import time. The autouse
# `tgt_home_env` fixture stubs `reader.read_active_scenario` so other
# tests don't shell out to fish; tests that exercise the real
# implementation undo that patch by re-binding to this reference.
_REAL_READ_ACTIVE = reader.read_active_scenario


# ── fish_unescape ────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    "raw,expected",
    [
        # `string escape --style=script` output shapes:
        ("plain",             "plain"),       # bare token
        ("'foo bar'",         "foo bar"),     # single-quoted (spaces)
        ('"it\'s ok"',        "it's ok"),     # double-quoted (raw apostrophe)
        ('"\'"',              "'"),           # lone single-quote → "'"
        ("'back\\\\slash'",   "back\\slash"), # backslash → \\\\ inside single quotes
        ("",                  ""),            # empty
        ("'\\''",             "'"),           # explicitly escaped apostrophe
    ],
)
def test_fish_unescape(raw, expected):
    assert reader.fish_unescape(raw) == expected


# ── parse_export_file ────────────────────────────────────────────────────


def test_parse_export_file(tgt_home_env):
    data = reader.parse_export_file(
        tgt_home_env / "scenarios" / "acme" / "creds" / "admin.fish"
    )
    assert data == {
        "TGT_CRED_USERNAME": "admin",
        "TGT_CRED_PASSWORD": "hunter2",
        "TGT_CRED_DOMAIN":   "ACME",
        "TGT_CRED_NOTES":    "primary",
    }


def test_parse_export_handles_corrupted_single_quote_domain(tgt_home_env):
    """Regression: a domain value of `"'"` (the literal fish-escape form
    of a single apostrophe) used to surface as the raw 3-char token in
    the UI instead of unescaping to `'`."""
    data = reader.parse_export_file(
        tgt_home_env / "scenarios" / "acme" / "creds" / "guest.fish"
    )
    assert data["TGT_CRED_DOMAIN"] == "'"


def test_parse_export_handles_quoted_value_with_apostrophe(tgt_home_env):
    data = reader.parse_export_file(
        tgt_home_env / "scenarios" / "acme" / "creds" / "svc.fish"
    )
    assert data["TGT_CRED_NOTES"] == "it's tricky"
    assert data["TGT_CRED_PASSWORD"] == "p@ssw0rd with space"


def test_parse_missing_file_returns_empty(tmp_path):
    assert reader.parse_export_file(tmp_path / "nope.fish") == {}


# ── list_scenarios ───────────────────────────────────────────────────────


def test_list_scenarios_picks_up_dirs(tgt_home_env):
    names = [s["name"] for s in reader.list_scenarios()]
    assert names == ["acme", "archived-engagement", "lab"]


def test_list_scenarios_flags_archived(tgt_home_env):
    by_name = {s["name"]: s for s in reader.list_scenarios()}
    assert by_name["archived-engagement"]["archived"] is True
    assert by_name["acme"]["archived"] is False


def test_list_scenarios_counts(tgt_home_env):
    by_name = {s["name"]: s for s in reader.list_scenarios()}
    assert by_name["acme"]["target_count"] == 2
    assert by_name["acme"]["cred_count"] == 3
    assert by_name["acme"]["dc_count"] == 1
    assert by_name["lab"]["target_count"] == 1
    assert by_name["lab"]["cred_count"] == 0


def test_list_scenarios_active_from_fish(monkeypatch, tgt_home_env):
    """`read_active_scenario` queries fish at request time — tests
    just patch it to a fixed value, no fish subprocess needed."""
    monkeypatch.setattr("tgt_web.reader.read_active_scenario", lambda: "lab")
    by_name = {s["name"]: s for s in reader.list_scenarios()}
    assert by_name["lab"]["active"] is True
    assert by_name["acme"]["active"] is False


def test_list_scenarios_no_home(monkeypatch, tmp_path):
    monkeypatch.setenv("TGT_HOME", str(tmp_path))
    assert reader.list_scenarios() == []


# ── scenario_detail ──────────────────────────────────────────────────────


def test_scenario_detail_unknown(tgt_home_env):
    assert reader.scenario_detail("does-not-exist") is None


def test_scenario_detail_acme(tgt_home_env):
    d = reader.scenario_detail("acme")
    assert d is not None
    assert d["name"] == "acme"
    assert d["archived"] is False

    targets = {t["alias"]: t for t in d["targets"]}
    assert targets["web"]["host"] == "10.10.10.10"
    assert targets["web"]["hosts"] == ["web.acme.local", "mail.acme.local"]
    assert targets["db"]["host"] == "10.10.10.20"
    assert targets["db"]["hosts"] == []

    creds = {c["alias"]: c for c in d["creds"]}
    assert creds["admin"]["active"] is True
    assert creds["admin"]["has_password"] is True
    assert creds["guest"]["has_password"] is False
    assert creds["guest"]["domain"] == "'"

    dcs = {dc["alias"]: dc for dc in d["dcs"]}
    assert dcs["dc01"]["active"] is True
    assert dcs["dc01"]["domain"] == "acme.local"
    assert dcs["dc01"]["realm"] == "ACME.LOCAL"


def test_scenario_detail_lab_no_active_markers(tgt_home_env):
    d = reader.scenario_detail("lab")
    assert d is not None
    assert d["creds"] == []
    assert d["dcs"] == []
    assert len(d["targets"]) == 1


# ── cred_password ────────────────────────────────────────────────────────


def test_cred_password_returns_plaintext(tgt_home_env):
    assert reader.cred_password("acme", "admin") == "hunter2"


def test_cred_password_handles_missing(tgt_home_env):
    assert reader.cred_password("acme", "guest") == ""
    assert reader.cred_password("acme", "nope") == ""


# ── read_active_scenario / invalidate_active_cache ───────────────────────


@pytest.fixture
def real_read_active(monkeypatch):
    """Undo the autouse stub so a test can exercise the real function."""
    monkeypatch.setattr(reader, "read_active_scenario", _REAL_READ_ACTIVE)
    monkeypatch.setattr(reader, "_active_cache", None)


def test_read_active_scenario_shells_out_to_fish(real_read_active):
    """First call invokes fish; the second is served from cache."""
    calls = []

    class Result:
        returncode = 0
        stdout = "current-scenario"

    def fake_run(argv, **kw):
        calls.append(argv)
        return Result()

    with patch("tgt_web.reader.subprocess.run", side_effect=fake_run):
        assert reader.read_active_scenario() == "current-scenario"
        assert reader.read_active_scenario() == "current-scenario"

    assert len(calls) == 1
    assert calls[0][0] == "fish"
    assert "TGT_SCENARIO" in calls[0][2]


def test_read_active_scenario_handles_unset(real_read_active):
    class Result:
        returncode = 1
        stdout = ""

    with patch("tgt_web.reader.subprocess.run", return_value=Result()):
        assert reader.read_active_scenario() == ""


def test_read_active_scenario_handles_fish_missing(real_read_active):
    """No fish on PATH → return empty, never crash."""
    with patch("tgt_web.reader.subprocess.run",
               side_effect=FileNotFoundError("no fish")):
        assert reader.read_active_scenario() == ""


def test_read_active_scenario_strips_tgt_env_from_subprocess(
    monkeypatch, real_read_active,
):
    """The fish probe must NOT inherit tgt-web's own TGT_* env. The
    parent process captured `TGT_SCENARIO` at launch (it's a fish
    universal *exported* var) and re-exporting it shadows
    fish_variables in the child — so we'd keep reading the
    launch-time snapshot forever even after the user switched."""
    monkeypatch.setenv("TGT_SCENARIO", "stale-from-launch")
    monkeypatch.setenv("TGT_CRED_NAME", "stale-cred")
    monkeypatch.setenv("UNRELATED", "should-pass-through")

    captured: dict = {}

    class Result:
        returncode = 0
        stdout = "fresh-on-disk"

    def fake_run(argv, **kw):
        captured.update(kw)
        return Result()

    with patch("tgt_web.reader.subprocess.run", side_effect=fake_run):
        assert reader.read_active_scenario() == "fresh-on-disk"

    env = captured["env"]
    assert "TGT_SCENARIO" not in env, "stale TGT_SCENARIO leaked into fish probe"
    assert "TGT_CRED_NAME" not in env, "TGT_* prefix scrub missed sibling vars"
    assert env.get("UNRELATED") == "should-pass-through"


def test_invalidate_active_cache_forces_requery(real_read_active):
    calls = []

    class Result:
        returncode = 0
        stdout = "first"

    def fake_run(argv, **kw):
        calls.append(argv)
        return Result()

    with patch("tgt_web.reader.subprocess.run", side_effect=fake_run):
        reader.read_active_scenario()
        reader.invalidate_active_cache()
        reader.read_active_scenario()

    assert len(calls) == 2
