"""Registry-file reader.

Reads `$TGT_HOME/scenarios/*/{targets,creds,dcs}/*.fish` directly.
The fish side writes these via `_tgt_export VAR value`, where `value`
has been run through `string escape --style=script`. We reverse that
escaping here.

Reads have no side effects and never invoke fish; they exist so the
web UI can paint the dashboard without spawning a subprocess per
field. Writes always go through `actions.dispatch_action` (which
shells out to `tgt`).
"""

from __future__ import annotations

import os
import re
import subprocess
import time
from pathlib import Path

EXPORT_RE = re.compile(r"^_tgt_export\s+(\S+)\s+(.*)$")

# `TGT_SCENARIO` is a fish *universal* variable. Python's `os.environ`
# is a one-shot snapshot taken at launch — when fish flips the var
# from a subprocess (e.g. `tgt scenario switch`), our parent never
# sees the update. We re-query fish at request time, with a brief
# cache so `list_scenarios` + `scenario_detail` share one invocation
# during a single UI refresh.
_ACTIVE_TTL = 1.0
_active_cache: tuple[float, str] | None = None


def tgt_home() -> Path:
    """Resolve $TGT_HOME the same way fish does."""
    return Path(
        os.environ.get("TGT_HOME") or Path.home() / ".config" / "fish" / "tgt"
    )


def read_active_scenario() -> str:
    """Return the current `$TGT_SCENARIO` from fish, or "" if unset.

    Cached for `_ACTIVE_TTL` seconds; tests monkeypatch this function
    directly rather than touching the cache.

    Implementation note — env scrubbing is load-bearing. tgt-web's
    own environment captured `TGT_SCENARIO` from the shell that
    launched it (it's a universal *exported* var, `set -Ux`). If we
    pass that env through to the fish probe, fish reads the env-var
    value, not the on-disk universal — and we get back the
    launch-time snapshot forever. We strip every `TGT_*` from the
    child env so fish has to fall back to `fish_variables`, which is
    the actual source of truth and updates with each `tgt scenario
    switch`.
    """
    global _active_cache
    now = time.monotonic()
    if _active_cache and now - _active_cache[0] < _ACTIVE_TTL:
        return _active_cache[1]
    clean_env = {k: v for k, v in os.environ.items() if not k.startswith("TGT_")}
    try:
        r = subprocess.run(
            ["fish", "-c", "set -q TGT_SCENARIO; and echo -n -- $TGT_SCENARIO"],
            capture_output=True, text=True, timeout=3,
            stdin=subprocess.DEVNULL, env=clean_env,
        )
        value = r.stdout if r.returncode == 0 else ""
    except (FileNotFoundError, subprocess.TimeoutExpired):
        value = ""
    _active_cache = (now, value)
    return value


def invalidate_active_cache() -> None:
    """Drop the active-scenario cache. Called after a write so the
    next read sees fresh state immediately, without waiting out TTL."""
    global _active_cache
    _active_cache = None


def fish_unescape(s: str) -> str:
    """Reverse `string escape --style=script` for the wrappings we emit.

    fish's `string escape` produces one of three forms:
      - bare token        (safe characters only)
      - single-quoted     'foo bar'  — backslash-escapes \\ and \'
      - double-quoted     "..."      — used for values with embedded single quotes

    A value containing a literal single quote becomes `\\'` inside a
    bare or single-quoted token (e.g. `it\\'s`), or appears as `'"'"'`
    when fish opens a new single-quoted segment around the quote
    (`'foo'\"'\"'bar'`). We collapse all of those.
    """
    if not s:
        return ""
    s = s.strip()
    if len(s) >= 2 and s[0] == "'" and s[-1] == "'":
        body = s[1:-1]
    elif len(s) >= 2 and s[0] == '"' and s[-1] == '"':
        body = s[1:-1].replace('\\"', '"')
    else:
        body = s
    return body.replace("\\'", "'").replace("\\\\", "\\")


def parse_export_file(path: Path) -> dict[str, str]:
    """Parse a `_tgt_export VAR value` file into {VAR: unescaped_value}."""
    out: dict[str, str] = {}
    if not path.is_file():
        return out
    for line in path.read_text(errors="replace").splitlines():
        m = EXPORT_RE.match(line)
        if not m:
            continue
        out[m.group(1)] = fish_unescape(m.group(2))
    return out


def _count_fish(d: Path) -> int:
    if not d.is_dir():
        return 0
    return sum(1 for f in d.iterdir() if f.suffix == ".fish")


def _read_marker(p: Path) -> str:
    if not p.is_file():
        return ""
    return p.read_text(errors="replace").strip()


def list_scenarios() -> list[dict]:
    """List all scenarios with summary counts + archived/active flags."""
    home = tgt_home()
    sc_root = home / "scenarios"
    if not sc_root.is_dir():
        return []
    active = read_active_scenario()
    out = []
    for sd in sorted(sc_root.iterdir()):
        if not sd.is_dir():
            continue
        out.append({
            "name": sd.name,
            "active": sd.name == active,
            "archived": (sd / ".archived").exists(),
            "target_count": _count_fish(sd / "targets"),
            "cred_count": _count_fish(sd / "creds"),
            "dc_count": _count_fish(sd / "dcs"),
        })
    return out


def scenario_detail(name: str) -> dict | None:
    """Detail for one scenario: targets, creds, DCs, active markers."""
    home = tgt_home()
    sd = home / "scenarios" / name
    if not sd.is_dir():
        return None

    active_dc = _read_marker(sd / ".active-dc")
    active_cred = _read_marker(sd / ".active-cred")

    targets = []
    if (sd / "targets").is_dir():
        for f in sorted((sd / "targets").glob("*.fish")):
            data = parse_export_file(f)
            hosts_raw = data.get("TGT_HOSTS", "")
            targets.append({
                "alias": f.stem,
                "host": data.get("TGT", ""),
                "hosts": hosts_raw.split() if hosts_raw else [],
            })

    creds = []
    if (sd / "creds").is_dir():
        for f in sorted((sd / "creds").glob("*.fish")):
            data = parse_export_file(f)
            creds.append({
                "alias": f.stem,
                "active": f.stem == active_cred,
                "username": data.get("TGT_CRED_USERNAME", ""),
                "has_password": bool(data.get("TGT_CRED_PASSWORD")),
                "domain": data.get("TGT_CRED_DOMAIN", ""),
                "notes": data.get("TGT_CRED_NOTES", ""),
            })

    dcs = []
    if (sd / "dcs").is_dir():
        for f in sorted((sd / "dcs").glob("*.fish")):
            data = parse_export_file(f)
            dcs.append({
                "alias": f.stem,
                "active": f.stem == active_dc,
                "domain": data.get("TGT_DC_DOMAIN", ""),
                "realm": data.get("TGT_DC_REALM", ""),
                "kdc_host": data.get("TGT_DC_HOST", ""),
                "kdc_ip": data.get("TGT_DC_IP", ""),
                "admin_host": data.get("TGT_DC_ADMIN_HOST", ""),
                "admin_ip": data.get("TGT_DC_ADMIN_IP", ""),
            })

    return {
        "name": name,
        "active": name == read_active_scenario(),
        "archived": (sd / ".archived").exists(),
        "targets": targets,
        "creds": creds,
        "dcs": dcs,
    }


def cred_password(scenario: str, alias: str) -> str:
    """Read the actual password value (used by /password endpoint)."""
    home = tgt_home()
    f = home / "scenarios" / scenario / "creds" / f"{alias}.fish"
    return parse_export_file(f).get("TGT_CRED_PASSWORD", "")
