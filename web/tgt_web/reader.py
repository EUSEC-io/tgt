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
from pathlib import Path

EXPORT_RE = re.compile(r"^_tgt_export\s+(\S+)\s+(.*)$")


def tgt_home() -> Path:
    """Resolve $TGT_HOME the same way fish does."""
    return Path(
        os.environ.get("TGT_HOME") or Path.home() / ".config" / "fish" / "tgt"
    )


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
    active = os.environ.get("TGT_SCENARIO", "")
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
        "active": name == os.environ.get("TGT_SCENARIO", ""),
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
