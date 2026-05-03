# pentest-fish-functions

A [fish shell](https://fishshell.com/) plugin for pentesting workflows.
Tested on Arch, Parrot OS, and Kali.

The flagship command is **`tgt`** — a target environment manager that
handles `/etc/hosts`, `/etc/krb5.conf`, env vars, and BloodHound
ingest. Targets organize into **scenarios** (HTB Pro Lab seasons,
client engagements) with fzf-based switching.

## Install

### 1. Dependencies

Most are pre-installed on pentesting-focused distros.

**Arch:**

```bash
sudo pacman -S fish fzf python-pipx
```

**Parrot OS:**

```bash
sudo apt install fish fzf pipx
```

**Kali Linux:**

```bash
sudo apt install fish fzf python3-pipx
```

For Active Directory ingest (optional — only if you use `tgt ingest`):

```bash
pipx install bloodhound
```

For running the test suite (dev only — needs Fisher + fishtape):

```fish
curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
fisher install jorgebucaran/fisher jorgebucaran/fishtape
```

### 2. Install the plugin

Two paths, depending on whether you intend to develop on this repo or
just use it.

**A. Use it (production):**

```fish
fisher install fuxx/pentest-fish-functions
```

(Or any local path: `fisher install /path/to/clone`.)

**B. Develop on it (symlink-based, fast iteration):**

```bash
git clone <repo-url> /path/to/clone
cd /path/to/clone
make dev
```

`make dev` symlinks the repo's `functions/`, `conf.d/`, `completions/`
contents into your `~/.config/fish/`. Edits in the repo are picked up
by new fish shells immediately — no re-install needed.

`make undev` removes the symlinks.

### 3. Verify

Open a new fish shell and run:

```fish
tgt --help
tgt <TAB>          # subcommand completion
tgt switch <TAB>   # completes from active scenario's targets
```

### Optional: prompt segment

Add a `[scenario:target]` indicator to your prompt — color-coded by
damage potential (red = creds loaded, yellow = host/port set, default
= scenario only).

```fish
tgt prompt install            # writes ~/.config/fish/functions/fish_right_prompt.fish
tgt prompt install --left     # use the left prompt instead
tgt prompt status             # show what's installed
tgt prompt uninstall          # remove the managed file
```

If you already have a custom `fish_(right_)prompt`, `tgt prompt
install` refuses to overwrite it. Either add `tgt_prompt` to it by
hand, or rerun with `--force` (your existing file is backed up to
`<file>.tgt-bak`).

## Quickstart

```fish
# Set up an engagement / lab season
tgt scenario new dante

# Add a target
tgt new web01
tgt              # interactive wizard for IP / port / creds / AD

# Add another target — gets its own /etc/hosts entry
tgt new dc01
tgt --add-host dc01.dante.local

# Switch between targets (no-arg → fzf picker)
tgt switch
tgt switch web01

# Run BloodHound (if AD set up)
tgt ingest <user> <password> --zip

# When the engagement closes
tgt scenario rm dante   # wipes /etc/hosts entries, krb5 realm, registry
```

## Commands

### Scenarios and targets

| Command | Behavior |
|---|---|
| `tgt scenario new <name>` | Create scenario, activate it |
| `tgt scenario list` | List scenarios; `*` marks active |
| `tgt scenario switch [name]` | Switch active scenario (no arg → fzf) |
| `tgt scenario show [name]` | Show scenario details |
| `tgt scenario rm [name] [--purge-workspace]` | Delete scenario + `/etc/hosts` entries; `--purge-workspace` also `rm -rf`s its workspace folder |
| `tgt new <alias>` | Create target in active scenario |
| `tgt switch [alias]` | Load target's saved env vars (no arg → fzf) |
| `tgt list` | List targets in active scenario |
| `tgt rm [alias] [--purge-workspace]` | Delete target + `/etc/hosts` entries; `--purge-workspace` also removes the target's workspace folder (nested layout only) |
| `tgt` (no args) | Interactive setup; auto-saves to active target |
| `tgt --show` | Print current state |
| `tgt --revoke` | Clear env vars + `/etc/hosts` for active target; deselects target (keeps scenario) |

### `/etc/hosts`

```
tgt --add-host <host> [host..]   Add hostnames for active target
tgt --rm-host <host> [host..]    Remove hostnames
```

All entries are tagged `# tgt:<scenario>:<target>`. The tool only
touches lines it owns — your manual `/etc/hosts` entries are safe.

### Active Directory

```
tgt --set-dc <DC_HOSTNAME>       Set DC + update /etc/krb5.conf realm
tgt ingest <user> <pass> [--zip] Run bloodhound-python
```

When the workspace folder for the active target exists on disk,
`tgt ingest` runs from that target's `loot/` subfolder (created
on demand) so JSON / zip output lands there. Otherwise it stays
in `$PWD`.

