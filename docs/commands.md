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
tgt scenario clone  [<src>] <new>       copy targets+DCs (NOT workspace)
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
tgt                                     no args → action picker (gum + TTY)
tgt show                                env + hosts + krb5 + workspace
tgt revoke                              clear runtime; keep scenario
                                        (--show / --revoke also accepted)

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

# credentials (per scenario)
tgt cred                                no verb → picker (switch)
tgt cred list [--show-passwords]        default masks pw column as pw:Y/N
tgt cred show [alias]                   detailed view — password shown
tgt cred new [alias] --username <u> [--password <p>]
                     [--domain <d>] [--notes <n>]
                                        alias defaults to --username when
                                        the username is a valid alias
tgt cred new                            (no flags) drops into wizard
tgt cred edit [alias]                   wizard with current values prefilled
tgt cred rename [<old>] <new>           rename a cred entry
tgt cred switch [alias]                 load TGT_USERNAME / TGT_PASSWORD
tgt cred unset                          clear $TGT_CRED_* + active marker
tgt cred rm [alias]

# AD / DCs (per scenario)
tgt dc                                  list DCs (no verb)
tgt dc list
tgt dc show [alias]
tgt dc new <alias> --domain <d> [--realm <R>]
                   [--kdc-host <h>] [--kdc-ip <ip>]
                   [--admin-host <h>] [--admin-ip <ip>]
tgt dc new                              (no flags) drops into wizard
tgt dc edit [alias]                     wizard with current values prefilled
tgt dc rename [<old>] <new>             rename a DC (defaults to active when only <new>)
tgt dc switch [alias]                   load DC env vars + set default_realm
tgt dc unset                            clear $TGT_DC_* + per-scenario marker
tgt dc rm [alias]
tgt ingest <user> <pass> [--zip]        bloodhound-python (uses active DC)

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
| `tgt scenario list [--all\|--archived]` | Active scenarios with target / creds / DC counts per row. `--all` adds archived (with `[archived]` tag); `--archived` shows only archived. `*` marks active. |
| `tgt scenario show [name]` | Dashboard: details + per-target table (host, hostname count) + credentials + DCs. |
| `tgt scenario switch [--all] [name]` | Switch active scenario; no arg → fzf picker. Archived hidden by default; `--all` to surface them. |
| `tgt scenario rename [<old>] <new>` | Rename a scenario; retags every target's `/etc/hosts` lines and moves the workspace folder. |
| `tgt scenario clone [<src>] <new>` | Duplicate the source scenario's registry state (targets, port records, DCs, active-DC marker) into a new scenario. Does NOT copy the workspace folder. No-arg form drops into a picker for src + prompt for new name. Doesn't activate the clone. |
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
| `tgt` (no args) | Interactive action picker (gum + TTY) — switch / new / show / edit / hosts / ports / dc / scenario / revoke. Falls back to help text in scripts/CI/no-gum environments. |
| `tgt show` (or `--show`) | Print env vars + active DC + `/etc/hosts` + krb5 + workspace tree for active target. |
| `tgt revoke` (or `--revoke`) | Clear runtime state + `/etc/hosts` for active target; deselects target (keeps scenario). |


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


## Credentials

Credential entries are per-scenario, not per-target — in practice
you collect several users (foothold, lateral movement, domain
admin) over an engagement and pivot between them, often against
the same target. `tgt cred switch` loads `TGT_USERNAME` /
`TGT_PASSWORD` and tags the prompt with `+<alias>`.

