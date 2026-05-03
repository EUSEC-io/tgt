# pentest-fish-functions

A [fish shell](https://fishshell.com/) plugin for pentesting workflows.
Tested on Arch, Parrot OS, and Kali.


## What it does

`tgt` is the flagship command. It remembers everything about the box
you're working on (IP, port, creds, AD domain, hostnames) and keeps
`/etc/hosts`, `/etc/krb5.conf`, and an optional per-engagement folder
tree in sync. Targets organize into **scenarios**, so a Pro Lab season
or a client engagement is one namespace; switching targets pulls up
every detail and updates the right system files.

A few flagged extras: a colored `[scenario:target]` prompt segment, an
fzf picker, archive support to hide finished engagements, BloodHound
ingest with auto-routed loot folders, and a gum-based config wizard
when [`gum`](https://github.com/charmbracelet/gum) is installed.

Sample dashboard:

```
  scenario:  dante
  active:    yes
  dir:       /home/you/.config/fish/tgt/scenarios/dante

  ─── targets (3) ─────────────────────────────────────
    target        host                     creds  AD   hosts
   * web01        10.10.10.5                 N    N    0
     dc01         10.10.10.10:445            Y    Y    2
     fileserver   10.10.10.20                Y    N    1
```


## Concepts

| Term | What it means |
|---|---|
| **scenario** | An engagement, HTB Pro Lab season, or client. Holds many targets. |
| **target** | One box / host. IP, port, creds, AD, hostnames. |
| **workspace** | Optional per-scenario / per-target directory tree (scans, loot, exploits, notes) for tidy reporting. |


## Workflows

### HTB single box

```fish
tgt scenario new lame      # one scenario per box (or use `tgt scenario import` to bulk-load existing notes)
tgt new box                # creates target slot + drops into the wizard
                           #   (fill in IP, hostname, creds when found, AD if present)
tgt --add-host lame.htb    # extra hostname, tagged so removal is precise
tgt cd                     # cd to the workspace folder for scans / loot
                           # ... pwn ...
tgt scenario archive       # done — hide it from the default list
```

### Pro Lab engagement (multi-target)

```fish
tgt scenario new dante           # one scenario for the lab
tgt new web01                    # first foothold
tgt --add-host web01.dante.local intranet.dante.local
                                 # ... move laterally, find dc01 ...
tgt new dc01                     # add the next target
tgt --set-dc dc01.DANTE.LOCAL    # writes a krb5 realm + adds the DC to /etc/hosts
tgt switch                       # fzf picker to jump between targets
tgt ingest <user> <pass> --zip   # bloodhound JSON lands in dc01/loot/
```

### Wrapping up

```fish
tgt scenario rm dante --purge-workspace
                  # removes /etc/hosts entries, krb5 realm, registry,
                  # and (with --purge-workspace) the workspace folder.
```

### Migrating existing notes

```fish
tgt scenario import ~/HTB/machines --prefix htb- --dry-run
                  # preview; then re-run without --dry-run.
                  # each subdir of ~/HTB/machines becomes a scenario,
                  # workspace dir = $TGT_WORKSPACE_ROOT/htb-<Name>/.
```


## Install

### Dependencies

| Package | Required for | Arch | Debian / Parrot / Kali |
|---|---|---|---|
| `fish` | the shell | `fish` | `fish` |
| `fzf` | switch picker (no-arg `tgt switch` etc.) | `fzf` | `fzf` |
| `pipx` | installing `bloodhound-python` (optional) | `python-pipx` | `pipx` |
| `gum` | nicer wizards (optional, but worth it) | `gum` | `gum` |
| `tree` | nicer `tgt workspace` visualization (optional) | `tree` | `tree` |
| `bloodhound-python` | `tgt ingest` (optional) | `pipx install bloodhound` | `pipx install bloodhound` |

Most are pre-installed on pentesting-focused distros. Arch:

```bash
sudo pacman -S fish fzf python-pipx gum tree
```

Parrot / Kali / Debian:

```bash
sudo apt install fish fzf pipx gum tree
```

For development, you also need Fisher and Fishtape:

```fish
curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
fisher install jorgebucaran/fisher jorgebucaran/fishtape
```

### Plugin install

**Use it (production):**

```fish
fisher install fuxx/pentest-fish-functions
```

**Develop on it (symlink-based, fast iteration):**

```bash
git clone <repo-url> /path/to/clone
cd /path/to/clone
make dev
```

`make dev` symlinks the repo's `functions/`, `conf.d/`, `completions/`
contents into your `~/.config/fish/`. Edits in the repo are picked up
by new fish shells immediately. `make undev` removes the symlinks.

### Verify

```fish
tgt --help
tgt <TAB>          # subcommand completion
tgt switch <TAB>   # completes from active scenario's targets
```

### Optional: prompt segment

A `[scenario:target]` indicator in your prompt — color-coded by damage
potential (red = creds loaded, yellow = host/port set, default =
scenario only).

```fish
tgt prompt install            # writes ~/.config/fish/functions/fish_right_prompt.fish
tgt prompt install --left     # left prompt instead
tgt prompt status             # show what's installed
tgt prompt uninstall          # remove the managed file
```

If you already have a custom `fish_(right_)prompt`, `tgt prompt install`
refuses to overwrite. Either add `tgt_prompt` to it by hand or rerun
with `--force` (your existing file is backed up to `<file>.tgt-bak`).


## Commands

### Scenarios

| Command | Behavior |
|---|---|
| `tgt scenario` | Interactive picker (gum + TTY) — new / switch / show / rm. Falls back to help text otherwise. |
| `tgt scenario new <name>` | Create scenario, activate it. |
| `tgt scenario list [--all\|--archived]` | Active scenarios with target count + creds/AD flags per row. `--all` adds archived (with `[archived]` tag); `--archived` shows only archived. `*` marks active. |
| `tgt scenario show [name]` | Dashboard: details + per-target table (host, creds, AD, hostname count). |
| `tgt scenario switch [--all] [name]` | Switch active scenario; no arg → fzf picker. Archived hidden by default; `--all` to surface them. |
| `tgt scenario rename [<old>] <new>` | Rename a scenario; retags every target's `/etc/hosts` lines and moves the workspace folder. |
| `tgt scenario archive [name]` / `unarchive [name]` | Hide a scenario from the default list (touches `.archived` marker), or surface it again. |
| `tgt scenario import <path> [--copy] [--dry-run] [--prefix <p>]` | Bulk-import each subdir under `<path>` as a scenario. |
| `tgt scenario rm [name] [--purge-workspace]` | Delete scenario + `/etc/hosts` entries; `--purge-workspace` also `rm -rf`s its folder. |

### Targets

| Command | Behavior |
|---|---|
| `tgt new [alias] [--no-edit]` | Create target in active scenario; drops into the wizard unless `--no-edit`. No alias → prompts. |
| `tgt switch [alias]` | Load target's saved env vars (no arg → fzf). |
| `tgt edit [alias]` | Switch (if needed) + run the wizard for a target. |
| `tgt rename [<old>] <new>` | Rename a target; retags `/etc/hosts` and moves its workspace folder. |
| `tgt list` | List targets in active scenario. |
| `tgt rm [alias] [--purge-workspace]` | Delete target + `/etc/hosts` entries. `--purge-workspace` also removes target's folder (nested layout only). |
| `tgt` (no args) | Interactive setup; auto-saves to active target. |
| `tgt --show` | Print env vars + `/etc/hosts` + krb5 + workspace tree for active target. |
| `tgt --revoke` | Clear runtime state + `/etc/hosts` for active target; deselects target (keeps scenario). |

### `/etc/hosts`

```
tgt hosts                        Multi-line editor (uses gum write or $EDITOR)
tgt --add-host <host> [host..]   Add hostnames for active target
tgt --rm-host <host> [host..]    Remove hostnames
```

All entries are tagged `# tgt:<scenario>:<target>`. The tool only
touches lines it owns — your manual `/etc/hosts` entries are safe.

When sudo is needed (writes to `/etc/hosts` and `/etc/krb5.conf` are
atomic via `sudo install`), `tgt` prints a one-line note before the
prompt explaining why.

### Active Directory

```
tgt --set-dc <DC_HOSTNAME>       Set DC + update /etc/krb5.conf realm
tgt ingest <user> <pass> [--zip] Run bloodhound-python
```

When the workspace folder for the active target exists on disk,
`tgt ingest` runs from that target's `loot/` subfolder (created on
demand) so JSON / zip output lands there. Otherwise it stays in
`$PWD`.


## Workspace folders

`tgt` can keep a directory tree per scenario (and per target) so scan
output, loot, exploits, and notes have a predictable home — useful for
reporting at the end of an engagement.

**Off by default.** Opt in with `tgt config` or:

```fish
set -Ux TGT_WORKSPACE_AUTOCREATE 1
```

### Layouts

`flat` — everything at scenario level. Best for HTB single boxes.

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

### Workspace commands

| Command | Behavior |
|---|---|
| `tgt cd [alias\|--scenario]` | `cd` to active target's / scenario's folder. |
| `tgt path [alias\|--scenario]` | Print the workspace path (no `cd`). |
| `tgt workspace` | Show settings + visualize the active scenario's tree. |
| `tgt workspace create [alias]` | Manually build the folder tree (regardless of `$TGT_WORKSPACE_AUTOCREATE`). |
| `tgt config` | Interactive editor for all workspace settings. Uses gum if installed; plain `read` + `$EDITOR` otherwise. |
| `tgt config show` | Print current settings. |
| `tgt config reset` | Erase all custom workspace settings. |

### Settings storage

`tgt config` writes to `~/.config/fish/tgt/config.fish` (or
`$TGT_HOME/config.fish`). The file is plain fish source — `set -gx VAR
value` lines — sourced by a `conf.d/` hook at shell startup. `cat` it,
edit by hand, commit to git, rsync between machines.

Env vars exported in your current shell still take precedence over the
file's values (handy for one-off overrides and tests).

### Templates

Configurable via `tgt config` or directly. Defaults shown:

```fish
set -Ux TGT_WORKSPACE_TARGET_TEMPLATE   scans/ loot/ exploits/ screenshots/ notes.md
set -Ux TGT_WORKSPACE_SCENARIO_TEMPLATE _report/findings/ _report/screenshots/ _engagement.md
```

In `flat` layout the per-target template is applied at scenario level
and the scenario template is unused. In `nested` layout, both apply
(scenario template at scenario root, target template under each target
dir). Trailing `/` on a template entry creates a directory; anything
else is `touch`-created as a file.


## State on disk

```
~/.config/fish/tgt/         (override with $TGT_HOME)
├── config.fish             user's workspace settings (managed by `tgt config`)
└── scenarios/
    └── <scenario>/
        ├── .archived       (when archived; remove to surface again)
        └── targets/
            └── <alias>.fish    set -gx TGT 10.10.11.5 ...
```

Workspace folders (when enabled) live under `$TGT_WORKSPACE_ROOT`,
default `~/Documents/pentest/`.


## Upgrading

If you have `$TGT` set from earlier use, the first `tgt` invocation
after upgrade auto-migrates the state into a `default` scenario with a
`default` target — open a new shell and `tgt list` will show it.

If you previously had workspace settings in fish universals, the
`conf.d/` hook migrates them into `~/.config/fish/tgt/config.fish` on
first startup and erases the universals so the file becomes the source
of truth.


## Tests

```bash
make test
```

Currently 543 tests across scenarios, targets, `/etc/hosts`,
`/etc/krb5.conf`, picker, prompt, migration, workspace, templating,
config file storage, completions, ask helpers, archive, import,
rename, and boundary helpers. Tests run sudoless against tmp files via
the `TGT_TEST_MODE` indirection.


## Uninstall

```bash
make undev      # if you used `make dev`
make uninstall  # if you used Fisher
```

`make undev` removes only the symlinks that point into this repo —
nothing else. To fully remove, also delete the repo directory.


## More

- [`CHANGELOG.md`](CHANGELOG.md) — reverse-chronological feature log.
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — layout, conventions, how to
  add a function, test mode primer.
- [`specs/`](specs/) — design discussions behind the larger features.
