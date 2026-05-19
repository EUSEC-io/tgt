# Phase 1 — Foundation rewrite

**Branch:** `web-ui` (was `web-ui-poc` during PoC).
**Status:** PoC complete and committed. Phase 0 decisions locked in below.
This document is the handoff from the planning session — a fresh
Claude session should be able to start Phase 1 directly from here
plus `web/README.md` plus the memory entry `feedback_mirror_web_ui`.

Read order for context:
1. This file (Phase 1 scope + design decisions).
2. `web/README.md` (design rules, distribution caveats, "how to add an action").
3. `~/.claude/projects/-home-smp86-Development-fish-tgt/memory/feedback_mirror_web_ui.md` (the mirror-new-commands discipline).
4. `web/server.py` (PoC — will be split into modules during Phase 1).

---

## Phase 0 decisions (locked)

| Topic | Decision |
|---|---|
| Repo model | Same repo (`EUSEC-io/tgt`), Python package lives under `web/`. |
| Branch | `web-ui` (renamed from `web-ui-poc`). Merge to master when Phase 1 is green. |
| Distribution | **pipx**, install via git URL initially. PyPI later when stable. |
| Sudo strategy | `SUDO_ASKPASS` auto-probe (zenity / kdialog / ssh-askpass) primary; opt-in NOPASSWD sudoers as documented fallback. |
| Tests | pytest under `web/tests/`, run via `make test-web`. CI: GitHub Actions on PR. |
| Drift prevention | Add `tgt --list-mutating-verbs --json` on the fish side; contract test asserts every entry has an `ACTIONS` mapping. |
| Cross-version coupling | `tgt-web` runs `tgt --version` at startup; warns on mismatch. |
| Branch fish wrapper | `tgt_web.fish` execs `command tgt-web $argv`; degrades gracefully with install hint if not installed. |
| ASKPASS install tips | Documented in pyproject readme + the error message. Suggest `zenity` (gnome / parrot), `kdialog` (kde), `ssh-askpass-gnome` (universal). |

---

## Phase 1 scope

Goal: replace the single-file PoC with a real Python package, tested,
pipx-installable, with proper sudo handling. The web UI stays
functionally equivalent at the end of Phase 1 — no new features.
Phase 2 handles features and polish.

### File structure

```
web/
├── pyproject.toml              ← project metadata (stdlib-only, no deps)
├── README.md                   ← keep current; update install command to pipx
├── PHASE1.md                   ← this file; delete when phase 1 lands
├── Makefile                    ← convenience: `make test`, `make install-dev`
├── tgt_web/
│   ├── __init__.py             ← version string
│   ├── __main__.py             ← `python -m tgt_web` entry; calls server.main()
│   ├── server.py               ← HTTP plumbing only (BaseHTTPRequestHandler etc.)
│   ├── reader.py               ← registry file parsing (pure, testable)
│   ├── actions.py              ← ACTIONS table + dispatch_action()
│   ├── sudo.py                 ← askpass probe + NOPASSWD check + helpful errors
│   ├── version_check.py        ← `tgt --version` mismatch warning
│   └── static/
│       ├── index.html
│       ├── style.css
│       └── app.js
└── tests/
    ├── conftest.py             ← TGT_HOME fixture pointing at tests/fixtures/
    ├── fixtures/
    │   └── scenarios/
    │       └── …               ← canned registry data (including a corrupted-`"'"`-domain cred)
    ├── test_reader.py          ← parse-output assertions; edge cases
    ├── test_actions.py         ← mock subprocess.run; argv-building correctness
    ├── test_sudo.py            ← mock env; strategy selection
    ├── test_http.py            ← integration: spin server, hit endpoints, check JSON
    └── test_drift.py           ← contract: tgt --list-mutating-verbs ⊆ ACTIONS keys
```

### `pyproject.toml` sketch

```toml
[build-system]
requires = ["setuptools>=61"]
build-backend = "setuptools.build_meta"

[project]
name = "tgt-web"
version = "0.1.0"
description = "Local browser UI for the tgt fish plugin"
requires-python = ">=3.10"
dependencies = []  # stdlib only — http.server, json, subprocess, re
readme = "README.md"
license = {text = "MIT"}
authors = [{name = "Stefan Mayer-Popp"}]

[project.urls]
Homepage = "https://github.com/EUSEC-io/tgt"
Repository = "https://github.com/EUSEC-io/tgt"
Issues = "https://github.com/EUSEC-io/tgt/issues"

[project.scripts]
tgt-web = "tgt_web.server:main"

[tool.setuptools.packages.find]
where = ["."]
include = ["tgt_web*"]

[tool.setuptools.package-data]
tgt_web = ["static/*"]

[tool.pytest.ini_options]
testpaths = ["tests"]
```

### Tasks

1. **Module split** — move logic out of `web/server.py` into the
   files in the tree above. Each module should be importable in
   isolation. `server.py` only handles HTTP/routing now.

2. **Static assets to disk** — extract `INDEX_HTML` into
   `tgt_web/static/index.html` + `style.css` + `app.js`. The
   server reads them at startup via `importlib.resources` so they
   travel inside the installed package.

3. **`pyproject.toml`** + `MANIFEST.in` if needed. Verify
   `pipx install -e .` works locally.

4. **pytest scaffolding** with `conftest.py` setting `TGT_HOME` to
   `tests/fixtures/`. Include a fixture cred with a deliberately
   corrupted `"'"` domain value to lock in regression coverage for
   the bug Stefan hit.