### Workspace folders

`tgt` can keep a directory tree per scenario (and per target) so scan
output, loot, exploits, and notes have a predictable home — useful
for reporting at the end of an engagement. Off by default.

```fish
set -Ux TGT_WORKSPACE_AUTOCREATE 1     # opt in
set -Ux TGT_WORKSPACE_ROOT ~/Documents/pentest    # default value
set -Ux TGT_WORKSPACE_LAYOUT flat      # or 'nested' (see below)
```

| Command | Behavior |
|---|---|
| `tgt cd [alias\|--scenario]` | `cd` to active target's / scenario's folder |
| `tgt path [alias\|--scenario]` | Print the workspace path (no `cd`) |
| `tgt workspace` | Show settings + visualize the active scenario's tree |

**Layouts:**

`flat` — everything at scenario level. Good for HTB single boxes.

```
~/Documents/pentest/dante/
├── scans/  loot/  exploits/  screenshots/
└── notes.md
```

`nested` — per-target subfolders + scenario-level report assets.
Better for Pro Labs / client engagements with many targets.

```
~/Documents/pentest/dante/
├── _report/{findings,screenshots}/
├── _engagement.md
├── web01/
│   ├── scans/  loot/  exploits/  screenshots/
│   └── notes.md
└── dc01/
    └── ...
```

When `$TGT_WORKSPACE_AUTOCREATE` is set, `tgt scenario new` and `tgt
new` create the matching folders. Removal is opt-in via
`--purge-workspace` on `tgt rm` / `tgt scenario rm`.

## Storage

State lives at `~/.config/fish/tgt/` (override with `$TGT_HOME`):

```
~/.config/fish/tgt/
└── scenarios/
    └── <scenario>/
        └── targets/
            └── <alias>.fish    # _tgt_export TGT 10.10.11.5 ...
```

Universal env vars (`set -Ux`) are synchronized across fish sessions
by fish itself.

## Upgrading from a pre-scenarios install

If you have `$TGT` set from earlier use, the first `tgt` invocation
after upgrade auto-migrates the state into a `default` scenario with
a `default` target. Nothing to do — open a new shell and `tgt list`
will show the migrated entry.

## Development

### Tests

```bash
make test
```

Currently 346 tests across scenarios, targets, `/etc/hosts`,
`/etc/krb5.conf`, picker, prompt, migration, workspace, completions,
and boundary helpers.
Tests run sudoless against tmp files via the `TGT_TEST_MODE`
indirection.

### Layout

```
.
├── functions/              all .fish functions, flat (Fisher convention)
│   ├── tgt.fish            main dispatcher
│   ├── _tgt_*.fish         private helpers (underscore-prefixed; fish hides them)
│   ├── tgt_prompt.fish     public prompt segment function
│   ├── tun0ip.fish, showip.fish, machines.fish
├── conf.d/                 fish startup hooks (currently empty)
├── completions/            tab completions (currently empty)
├── test/                   fishtape tests + fixtures
├── specs/                  design notes
├── README.md  CLAUDE.md  Makefile
```

This is a standard Fisher plugin layout. `functions/` must be flat —
fish doesn't recurse into subfolders of `$fish_function_path`.
Per-tool grouping happens via filename prefix (`_tgt_*`).

### Adding a function

Drop a new file in `functions/`. With `make dev` active, a new shell
picks it up. Naming: public functions get a plain name (`mything`),
private helpers get an underscore prefix (`_mything_helper`) so fish
hides them from default tab completion and `functions` listings.

### Multiple plugins coexisting

This is a Fisher plugin. Other Fisher plugins coexist with it in your
`~/.config/fish/` — Fisher tracks which files came from which plugin
in `~/.config/fish/fish_plugins`. With `make dev`, the symlinks are
named after files in this repo and won't collide with another
plugin's files (assuming the other plugin doesn't ship the same
filenames).

## Uninstall

```bash
make undev      # if you used `make dev`
make uninstall  # if you used Fisher
```

`make undev` removes only the symlinks that point into this repo —
nothing else. To fully remove, also delete the repo directory.

## Specs / design notes

The `specs/` directory holds design discussions for the larger
features (multi-target / scenarios, `/etc/hosts` redesign, testing
strategy, configuration TUI backlog). Read them for the *why* behind
architectural choices.
