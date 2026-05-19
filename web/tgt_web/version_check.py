"""Compare the installed `tgt` fish plugin against this package's version.

The web UI is a separate Python package that shells out to `tgt` for
every write — so the two halves can drift. We surface a warning when
they do, both in the startup log and in the UI header.
"""

from __future__ import annotations

import subprocess
from dataclasses import dataclass
from typing import Optional

from tgt_web import __version__


@dataclass
class VersionInfo:
    web: str
    tgt: Optional[str]
    mismatch: bool
    note: str


def _query_tgt_version() -> Optional[str]:
    """Return the fish-side version string, or None if `tgt` is unavailable."""
    try:
        r = subprocess.run(
            ["fish", "-c", "tgt --version"],
            capture_output=True, text=True, timeout=5,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None
    if r.returncode != 0:
        return None
    out = r.stdout.strip()
    return out or None


def check() -> VersionInfo:
    """Run the comparison. Never raises — drift here is a warning."""
    tgt = _query_tgt_version()
    if tgt is None:
        return VersionInfo(
            web=__version__,
            tgt=None,
            mismatch=False,
            note="could not determine fish-side `tgt` version",
        )
    mismatch = tgt != __version__
    note = (
        f"version mismatch: tgt={tgt}, tgt-web={__version__}"
        if mismatch
        else f"versions match ({__version__})"
    )
    return VersionInfo(web=__version__, tgt=tgt, mismatch=mismatch, note=note)
