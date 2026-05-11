# Changelog

This plugin doesn't cut versioned releases — `master` is what you
get. Entries are reverse-chronological; the top is the freshest.
Older milestones live in `git log`.

## Unreleased

### Commands added
- `tgt cred …` — credentials are now first-class scenario-level
  entries, mirroring `tgt dc`. Subcommands: `list / show / new /
  switch / edit / rename / unset / rm` (bare `tgt cred` drops into
  the switch picker). One scenario holds many credentials (foothold,
  lateral, DA…) and `tgt cred switch <alias>` loads
  `TGT_USERNAME` / `TGT_PASSWORD` / `TGT_CRED_*`. The prompt picks
  it up as `+<alias>`. Same field stores NT/AES hashes — no separate
  `--hash` flag. The active credential per scenario is remembered
  across `tgt scenario switch`. **Migration:** target files no longer
  persist `TGT_USERNAME` / `TGT_PASSWORD` / `TGT_AD_DOMAIN`; legacy
  lines are filtered on load, so existing target files keep working
  but those fields are silently dropped on next save. Move your
  creds into `tgt cred new` and they survive scenario switches.
- `tgt scenario import <path> [--copy] [--dry-run] [--prefix <p>]`
  — bulk-import each subdir under `<path>` as a scenario. Default
  moves the dir into the workspace root; `--copy` keeps the source
  intact; `--prefix` prepends a string to each scenario name (e.g.
  `--prefix htb-` turns `lame/` into `htb-lame`); `--dry-run`
  prints the plan without touching anything. Names with `.`,
  spaces, or other invalid chars are sanitized (invalid → `-`,
  dashes collapsed and trimmed; case is preserved). Conflicts (scenario
  exists, workspace dest exists) are skipped, not clobbered.
- `tgt scenario archive [name]` and `tgt scenario unarchive [name]` —
  mark a scenario as archived (hidden from `tgt scenario list` by
  default) or revive it. Marker is just a `.archived` file under
  the scenario's registry dir. `tgt scenario list --all` shows
  archived too with an `[archived]` tag; `tgt scenario list
  --archived` shows only archived. Switch picker hides archived
  by default — pass `--all` or name explicitly to revive.
- `tgt rename [<old>] <new>` and `tgt scenario rename [<old>] <new>` —
  rename a target / scenario in place. Moves the registry file or
  scenario directory, retags `/etc/hosts` entries, moves the
  workspace folder, and updates `$TGT_ACTIVE` / `$TGT_SCENARIO` if
  the renamed item was the active one. Refuses to overwrite an
  existing alias / scenario name.
- `tgt scenario` (no args) — interactive picker (gum + TTY) for
  new / switch / show / rm. Falls back to help text on
  scripts / CI / tests.
- `tgt scenario show` — dashboard with per-target row state
  (`host[:port]`, creds Y/N, AD Y/N, hostnames count). Active
  target starred and bolded.
- `tgt scenario list` — now also shows target count + creds/AD
  flags per scenario.
- `tgt edit [alias]` — switches if needed, then runs the wizard.
- `tgt new [alias] [--no-edit]` — chains into the wizard by
  default; `--no-edit` keeps the old "create slot only" behavior.
  No alias → prompts for one.
- `tgt hosts` — multi-line editor for the active target's
  hostnames.
- `tgt cd [alias|--scenario]` / `tgt path` — navigate to the
  workspace folder tree (or print its path).
- `tgt workspace` / `tgt workspace create [alias]` — show settings
  and tree, or manually build the folder tree.
- `tgt config` / `tgt config show` / `tgt config reset` —
  interactive editor for workspace settings (gum or plain `read` +
  `$EDITOR`). Persisted as fish universals.
- `tgt prompt install / uninstall / status` — wires `tgt_prompt`
  into `fish_(right_)prompt` (`--right|--left|--force`).

