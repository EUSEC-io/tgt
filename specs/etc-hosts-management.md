# Spec: Safer `/etc/hosts` Management

Status: draft
Owner: stefan

## Problem

Today `tgt` mutates `/etc/hosts` with line-pattern sed commands that don't
distinguish "lines `tgt` put there" from "lines the user put there".

### Concrete bug

In `tgt --add-host` and `tgt --rm-host`:

```fish
sudo sed -i -E '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\s*$/d' /etc/hosts
```

This deletes **every** line in `/etc/hosts` that contains only a bare IPv4
address — anywhere in the file, regardless of whose target it belongs to.
Today it usually does the right thing because there's only one tgt-managed
entry. Once multi-target lands (see `multi-target.md`), one target's
hostname-removal sweep will silently break another target's entry.

### Other smells

- `sudo sed -i "s/^$escaped\s.*/$TGT $existing_hosts/"` — `$TGT` and
  `$existing_hosts` are interpolated into a sed replacement without escaping
  `/` or `&`. A typo in the read prompt corrupts the file.
- `sudo sh -c "echo '$TGT $input_hosts' >> /etc/hosts"` — single-quote
  injection from a fat-fingered prompt input. Not a security boundary
  (it's your machine, your input), but it can wedge `/etc/hosts`.
- All matching reads use `grep`, contrary to the project rule of preferring
  `string` builtins.

## Proposal: tagged lines, scenario-scoped

Every line `tgt` writes to `/etc/hosts` ends with a marker comment naming
the **scenario** and **target** that own it (see `multi-target.md`).

```
172.16.10.20  web01.dante.local intranet.dante.local  # tgt:dante:web01
172.16.10.100 dc01.dante.local                        # tgt:dante:dc01
10.10.11.5    forest.htb                              # tgt:htb-forest:forest
10.20.30.5    api.acme.test                           # tgt:customer-acme:api-gateway
```

The tag is the **only** identifier `tgt` uses. We never match by IP, never
match by hostname, never match by anchored line shape. This means:

- Two targets (in the same or different scenarios) can share an IP
  without interfering. Common in NAT'd client labs.
- The user's own `/etc/hosts` entries (untagged) are invisible to `tgt`
  and cannot be deleted.
- Removing one target: filter out lines tagged `# tgt:<scenario>:<alias>`.
- Removing a whole scenario: filter out lines tagged `# tgt:<scenario>:*`
  in one pass — clean engagement teardown.

### Read path (pure `string`)

```fish
set -l lines (cat /etc/hosts)
# all lines for target web01 in scenario dante
set -l mine (string match -r ".* # tgt:dante:web01\$" -- $lines)
# all lines for scenario dante (any target)
set -l scenario_lines (string match -r ".* # tgt:dante:[A-Za-z0-9_-]+\$" -- $lines)
# everything not managed by tgt
set -l others (string match -rv " # tgt:[A-Za-z0-9_-]+:[A-Za-z0-9_-]+\$" -- $lines)
```

No `grep`, no anchored sed pattern.

### Write path

A single helper rewrites `/etc/hosts` atomically:

```fish
function _tgt_hosts_write --argument-names content
    set -l tmp (mktemp)
    printf '%s\n' $content > $tmp
    sudo install -m 644 -o root -g root $tmp /etc/hosts
    rm -f $tmp
end
```

Why `install` instead of `tee >>` or `sed -i`:
- Atomic replace (no half-written state if interrupted).
- Preserves mode/owner explicitly.
- No shell-quoted command injection surface.

### Operations

- **Add host(s) for scenario S target T, IP X**: read all lines, find the
  one tagged `# tgt:S:T`, append new hostnames (skip via `contains`),
  rewrite. If no line exists yet, create one.
- **Remove host(s) for scenario S target T**: same, but filter out the
  names. If the resulting line has no hostnames left, drop the line
  entirely (no bare-IP residue, no global sweep needed).
- **Revoke target T in scenario S** (`tgt rm T`): drop every line matching
  `# tgt:S:T$`.
- **Revoke whole scenario S** (`tgt scenario rm S`): drop every line
  matching `# tgt:S:[A-Za-z0-9_-]+$`. One-pass engagement teardown.
- **Revoke all** (`tgt --revoke --all`): drop every line matching
  `# tgt:[A-Za-z0-9_-]+:[A-Za-z0-9_-]+$`.

### Migration

On first run after this change:
- If `$TGT` is set and a matching untagged line exists in `/etc/hosts`, ask
  once: "tag this entry as `tgt:default:default`?" (matches the
  scenario/target migration default in `multi-target.md`).
- After that, untagged entries are user-owned forever.

## Trade-offs

- The tag is visible to anything else that reads `/etc/hosts`. Cosmetic
  cost. Tools that parse `/etc/hosts` ignore comments correctly.
- `string match -r` per-operation reads the whole file. `/etc/hosts` is
  tiny, this is irrelevant.
- We still need `sudo` for the write step. Unavoidable; that's where the
  privilege boundary lives.

## Smaller alternative (if multi-target gets deferred)

If you want to fix only the bug without committing to the redesign:

Replace the global bare-IP sweep with a `$TGT`-anchored check: only delete
the line if it starts with `^$escaped\s*$` after the hostname removal. This
limits collateral damage to the active target's own line, which is what the
code intended in the first place. Two-line change, no new file format.

Recommend doing this **and** the tagged-line redesign — bug fix today, full
redesign with multi-target.

## Open questions

1. Tag syntax: `# tgt:<scenario>:<target>` vs. `# managed-by:tgt
   scenario=S target=T`. First is shorter, second is more
   self-documenting. Leaning toward the short form.
2. Should `tgt --show` print only the active target's hosts, all hosts
   for the active scenario, or every tgt-managed host grouped by
   scenario? Probably show active target by default, scenario via
   `tgt scenario show`, all via `tgt --show --all`.
3. Allowed characters in scenario/target names: stick to
   `[A-Za-z0-9_-]` so the regex stays simple and shell-safe. Reject
   anything else at `tgt scenario new` / `tgt new` time.
