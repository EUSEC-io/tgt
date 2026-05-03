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
```

### Optional: prompt segment

Add a `[scenario:target]` indicator to your prompt — color-coded by
damage potential (red = creds loaded, yellow = host/port set, default
= scenario only):

```fish
# in ~/.config/fish/config.fish
function fish_right_prompt
    tgt_prompt
end
```

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
| `tgt scenario rm [name]` | Delete scenario + its `/etc/hosts` entries |
| `tgt new <alias>` | Create target in active scenario |
| `tgt switch [alias]` | Load target's saved env vars (no arg → fzf) |
| `tgt list` | List targets in active scenario |
| `tgt rm [alias]` | Delete target + its `/etc/hosts` entries |
| `tgt` (no args) | Interactive setup; auto-saves to active target |
| `tgt --show` | Print current state |
| `tgt --revoke` | Clear env vars + `/etc/hosts` for active target |

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

Currently 197 tests across scenarios, targets, `/etc/hosts`,
`/etc/krb5.conf`, picker, prompt, migration, and boundary helpers.
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
