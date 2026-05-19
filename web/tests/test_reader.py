"""Reader unit tests: fish_unescape edge cases + happy-path parsing."""

from __future__ import annotations

import pytest

from tgt_web import reader


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


def test_list_scenarios_active_from_env(monkeypatch, tgt_home_env):
    monkeypatch.setenv("TGT_SCENARIO", "lab")
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
