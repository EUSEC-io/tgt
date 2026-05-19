# `tgt web` — local browser UI (proof of concept)

Status: **PoC, branch `web-ui-poc`.** Read works; a handful of write
actions wired (switch / unload / archive / unset). Not Fisher-installable
yet (Fisher only copies `.fish` files — see "Distribution" below).

## What it is

A localhost-only web dashboard for the `tgt` plugin. Renders the same
scenario / target / cred / DC state you'd see from `tgt scenario show`
+ `tgt cred list` + `tgt dc list`, in a clickable layout.

```
tgt web              # picks a free port, opens browser
tgt web --port 8080
tgt web --no-open    # for SSH / headless usage
```

## How it's built

- **`web/server.py`** — single Python file (stdlib only: `http.server`,
  `json`, `subprocess`, `re`). ~300 lines including the embedded HTML/
  CSS/JS. No frameworks, no bundlers, no npm. Vanilla `fetch()`.
- **`functions/tgt_web.fish`** — fish wrapper. Locates `web/server.py`
  relative to its own path, execs `python3` against it.
- **`tgt.fish`** — dispatches `tgt web` → `tgt_web` (see the dispatch
  block just below the `tgt cred` case).

## Design rules (keep stable across changes)

1. **Localhost only.** `127.0.0.1`. No external bind. No auth — same
   single-user threat model as `fish_config`.
2. **Reads parse the registry files directly** under `$TGT_HOME`. The
   format is stable (same `_tgt_export VAR value` lines fish writes),
   and reads have no side effects. The Python parser mirrors what
   `_tgt_*_inspect.fish` does — including the `string unescape` reverse
   of `string escape`.
3. **Writes ALWAYS shell out to `tgt`.** Never reimplement save /
   load / krb5-sync / hosts-sync. The `ACTIONS` table in `server.py`
   whitelists every action; client requests must hit one of those
   names with the required params. No raw argv from the client.
4. **Mirror new commands.** When a new `tgt` verb lands in fish, add
   it to:
   - `ACTIONS` in `server.py` (if it's a write) — `{name: (argv_builder, [required_params])}`.
   - The reader functions (`list_scenarios`, `scenario_detail`, …) if it introduces a new field type.
   - The frontend `render*` functions for any new UI surface.
   See the "Adding a new action" section below.

## Adding a new action

Say we add `tgt cred rename <old> <new>` (already exists) and want a
rename button in the web UI.

1. **Add to `ACTIONS` in `server.py`**:
   ```python
   "cred_rename": (lambda p: ["cred", "rename", p["old"], p["new"]], ["old", "new"]),
   ```
2. **Wire the button in `INDEX_HTML`'s JS** — call `act("cred_rename", {old: ..., new: ...})`.
3. **No new read parsing needed** — rename doesn't introduce a field.

If the new action introduces a new field on disk (e.g. a hypothetical
`TGT_CRED_KEYTAB`), also update the reader in `scenario_detail()` so
the field surfaces in the JSON sent to the frontend.

## Distribution (open question)

Fisher only copies `.fish` files. To ship the web UI to Fisher users
we need ONE of:

1. **Embed Python in a fish heredoc**: `functions/tgt_web.fish` holds
   the Python source as a single-quoted multi-line string, pipes it
   to `python3 -`. Ugly but Fisher-clean.
2. **Separate install step**: `make install-web` copies `web/server.py`
   to a known path (`~/.local/share/tgt/server.py`). Users who want
   the UI run this once. Keeps the source readable.
3. **Defer**: keep the PoC `make dev`-only until we decide if it's
   worth the distribution cost.

Currently on **(3)**. Pick after the PoC settles.

## Known limitations (PoC)

- **No create/edit/delete forms** — only switch / unset / archive /
  unload. Wizards remain CLI-only for now.
- **Password reveal**: clicking "reveal" hits a separate endpoint and
  shows the plaintext inline. No copy-to-clipboard, no auto-hide.
- **Auto-refresh every 5 s** — picks up CLI changes but not instant.
  No WebSocket / SSE.
- **No multi-shell coordination** — if you `tgt cred switch` in a
  shell, the web UI shows it on next refresh. Universal vars across
  shells already handle this; the UI just polls.
- **Errors are dropped into a toast** — no detailed log view.

## Removing the PoC

If we decide not to keep this, the surface to revert is small:

- Delete: `web/`, `functions/tgt_web.fish`
- Revert: the `tgt web` dispatch block in `functions/tgt.fish`, the
  `web` entries in `completions/tgt.fish`.

That's it. No tests touch this; no other functions depend on it.