| Command | Behavior |
|---|---|
| `tgt cred` / `tgt cred list [--show-passwords]` | Bare `cred` drops into the switch picker; `list` is the read-only view (alias, username, `pw:Y/N`, domain, notes — notes truncated to 30 chars). Pass `--show-passwords` to render the actual values in the password column (useful for copy-paste; dangerous on shared screens). |
| `tgt cred show [alias]` | Detailed view (full notes + actual password). No arg → fzf picker. The password is rendered as-is — this is the "you asked for it" view. |
| `tgt cred new [alias] ...` | Create a cred entry. Auto-activates (loads env vars + writes `.active-cred`). If `[alias]` is omitted, defaults to `--username` when the username is itself a valid alias (the common ASCII case). Drops into wizard with no data flags. |
| `tgt cred edit [alias]` | Re-open the wizard for an existing entry with current values prefilled (password masked as `<KEEP>` — Enter keeps it). To clear an optional field, type `!`. |
| `tgt cred rename [<old>] <new>` | Rename a cred entry. With one arg, renames the active credential. |
| `tgt cred switch [alias]` | Activate a credential (loads `TGT_USERNAME` / `TGT_PASSWORD` / `TGT_CRED_*`). |
| `tgt cred unset` | Clear `$TGT_USERNAME` / `$TGT_PASSWORD` / `$TGT_CRED_*` + the per-scenario active marker. |
| `tgt cred rm [alias]` | Remove a cred entry. |

`tgt cred new` flags (or wizard prompts):

