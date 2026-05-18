# Spec: Scenarios and Multi-Target Support

Status: draft / brainstorming
Owner: stefan

## Goal

Let `tgt` track multiple **scenarios** (HTB Pro Lab seasons like Dante,
client engagements, AD ranges), each containing many named **targets**.
Provide an interactive picker so switching between targets is fast and
doesn't require remembering names.

## Why

- HTB Pro Labs (Dante, Offshore, RastaLabs) and AD labs (Forest, Sauna)
  span many boxes — a DC, member servers, web vhosts, jumpboxes. Today
  swapping focus between them means re-running `tgt` from scratch and
  losing port / creds / hostname / DC state.
- Client engagements have the same shape: a defined scope of in-scope
  hosts that all need to be reachable for the duration of the engagement.
- A visible "which scenario, which box" indicator prevents running
  exploits against the wrong target — especially important when one
  fish tab is on a customer's prod webapp and another is on Dante.
- An engagement-level teardown (`tgt scenario rm acme`) gives a clean
  exit at the end of a project: every host entry, every krb5 realm,
  every credential gone in one step.

## Concept

Two-layer hierarchy:

```
scenario   — Dante, customer-acme, htb-forest
  └── target   — jumpbox, web01, dc01, ...
```

Plus two pointers:
- `$TGT_SCENARIO` — the active scenario.
- `$TGT_ACTIVE` — the active target within that scenario.

All existing `$TGT*` vars (TGT, TGT_PORT, TGT_USERNAME, etc.) are derived
from the active target's registry file, so every tool that uses them
keeps working unchanged.

### Storage layout

```
~/.config/fish/tgt/
  active                       # scenario=dante\ntarget=jumpbox
  scenarios/
    dante/
      meta.fish                # vpn, notes, persist_password flag
      targets/
        jumpbox.fish
        web01.fish
        dc01.fish
        fileserver.fish
    htb-forest/
      meta.fish
      targets/
        forest.fish
    customer-acme/
      meta.fish
      targets/
        webapp01.fish
        api-gateway.fish
        dc01.fish
```

Target file (sketch — current schema as of the cred/DC migration):

```fish
# ~/.config/fish/tgt/scenarios/dante/targets/web01.fish
# Only TGT + TGT_HOSTS are per-target now. Credentials and AD/DC
# info moved to per-scenario entries under creds/ and dcs/, since
# real engagements pivot multiple users across multiple targets.
_tgt_export TGT 172.16.10.20
_tgt_export TGT_HOSTS web01.dante.local intranet.dante.local
```

```fish
# ~/.config/fish/tgt/scenarios/dante/creds/admin.fish
_tgt_export TGT_CRED_USERNAME admin
_tgt_export TGT_CRED_PASSWORD hunter2
```

```fish
# ~/.config/fish/tgt/scenarios/dante/dcs/dc01.fish
_tgt_export TGT_DC_DOMAIN dante.local       # lowercase, for /d:, -d
_tgt_export TGT_DC_REALM DANTE.LOCAL        # uppercase
_tgt_export TGT_DC_HOST dc01.dante.local
_tgt_export TGT_DC_IP 10.10.10.5
```

### Interactive picker (the workflow you asked about)

`tgt` and `tgt switch` drop into an fzf picker by default — no need to
remember names. Direct form `tgt switch web01` still works for muscle
memory.

```
$ tgt switch
> pick target in 'dante':
  > jumpbox      172.16.5.5   (active)
    web01        172.16.10.20
    dc01         172.16.10.100
    fileserver   172.16.10.50
[esc to cancel, enter to switch]
```

```
$ tgt scenario switch
> pick scenario:
  > dante           4 targets    (active)
    htb-forest      1 target
    customer-acme   3 targets
```

