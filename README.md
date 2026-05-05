# pentest-fish-functions

A [fish shell](https://fishshell.com/) plugin for pentesting workflows.
Tested on Arch, Parrot OS, and Kali.


## What it does

`tgt` is the flagship command. It remembers everything about the box
you're working on (IP, creds, AD domain, hostnames, ports) and keeps
`/etc/hosts`, `/etc/krb5.conf`, and an optional per-engagement folder
tree in sync. Targets organize into **scenarios**, so a Pro Lab season
or a client engagement is one namespace; switching targets pulls up
every detail and updates the right system files.

A few flagged extras: a colored `[scenario:target:port@dc]` prompt segment,
fzf pickers, archive support to hide finished engagements, BloodHound
ingest with auto-routed loot folders, nmap port-record import, and a
gum-based config wizard when [`gum`](https://github.com/charmbracelet/gum)
is installed.


## Concepts

| Term | What it means |
|---|---|
| **scenario** | An engagement, HTB Pro Lab season, or client. Holds many targets. |
| **target** | One box / host. IP, creds, AD, hostnames, ports. |
| **workspace** | Optional per-scenario / per-target directory tree (scans, loot, exploits, notes) for tidy reporting. |


## At a glance

![dashboard](assets/dashboard.svg)

`tgt scenario show` gives you a per-scenario dashboard: every target's
host, credentials-loaded flag (red = damage potential), AD flag
(yellow), and hostname count. Active target is starred and bolded
green. The data is read straight from the registry — no shell env
pollution to inspect it.


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

```fish
tgt prompt install            # writes ~/.config/fish/functions/fish_right_prompt.fish
tgt prompt install --left     # left prompt instead
```

Renders `[scenario:target[:port][@dc]]` color-coded by damage potential.
Details in [docs/commands.md](docs/commands.md#prompt-segment).


## Best practices

### Working a single HTB box

```fish
tgt scenario new lame      # one scenario per box
tgt new box                # creates target slot + drops into the wizard
                           #   (fill in IP, hostname, creds when found, AD if present)
tgt --add-host lame.htb    # extra hostname, tagged so removal is precise
tgt ports add scans/sv_scan.gnmap     # import nmap output
tgt ports                  # pick the port to focus on → $TGT_PORT
tgt cd                     # cd to the workspace folder for scans / loot
                           # ... pwn ...
tgt scenario archive       # done — hide it from the default list
```

### Multi-target engagement (Pro Lab, client)

```fish
tgt scenario new dante                       # one scenario for the lab
tgt new web01                                # first foothold
tgt --add-host web01.dante.local intranet.dante.local
                                             # ... move laterally, find a DC ...
tgt dc new dc01 \
    --domain dante.local \
    --kdc-host dc01.dante.local --kdc-ip 10.10.10.5
                                             # writes the realm to krb5.conf,
                                             # the host→ip pair to /etc/hosts,
                                             # and exports TGT_DC_*. Auto-active.
tgt new dc01-host                            # the DC as a target (for SMB, etc.)
tgt switch                                   # fzf picker to jump between targets
tgt ingest <user> <pass> --zip               # bloodhound JSON lands in dc01-host/loot/
```

A scenario can hold many DCs (`tgt dc new` again, or run with no
flags for the wizard). `tgt dc switch <alias>` flips which one's
active. The prompt picks up the change as `[scenario:target@dc-alias]`.

### Wrapping up

```fish
tgt scenario rm dante --purge-workspace
                  # removes /etc/hosts entries, krb5 realm, registry,
                  # and (with --purge-workspace) the workspace folder.
```

For solo boxes you finished but want to keep the notes, archive
instead of remove:

```fish
tgt scenario archive lame    # hidden from default list, still on disk
tgt scenario unarchive lame  # bring it back
```


## Demo gallery

### Per-target ports with nmap import

![ports](assets/ports.svg)

`tgt ports add <file>` imports `nmap -oG` (gnmap) or `-oX` (xml)
output. Common pentest ports get a bright cyan ★ marker so they jump
out. Comments are free-form per record. The picker exports `TGT_PORT`
for use in subsequent tools.

### The prompt always tells you where you stand

![prompt](assets/prompt.svg)

`tgt_prompt` is color-coded by damage potential — neutral for
scenario-only, yellow once a host or port is loaded (recon), red as
soon as credentials are present.

### Hide finished engagements

![archive](assets/archive.svg)

`tgt scenario archive` keeps the data on disk and switchable by name
but hides it from the default list. `--all` to surface them, or
`--archived` for the archived-only view.

### Bulk-import existing notes

![import](assets/import.svg)

`tgt scenario import` walks each subdirectory under a path and turns
it into a scenario. `--prefix htb-` to namespace, `--copy` to keep
the source intact, `--dry-run` to preview.

### Jumping between targets

![tgt switch](assets/switch.gif)

No-arg `tgt switch` opens an fzf picker over the active scenario's
targets. Type to filter, arrow + Enter to select.

### Clean up between targets

![revoke](assets/revoke.svg)

`tgt --revoke` clears the active target's runtime state — env vars,
`/etc/hosts` entries, krb5 realm, `TGT_PORT` — but keeps the scenario
active. The persisted target file on disk is untouched, so
`tgt switch <name>` loads it back instantly.

### More

[![rename](assets/rename.svg)](assets/rename.svg) ·
[![workspace](assets/workspace.svg)](assets/workspace.svg) ·
[![tgt scenario picker](assets/scenario-picker.gif)](assets/scenario-picker.gif) ·
[![tgt config](assets/config.gif)](assets/config.gif)


## Documentation

- **[docs/commands.md](docs/commands.md)** — full command reference
  (cheat sheet + every subcommand and flag, organized by concern,
  plus state-on-disk and upgrading notes).
- **[docs/workspace.md](docs/workspace.md)** — workspace deep-dive:
  layouts, settings storage, templates.
- **[CHANGELOG.md](CHANGELOG.md)** — reverse-chronological feature log.
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — layout, conventions, how to
  add a function, test mode primer, demo recording.
- **[specs/](specs/)** — design discussions behind the larger features.


## Tests

```bash
make test
```

Tests run sudoless against tmp files via the `TGT_TEST_MODE`
indirection.


## Uninstall

```bash
make undev      # if you used `make dev`
make uninstall  # if you used Fisher
```

`make undev` removes only the symlinks that point into this repo —
nothing else. To fully remove, also delete the repo directory.