| Flag | Meaning |
|---|---|
| `--username <u>` | Required. Field is opaque — UTF-8 anything, Windows `DOMAIN\user`, `user@domain`, Chinese characters, all fine. Only the *alias* has to be filename-safe (`A-Z a-z 0-9 _ - .`, can't start with `.`). |
| `--password <p>` | Optional. Same field stores NT/AES hashes — paste them verbatim and tools that accept `:hash` syntax will pick it up. |
| `--domain <d>` | Optional. Free-form note (workgroup, realm, whatever's relevant). |
| `--notes <n>` | Free-form note. Truncated in `tgt cred list`; full text in `tgt cred show`. |

The active credential for each scenario is remembered across
`tgt scenario switch`, so re-entering a scenario restores whichever
cred you last had loaded. There is no cred ↔ target binding —
credentials float at the scenario level alongside DCs.

### Env vars (when a credential is active)

```
TGT_CRED_NAME=admin                # alias — surfaces in the prompt as +admin
TGT_CRED_USERNAME=Administrator    # raw field
TGT_CRED_PASSWORD=hunter2          # raw field (or NT/AES hash)
TGT_CRED_DOMAIN=DANTE              # optional, raw field
TGT_CRED_NOTES=domain admin        # optional, raw field
TGT_USERNAME=Administrator         # derived (mirror of TGT_CRED_USERNAME)
TGT_PASSWORD=hunter2               # derived (mirror of TGT_CRED_PASSWORD)
```

### Storage

```
scenarios/<scen>/
├── .active-cred                   (alias of currently-active credential)
└── creds/
    └── <alias>.fish               (raw TGT_CRED_* fields; TGT_USERNAME / TGT_PASSWORD derived at load)
```


## DCs

DC entries (per-scenario krb5 realm definitions) hold the AD info
that used to live on each target. Each entry maps to one realm
block in `/etc/krb5.conf` and, when both host and IP are stored,
one tagged line in `/etc/hosts`.

| Command | Behavior |
|---|---|
| `tgt dc` / `tgt dc list` | List all DCs in the active scenario. |
| `tgt dc show [alias]` | Detailed view; the kdc/admin lines render `host  →  ip` when both are stored. |
| `tgt dc new <alias> ...` | Create a DC entry. Auto-activates. Drops into wizard with no data flags. |
| `tgt dc edit [alias]` | Re-open the wizard for an existing entry with current values prefilled. Empty input keeps the current value. To clear an optional field, type `!` (or `<existing-value>!` if your prompt pre-filled — gum does that). When you supply or change a hostname, the wizard immediately resolves the IP and pre-fills the IP prompt with it. |
| `tgt dc rename [<old>] <new>` | Rename a DC entry. Re-emits the krb5 + `/etc/hosts` comment markers with the new alias. With one arg, renames the active DC. |
| `tgt dc switch [alias]` | Activate a DC (loads env vars, sets `default_realm`). |
| `tgt dc unset` | Clear `$TGT_DC_*` and the per-scenario active marker. |
| `tgt dc rm [alias]` | Remove a DC entry. Re-applies krb5 + hosts to clean up. |

`tgt dc new` flags (or wizard prompts):

| Flag | Meaning |
|---|---|
| `--domain <d>` | Lowercase AD domain — required (`dante.local`). |
| `--realm <R>` | Kerberos realm — defaults to `upper(domain)`. Always uppercased on save. |
| `--kdc-host <h>` | DC FQDN (used in krb5.conf when set). |
| `--kdc-ip <ip>` | DC IP. Paired with `--kdc-host` writes `<ip> <host>` to `/etc/hosts` so name resolution works without DNS. |
| `--admin-host <h>` / `--admin-ip <ip>` | Optional `admin_server` for kpasswd / password changes. |

At least one of `--kdc-host` / `--kdc-ip` is required. For
hostname-only entries krb5 uses the hostname directly (relies on
DNS); IP-only entries use the IP. With both stored, krb5 gets the
hostname and `/etc/hosts` makes resolution reliable.

**IP resolution at create/edit time:** when you supply only a
hostname, `tgt dc` resolves the IP as soon as you finish typing
the host — first by scanning manual `/etc/hosts` entries, then by
a short DNS probe. The resolved value pre-fills the IP prompt;
press Enter to accept, type a different value to override, or `!`
to clear. The chosen value is saved with a `*_SOURCE` field
(`user`, `hosts`, or `dns`) so `tgt dc show` can attribute it.
Resolution only runs at create/edit; scenario switches just use
whatever's stored.

**Lowercase in `/etc/hosts`:** hostnames are lowercased on the
way into `/etc/hosts` (DNS is case-insensitive — this prevents
duplicate-by-case rows). `/etc/krb5.conf` keeps the original case
since kerberos SPN lookups are case-sensitive.

The active DC for each scenario is remembered across
`tgt scenario switch`, so re-entering a scenario restores whichever
DC you last had loaded.

### Env vars (when a DC is active)

```
TGT_DC_NAME=dc01                  # alias — surfaces in the prompt
TGT_DC_DOMAIN=dante.local         # lowercase, for /d:, -d
TGT_DC_REALM=DANTE.LOCAL          # uppercase
TGT_DC=10.10.10.5                 # kdc value verbatim — drop-in for $TGT_DC scripts
TGT_DC_HOST=dc01.dante.local      # FQDN if known
TGT_DC_IP=10.10.10.5              # IP if known
```

### Storage

```
scenarios/<scen>/
├── .active-dc                    (alias of currently-active DC)
└── dcs/
    └── <alias>.fish              (raw fields; TGT_DC and TGT_DC_NAME derived at load)
```


## BloodHound ingest

```
tgt ingest <user> <pass> [--zip [collection] [zipname]]
```

Uses the active DC's `TGT_DC_DOMAIN` (for `-d`) and `TGT_DC_IP` (for
`-ns`). Run `tgt dc switch <alias>` first if no DC is active.

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

Renders `[scenario:target[:port][@dc][+cred]]` color-coded by damage
potential (red = credential loaded, yellow = host / port / DC set,
default = scenario only). Segments appear as you pick them: `:port`
via `tgt ports`, `@dc` via `tgt dc switch`, `+cred` via
`tgt cred switch`. Cred uses `+` so it stays unambiguous next to
`:port` and `@dc`, and survives `tgt revoke` (which only drops the
target half).

Refuses to overwrite an existing custom `fish_(right_)prompt` unless
`--force` is passed (your file is backed up to `<file>.tgt-bak`).


## State on disk

```
~/.config/fish/tgt/         (override with $TGT_HOME)
├── config.fish             user's workspace settings (managed by `tgt config`)
└── scenarios/
    └── <scenario>/
        ├── .archived       (when archived; remove to surface again)
        ├── .active-dc      (alias of currently-active DC, when set)
        ├── .active-cred    (alias of currently-active credential, when set)
        ├── targets/
        │   ├── <alias>.fish    set -gx TGT 10.10.11.5 ...
        │   └── <alias>.ports   port records (tab-separated)
        ├── dcs/
        │   └── <alias>.fish    set -gx TGT_DC_DOMAIN dante.local ...
        └── creds/
            └── <alias>.fish    set -gx TGT_CRED_USERNAME admin ...
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
