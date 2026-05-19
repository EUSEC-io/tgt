# `tgt-web` — local browser UI for the `tgt` fish plugin

A localhost-only web dashboard for the `tgt` plugin. Renders the same
scenario / target / cred / DC state you'd see from `tgt scenario show`
+ `tgt cred list` + `tgt dc list`, in a clickable layout.

Status: **Phase 1.** Standalone Python package, stdlib-only, installable
via pipx. The fish plugin (`tgt`) still owns every write — this UI is
purely presentation + dispatch.

## Install

```bash
pipx install "git+https://github.com/EUSEC-io/tgt#subdirectory=web"
```

For development from a checkout:

```bash
cd <repo>/web
pipx install -e .
# or: make install-dev
```

After install, the fish wrapper finds `tgt-web` on `PATH`:

```fish
tgt web              # picks a free port, opens browser
tgt web --port 8080
tgt web --no-open    # for SSH / headless usage
```

## Sudo

`tgt` modifies `/etc/hosts` and `/etc/krb5.conf` via `sudo install`.
The CLI prompts in the terminal; the web UI has no terminal, so on
startup `tgt-web` probes for a graphical askpass helper:

1. Honors `$SUDO_ASKPASS` if you've already set it.
2. Otherwise searches `PATH` for, in order: `zenity`, `kdialog`,
   `ssh-askpass`, `ssh-askpass-gnome`, `x11-ssh-askpass`.
3. Falls back to detecting a passwordless sudoers entry
   (`sudo -n install --version` exits 0).

If none of those work, you'll get a clear error toast in the UI. The
fix is one of:

```
sudo apt install zenity        # Parrot / Kali / Debian / Ubuntu
sudo pacman -S zenity          # Arch / Manjaro
sudo dnf install zenity        # Fedora
```

…or add a NOPASSWD rule for `install`:

```
your_user ALL=(root) NOPASSWD: /usr/bin/install
```

## Architecture

```
tgt_web/
├── __init__.py           — version string
├── __main__.py           — `python -m tgt_web`
├── server.py             — HTTP plumbing only (BaseHTTPRequestHandler)
├── reader.py             — registry-file parser (pure, testable)
├── actions.py            — ACTIONS whitelist + dispatch_action
├── sudo.py               — askpass probe + NOPASSWD check
├── version_check.py      — `tgt --version` mismatch warning
└── static/               — index.html, style.css, app.js (shipped in wheel)
```

## Design rules (keep stable across changes)

1. **Localhost only.** `127.0.0.1`. No external bind. No auth — same
   single-user threat model as `fish_config`.
2. **Reads parse the registry files directly** under `$TGT_HOME`. The
   format is stable (same `_tgt_export VAR value` lines fish writes),
   and reads have no side effects. The Python parser mirrors what
   `_tgt_*_inspect.fish` does — including the `string unescape` reverse
   of `string escape`.
3. **Writes ALWAYS shell out to `tgt`.** Never reimplement save / load /
   krb5-sync / hosts-sync. The `ACTIONS` table in `actions.py`
   whitelists every action; client requests must hit one of those names
   with the required params. No raw argv from the client.
4. **Mirror new commands.** When a new `tgt` verb lands in fish, add it
   in lock-step here. The drift contract (`tgt --list-mutating-verbs
   --json` ⊆ `ACTIONS` keys) is enforced by `tests/test_drift.py` and
   fails CI if you forget. See "Adding a new action" below.

## Adding a new action

Say a `tgt cred rename <old> <new>` button gets added to the UI.

1. **Add to `ACTIONS` in `actions.py`**:
   ```python
   "cred_rename": (lambda p: ["cred", "rename", p["old"], p["new"]], ["old", "new"]),
   ```
2. **Add to `tgt --list-mutating-verbs --json`** in `functions/tgt.fish`:
   ```fish
   {"action": "cred_rename", "argv": ["cred", "rename", "<old>", "<new>"]},
   ```
3. **Wire the button in `static/app.js`** — call `act("cred_rename", {old, new})`.
4. **No new read parsing needed** unless the action introduces a new
   on-disk field (e.g. a hypothetical `TGT_CRED_KEYTAB` would need
   `reader.scenario_detail` updated too).

## Development

```bash
make test-web       # pytest in web/tests/
make test-all      # fishtape + pytest + drift contract
make install-dev   # pipx install -e .
```

The drift test (`tests/test_drift.py`) needs `fish` on PATH; it
auto-sources every `.fish` in `../functions/`, so no Fisher install
is required.

## Known limitations

- **No create/edit/delete forms yet** — only switch / unset / archive /
  unarchive / unload. Wizards remain CLI-only (Phase 2 backlog).
- **Password reveal** is plaintext-in-DOM; no copy-to-clipboard, no
  auto-hide (Phase 2 backlog).
- **Auto-refresh every 10 s** — picks up CLI changes but not instant.
  No WebSocket / SSE yet (Phase 2 backlog).
- **Errors land in a toast** — no detailed log view.

## Uninstall

```bash
pipx uninstall tgt-web
```

The fish wrapper (`functions/tgt_web.fish`) will then print an install
hint when invoked, but never break.