### Storage migration
- Workspace config now lives in `~/.config/fish/tgt/config.fish`
  (plain fish source, sourced by a `conf.d/` hook at shell startup).
  Replaces the old "stored as fish universal vars" approach. The
  file is `cat`-friendly, version-controllable, and can be rsynced
  between machines. One-shot migration: on first startup with
  existing universals and no file yet, `_tgt_config_migrate` writes
  the universals' values into the file and erases them. Env vars
  exported in the current shell still override the file values at
  lookup time — used by tests and by ad-hoc overrides.

### Behaviors changed
- **`/etc/hosts` hot-swaps on scenario change.** Switching scenarios
  (and `tgt scenario new`) now revokes the old scenario's tagged
  lines and adds the new scenario's targets' lines in a single
  atomic write. Avoids cross-scenario IP collisions (matters for
  HTB / Pro Labs where IPs are recycled). Single sudo prompt per
  switch. Manual (non-tgt-tagged) lines are preserved.
- `tgt --revoke` also unsets `$TGT_ACTIVE` (deselects the target;
  scenario is kept).
- `tgt rm <alias>` and `tgt scenario rm <name>` now clean their AD
  realm(s) from `/etc/krb5.conf` when no remaining target uses
  them. Cross-scenario realm sharing is respected.
- `tgt --show` now also visualizes the workspace tree under the
  env / `/etc/hosts` / krb5 sections.
- `tgt ingest` auto-routes BloodHound JSON / zip into the active
  target's `loot/` subfolder when the workspace folder exists.
- Wizard (`tgt` no-args) is now a gum-aware 4-section walker
  (Host & port, Hostnames, Credentials, AD) with numbered
  headers, bold-yellow labels, dim hints, and clean Ctrl-C abort
  at any prompt. BloodHound ingest is the standalone `tgt ingest`
  command — no longer chained from the wizard, since at target
  creation time you usually don't have credentials yet.
- One-line sudo notice (deduped per `tgt` invocation) explains why
  the password prompt is about to fire when modifying `/etc/hosts`
  or `/etc/krb5.conf`.

### Workspace folders
New optional feature off by default. Set `$TGT_WORKSPACE_AUTOCREATE`
to opt in.

- `$TGT_WORKSPACE_ROOT` (default `~/Documents/pentest`).
- `$TGT_WORKSPACE_LAYOUT` — `flat` (everything at scenario level —
  HTB single boxes) or `nested` (per-target subfolders + scenario
  `_report/` — Pro Labs / clients).
- `$TGT_WORKSPACE_TARGET_TEMPLATE` / `$TGT_WORKSPACE_SCENARIO_TEMPLATE`
  list which folders / files to seed per target / per scenario;
  trailing `/` marks a directory.
- `--purge-workspace` flag on `tgt rm` / `tgt scenario rm` removes
  the corresponding folder.

### Fixed
- `_tgt_clean_krb5` now also resets `default_realm` when its current
  value is the realm being removed (falls back to a surviving realm
  or `ATHENA.MIT.EDU`).
- `tgt scenario` (no args) gates on `isatty stdin` so
  scripts / CI / tests don't open the gum picker.
- A few test blocks no longer try to atomically `mv` over the real
  `/etc/hosts` (was harmless but noisy).
- Backslash-backticks (`\``) in echo strings rewritten to plain
  backticks — fish doesn't escape backticks inside `""`.

### Internal
- `_tgt_update_krb5` rewritten to do a single atomic
  `_tgt_krb5_write` instead of three separate sudo'd `sed -i` /
  `sh -c` calls.
- Wizard extracted from `tgt.fish` into `_tgt_wizard.fish`.
- Four `_tgt_ask_*` helpers (text / choice / confirm / password /
  multiline) centralize the gum-or-fallback branching.
- Fish completions for `tgt` are subcommand-aware and dynamically
  pull scenario / target lists from the registry.
- Test count: 211 → 456.

## Pre-Unreleased history

See `git log` for the earlier arc: scenario / target storage,
tagged `/etc/hosts` rewrite, fzf picker, prompt segment, Fisher
plugin restructure, etc.
