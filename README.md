# pentest-fish-functions

A collection of [fish shell](https://fishshell.com/) functions for
pentesting. Works on Arch, Parrot OS, Kali, and any distro running
fish.

The flagship command is **`tgt`** — a target environment manager that
handles `/etc/hosts`, `/etc/krb5.conf`, env vars, and BloodHound
ingest. Targets can be organized into **scenarios** (HTB Pro Lab
seasons, client engagements) with fzf-based switching.

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

To run the test suite (dev-only):

```fish
curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
fisher install jorgebucaran/fisher jorgebucaran/fishtape
```

### 2. Clone

You can put the repo anywhere. Two common choices:

**Option A — into fish's config dir** (no install step required for
top-level files; subfolder tools still need step 3):

```bash
git clone <repo-url> ~/.config/fish/functions
```

**Option B — anywhere else:**

```bash
git clone <repo-url> ~/repos/pentest-fish-functions
```

### 3. Activate the loader

```bash
cd <wherever you cloned>
./bin/install.fish     # or: make install
```

This symlinks `conf.d/tgt-loader.fish` into `~/.config/fish/conf.d/`
so fish autoloads from each tool's subfolder. Idempotent and
location-independent — re-run after moving the repo.

### 4. Verify

```fish
tgt --help
```

### Optional: prompt segment

Add `[scenario:target]` to your prompt — color-coded by damage
potential (red = creds loaded, yellow = host/port set, default =
scenario only):

```fish
# in ~/.config/fish/config.fish
function fish_right_prompt
    tgt_prompt
end
```

## Quickstart

```fish
# Set up a scenario for an engagement / lab season
tgt scenario new dante

# Add a target inside it
tgt new web01
tgt              # interactive wizard for IP / port / creds / AD

# Add another target — gets its own /etc/hosts entry
tgt new dc01
tgt --add-host dc01.dante.local

# Switch between targets (fzf picker without arg)
tgt switch
tgt switch web01

# Run BloodHound (if AD set up)
tgt ingest <user> <password> --zip

# When the engagement closes
tgt scenario rm dante   # wipes /etc/hosts, krb5 realm, registry — one shot
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

## Upgrading from before scenarios existed

If you had `$TGT` set from previous use, the first `tgt` invocation
after upgrade auto-migrates your state into a `default` scenario with
a `default` target. Nothing to do — open a new shell and `tgt list`
will show the migrated entry.

## Development

### Tests

```bash
make test
```

Currently 197 tests covering scenarios, targets, `/etc/hosts`
management, krb5 realm management, picker, prompt, migration, and
boundary helpers. Tests run sudoless against tmp files via the
`TGT_TEST_MODE` indirection.

### Project layout

```
.
├── bin/                    install.fish, uninstall.fish
├── conf.d/                 fish startup hooks (the loader)
├── specs/                  cross-cutting design docs
├── tgt/                    the tgt tool
│   ├── tgt.fish            main dispatcher
│   ├── _tgt_*.fish         helpers (autoloaded, hidden)
│   ├── tgt_prompt.fish     public prompt segment function
│   ├── test/               tests + fixtures
│   └── specs/              tool-specific design notes
├── tun0ip/, showip/, ...   other small tools
└── Makefile                make install / uninstall / test
```

Each tool lives in its own folder. The loader registers
`<tool>/<tool>.fish` for autoload — so a folder counts as a tool
folder when it contains a same-named primary `.fish` file.

### Adding a new tool

```bash
mkdir mytool
cat > mytool/mytool.fish <<'EOF'
function mytool --description '...'
    echo hi
end
EOF
```

Open a new shell — fish autoloads it. Update `.gitignore` to track
the folder if you want it shared.

### Adding your own personal functions

The `.gitignore` allowlist means files you drop in won't be tracked
unless explicitly listed. Personal scripts live alongside without
interfering with pulls.

## Uninstall

```bash
cd <repo>
./bin/uninstall.fish     # or: make uninstall
```

Removes the loader symlink. Repo stays on disk — re-run
`./bin/install.fish` to reactivate. To fully remove, also delete the
repo directory.

## Specs / design notes

The `specs/` and `tgt/specs/` folders contain design discussions for
larger features (multi-target, `/etc/hosts` redesign, testing
strategy, configuration TUI). Read them for the *why* behind
architectural choices.