5. **`tgt --list-mutating-verbs --json`** in fish (`functions/tgt.fish`)
   — emits a static JSON array of `{verb, args}` for every mutating
   action. Pure listing, no state changes. The web's `test_drift.py`
   pulls it via subprocess and asserts every entry has a matching
   `ACTIONS` key.

6. **Sudo plumbing** (`sudo.py`):
   - At startup, probe in order: `$SUDO_ASKPASS` (user override),
     `which zenity`, `which kdialog`, `which ssh-askpass`. First hit
     wins. If `zenity`/`kdialog`/`ssh-askpass` is found at a known
     path, write a tiny shell wrapper to `~/.cache/tgt-web/askpass.sh`
     that invokes it with a "tgt needs sudo to update /etc/hosts"
     prompt.
   - Subprocess calls to `tgt` set `SUDO_ASKPASS=<wrapper>` so
     `_tgt_sudo`'s `sudo -A install …` picks it up automatically.
   - If no askpass tool is available: check for a sudoers NOPASSWD
     entry by trying `sudo -n install --version`. If that works,
     the user has the opt-in path set up; carry on.
   - If neither path works: still let the action run, but surface
     a clear error in the toast with install tips:
     `pkg install zenity` (Parrot/Kali) /
     `apt install zenity` (Debian) /
     `pacman -S zenity` (Arch).

7. **Version check** — at startup, run `tgt --version` (need to add
   `--version` flag to `tgt.fish` if missing — it might just be a
   1-line addition). Compare against `tgt_web.__version__`. On
   mismatch, log a warning + surface in the UI header.

8. **Fish wrapper update** — `functions/tgt_web.fish` becomes:
   ```fish
   function tgt_web
       if not command -q tgt-web
           echo "tgt web: tgt-web not installed." >&2
           echo "  Install: pipx install \"git+https://github.com/EUSEC-io/tgt#subdirectory=web\"" >&2
           return 1
       end
       command tgt-web $argv
   end
   ```

9. **Update `web/README.md`** — pipx install command, sudo doc
   pointer, the `make install-dev` workflow. Note Phase 1 milestone.

10. **`make test-web`** target — runs pytest in the worktree's `web/`.
    `make test-all` runs fishtape + pytest.

11. **CI** — `.github/workflows/test.yml` running on PR:
    - Job 1: fish + fishtape tests
    - Job 2: Python 3.10 + 3.11 + 3.12 + pytest
    - Job 3: drift contract test (needs both fish and python)

12. **Delete `web/PHASE1.md`** at end of Phase 1 (replaced by the
    persistent docs in README.md).

### Definition of "Phase 1 done"

- [ ] `pipx install -e ./web` (from repo root) installs `tgt-web` on PATH
- [ ] `tgt web` works from a fresh shell after install
- [ ] `pytest web/tests/` is green
- [ ] `make test-all` green (fishtape + pytest + drift contract)
- [ ] CI green on a PR from `web-ui` to `master`
- [ ] Sudo flow tested manually with at least one of zenity / kdialog
- [ ] PoC's `server.py` deleted (replaced by the module split)
- [ ] `PHASE1.md` (this file) deleted
- [ ] Merge `web-ui` → `master` (or hold if Phase 2 wants more first)

---

## Phase 2 backlog (do NOT do in Phase 1)

UX polish + new features. Notes captured during planning so we don't
lose them:

- Forms for create/edit/rename/rm on each entity (scenario / target / cred / DC).
- Better action feedback: full output in a collapsible panel, not just toasts.
- Confirm modals for destructive actions (`rm`, `unload`, `archive`).
- Copy-to-clipboard buttons everywhere a value is shown.
- Auto-hide revealed passwords after 30s.
- Server-Sent Events for cross-shell state changes (replaces polling).
- Mobile-friendly responsive layout.
- Light/dark theme toggle.
- "Dry run" preview pane: what would `/etc/hosts` and `/etc/krb5.conf`
  look like after this action, before applying.

## Phase 3 backlog

- Workspace file browser (read-only first, read-write later).
- Search across all entities (find a cred by username, jump to scenario).
- Bulk operations (archive multiple, etc.).
- Stats / timeline view: which scenarios touched recently.
- Live action log (audit trail for what was clicked).

## Adjacent ideas (not web-specific, parked)

- Drop gum entirely from CLI wizards (`read -P` + `fzf` only) —
  would also categorically fix the `!` clear quirk that's lingered.
- `--json` flag across all read commands (would feed the web reader
  cleanly instead of the file-parsing approach).
- `tput cols`-aware table rendering in CLI.
- pexpect-based integration tests for the gum branch (if it survives).
- Re-record demo SVGs/GIFs with current variable names (cred / dc /
  TGT_DC_DOMAIN etc.).

---

## Notes for the next session

- The worktree is at `~/Development/fish/tgt-webui` on branch `web-ui`.
- The main checkout is at `~/Development/fish/tgt` on `master` — do
  not touch master from the new session unless explicitly asked.
- Memory dir: `~/.claude/projects/-home-smp86-Development-fish-tgt/`.
  The feedback memory `feedback_mirror_web_ui.md` is the canonical
  reminder to mirror new tgt verbs here.
- YubiKey is required for `git push`; warn Stefan before pushing.
- Last commit on `web-ui` is `9c23c18` (PoC UI v2 — master/detail
  layout, flicker fixed, archived toggle). Phase 1 builds on top.
- `make dev` symlinks are currently pointed at the main checkout
  (master). If the new session needs the web-ui branch's fish bits
  active, run `make -C ~/Development/fish/tgt-webui dev` first.
- This file (`PHASE1.md`) should be deleted when Phase 1 lands.