Picker mechanics:
- Use `fzf` if installed (it's on Parrot by default).
- Fall back to a numbered `read --prompt "select [1-N]: "` menu if not.
- Tab completion on direct forms (`tgt switch <TAB>`) for users who
  prefer keyboard-only without fzf.
- Picker shows the IP next to each target so you can disambiguate when
  alias names overlap across scenarios.

### Command surface

**Scenario layer** (`tgt scenario ...` or shortened `tgt s ...`):

| Command | Behavior |
|---|---|
| `tgt scenario new <name>` | Create scenario, switch to it, prompt to add first target |
| `tgt scenario switch [name]` | Switch active scenario; no arg → fzf picker |
| `tgt scenario list` | All scenarios with target count + active marker |
| `tgt scenario rm [name]` | Wipe scenario: targets, hosts entries, krb5 realms; no arg → picker |
| `tgt scenario show` | Active scenario meta + target list |

**Target layer** (operates on `$TGT_SCENARIO`):

| Command | Behavior |
|---|---|
| `tgt new <alias>` | Interactive target setup in active scenario |
| `tgt switch [alias]` | Switch active target; no arg → fzf picker |
| `tgt list` | All targets in active scenario |
| `tgt rm [alias]` | Remove target + its hosts entries; no arg → picker |
| `tgt show [alias]` | Show active or named target |
| `tgt --revoke` | Clear `$TGT*` env vars (scenario stays active, registry preserved) |

**Existing per-target ops** (`--add-host`, `--rm-host`, `--set-dc`,
`ingest`) work unchanged — they always target the active target.

**Top-level `tgt`** (no args):
- No active scenario → prompt to create one (or pick existing if any).
- Active scenario, no active target → fzf picker over scenario's targets.
- Active scenario + active target → show summary (current `tgt --show`).

### Prompt indicator

`fish_prompt` segment shows both layers:

```
[dante:web01] $          # in scenario dante, target web01, no creds
[dante:dc01]* $          # asterisk = creds loaded
[acme:webapp01]! $       # exclamation = real-engagement scenario (red)
```

Mark a scenario as "real engagement" in `meta.fish`
(`set -gx SCENARIO_KIND real`) to enable the red color and `!` marker —
extra friction reminder when you're about to do something to a customer
box.

### `/etc/hosts` interaction

Tagged entries become two-level: `# tgt:<scenario>:<target>` (see
`etc-hosts-management.md`). Multiple scenarios coexist without colliding,
and `tgt scenario rm` is one filter pass.

```
172.16.10.20  web01.dante.local intranet.dante.local  # tgt:dante:web01
172.16.10.100 dc01.dante.local                        # tgt:dante:dc01
10.20.30.5    api.acme.test                           # tgt:customer-acme:api-gateway
```

### `krb5.conf` interaction

- Multiple realms from multiple scenarios coexist under `[realms]`.
- `default_realm` follows the active **target** on switch (so impacket
  picks the right one).
- `tgt scenario rm` removes every realm tagged for that scenario. Tag
  realms with a comment `# tgt:<scenario>` on the line above the realm
  block so we have something to grep on.

## Client engagement considerations

These build on the scenario layer rather than being separate concepts:

- **Per-scenario credential persistence**: `meta.fish` carries a
  `set -gx SCENARIO_PERSIST_PASSWORD false` flag. When false, passwords
  are loaded into the running session only via `set -gx` and never written
  to the target file. Reboot or scenario switch wipes them.
- **Per-scenario audit log**:
  `~/.local/share/tgt/scenarios/<name>/history.log` records timestamp +
  target + command for `switch`, `ingest`, `--add-host`, `--set-dc`.
  Engagement reporting gets a built-in source-of-truth.
- **Encrypted-at-rest creds**: optional `pass` integration for
  scenarios marked `kind=real`. Out of scope for v1.

## Migration from today's single-target setup

On first run after upgrade:
- If `$TGT` is set, prompt: "Save current state as scenario `default`,
  target `default`?"
- After confirmation, write registry files, set
  `$TGT_SCENARIO=default $TGT_ACTIVE=default`. No behavior change for the
  user.

## Decisions so far

- **Cross-scenario switching** (`tgt switch acme:webapp01` from inside
  Dante): defer to v2. Two-step `scenario switch` + `switch` is fine
  for now.
- **Prompt segment**: opt-out. Installed via `conf.d/` so the
  scenario:target indicator is visible by default — wrong-box safeguard
  matters more than prompt purity.

## Open questions

1. Tab completion across scenarios: should `tgt switch <TAB>` only
   complete targets in the active scenario (probably yes — matches
   muscle memory)?
2. Picker UX when fzf unavailable: numbered list is fine for ≤10
   targets. Pro Labs can have 30+. Worth bundling a simple fish-native
   filterable picker as fallback?

## Out of scope (for now)

- Sharing the registry across machines / cloud sync.
- Auto-discovery of targets from nmap output.
- GUI / web UI.
