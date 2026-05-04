# Command reference

Every `tgt` subcommand and flag, organized by concern. For the
guided tour, see the [README](../README.md). For workspace settings,
layouts, and templates, see [workspace.md](workspace.md).


## Cheat sheet

```
# scenarios
tgt scenario [verb]                     no verb → interactive picker
tgt scenario new <name>                 create + activate
tgt scenario list [--all|--archived]    active by default
tgt scenario show [name]                per-scenario dashboard
tgt scenario switch [--all] [name]      no name → fzf
tgt scenario rename [<old>] <new>       retags hosts + moves workspace
tgt scenario archive   [name]           hide from default list
tgt scenario unarchive [name]           surface again
tgt scenario import <path> [--copy] [--dry-run] [--prefix <p>]
tgt scenario rm [name] [--purge-workspace]

# targets (within active scenario)
tgt new [alias] [--no-edit]             create slot + drop into wizard
tgt switch [alias]                      load saved env (no arg → fzf)
tgt edit [alias]                        switch (if needed) + wizard
tgt rename [<old>] <new>                retags hosts + moves workspace
tgt list                                targets in active scenario
tgt rm [alias] [--purge-workspace]
tgt                                     no args → interactive setup
tgt --show                              env + hosts + krb5 + workspace
tgt --revoke                            clear runtime; keep scenario

# /etc/hosts
tgt hosts                               multi-line editor
tgt --add-host <host> [host..]
tgt --rm-host  <host> [host..]

# ports (per active target)
tgt ports                               list + pick → TGT_PORT
tgt ports list
tgt ports add <file>                    nmap import (gnmap or xml)
tgt ports add <port>[/<proto>] [svc] [comment]
tgt ports rm <port>[/<proto>]
tgt ports comment <port>[/<proto>] <text>
tgt ports clear                         drop all records
tgt ports unset                         clear $TGT_PORT (keep records)

# AD
tgt --set-dc <DC_HOSTNAME>              writes krb5 realm + adds DC to hosts
tgt ingest <user> <pass> [--zip]        bloodhound-python

# workspace
tgt cd   [alias|--scenario]
tgt path [alias|--scenario]
tgt workspace                           settings + tree visualization
tgt workspace create [alias]            build folders manually
tgt config [show|reset]                 interactive settings editor

# prompt segment
tgt prompt install [--left|--right] [--force]
tgt prompt status
tgt prompt uninstall
```


## Scenarios

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


## Targets

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


## `/etc/hosts`

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


## Ports

Per-target port records, with nmap import + interactive picker.
The picked port becomes `$TGT_PORT` and shows up in the prompt as
`[scenario:target:port]`.

| Command | Behavior |
|---|---|
| `tgt ports` | List + pick → exports `TGT_PORT`. |
| `tgt ports list` | List only (no picker). |
| `tgt ports add <file>` | Import nmap output (`-oG` gnmap or `-oX` xml; auto-detect). |
| `tgt ports add <port>[/<proto>] [svc] [comment]` | Manually add one record (proto defaults to `tcp`). |
| `tgt ports rm <port>[/<proto>]` | Remove a record. |
| `tgt ports comment <port>[/<proto>] <text>` | Set/replace the comment on an existing record. |
| `tgt ports clear` | Drop all records for the active target. |
| `tgt ports unset` | Clear `$TGT_PORT` (records kept). Also happens automatically on `tgt switch` and `tgt --revoke`. |

Records live next to the target's registry file as
`<target>.ports` — tab-separated `port\tproto\tservice\tcomment`,
sorted by port. Identity is `port+proto`, so re-running an import
upserts (no duplicates) while `53/tcp` and `53/udp` coexist.

Common pentest-relevant ports get a bright cyan ★ marker so they
stand out when scanning a long list. Override the highlight set per
shell:

```fish
set -gx TGT_INTERESTING_TCP 21 22 80 443 445 3389
set -gx TGT_INTERESTING_UDP 53 88 161 500
```

The default sets lean toward AD + common service exposure; see
`functions/_tgt_ports_interesting_{tcp,udp}.fish`.


## Active Directory

```
tgt --set-dc <DC_HOSTNAME>       Set DC + update /etc/krb5.conf realm
tgt ingest <user> <pass> [--zip] Run bloodhound-python
```

When the workspace folder for the active target exists on disk,
`tgt ingest` runs from that target's `loot/` subfolder (created on
demand) so JSON / zip output lands there. Otherwise it stays in
`$PWD`.


## Workspace

| Command | Behavior |
|---|---|
| `tgt cd [alias\|--scenario]` | `cd` to active target's / scenario's folder. |
| `tgt path [alias\|--scenario]` | Print the workspace path (no `cd`). |
| `tgt workspace` | Show settings + visualize the active scenario's tree. |
| `tgt workspace create [alias]` | Manually build the folder tree (regardless of `$TGT_WORKSPACE_AUTOCREATE`). |
| `tgt config` | Interactive editor for all workspace settings. Uses gum if installed; plain `read` + `$EDITOR` otherwise. |
| `tgt config show` | Print current settings. |
| `tgt config reset` | Erase all custom workspace settings. |

Layouts, settings, and templates are documented in
[workspace.md](workspace.md).


## Prompt segment

```
tgt prompt install [--left|--right] [--force]   wire tgt_prompt into your prompt
tgt prompt status                               show what's installed
tgt prompt uninstall                            remove the managed file
```

Renders `[scenario:target[:port]]` color-coded by damage potential
(red = creds loaded, yellow = host or port set, default = scenario
only). The `:port` segment appears once you pick one via `tgt ports`.

Refuses to overwrite an existing custom `fish_(right_)prompt` unless
`--force` is passed (your file is backed up to `<file>.tgt-bak`).


## State on disk

```
~/.config/fish/tgt/         (override with $TGT_HOME)
├── config.fish             user's workspace settings (managed by `tgt config`)
└── scenarios/
    └── <scenario>/
        ├── .archived       (when archived; remove to surface again)
        └── targets/
            ├── <alias>.fish    set -gx TGT 10.10.11.5 ...
            └── <alias>.ports   port records (tab-separated)
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
