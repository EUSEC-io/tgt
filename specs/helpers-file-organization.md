# Spec: Helper Function Layout

Status: proposal
Owner: stefan

## Question

`tgt.fish` defines four functions: `tgt`, `_tgt_run_bloodhound`,
`_tgt_update_krb5`, `_tgt_clean_krb5`. The project convention is **one
function per file, filename matches function name**. What do we do with
the helpers?

## Options

### A. Split into per-file autoloaded helpers (recommended)

```
functions/
  tgt.fish
  _tgt_run_bloodhound.fish
  _tgt_update_krb5.fish
  _tgt_clean_krb5.fish
```

Pros:
- Matches the project rule literally.
- Fish autoloads each on first use — no source-time cost.
- Underscore prefix is the conventional "private, don't call directly"
  marker. Anyone reading `functions/` sees the grouping at a glance.
- Each helper gets its own `test/test_<name>.fish` per the testing rule.

Cons:
- Four files instead of one. Slight discovery overhead (`grep -r tgt
  functions/` still finds them all).

### B. Keep helpers inline in `tgt.fish`

Pros:
- Tightly coupled code lives together. Easy to read top-to-bottom.

Cons:
- Violates the project convention.
- Helpers can't be unit-tested in isolation (Fishtape loads functions by
  filename).
- Other functions can't reuse them, even though `_tgt_update_krb5` is
  obviously generic ("write a realm to krb5.conf") and might be wanted by
  other AD-related functions later.

### C. Inline as nested `function ... end` inside `tgt`

Doesn't work the way you'd want in fish — nested functions persist after
the outer call returns, polluting the global namespace anyway. Skip.

## Recommendation

**Option A.** Cost is low (one-time split), it's what the convention asks
for, and it sets up `_tgt_update_krb5` to be reused if other AD tooling
gets added later. The underscore prefix already conveys "internal helper,
don't call directly" so the convention isn't fighting the design intent.

## Mechanics

When splitting, each helper gets:

```fish
# <description>
function _tgt_<name>
    ...
end
```

Per the project rule "Every function starts with a `# description`
comment". For `tgt` itself, fish's `--description` flag already serves this
purpose — keep it.

## Privacy: keeping helpers out of completion / listings

Concern: with helpers as separate autoloaded files, won't they pollute
tab completion and `functions` listings?

Empirically verified on fish 4.0.2: **no**. The `_` prefix is treated as
"hidden" by fish itself.

| Surface | Behavior with `_tgt_*` |
|---|---|
| `<TAB>` at empty prompt or partial command | Filtered out unless you start typing `_` |
| `complete -C ""` (full command list) | Filtered out |
| `functions` (no args) | Hidden (need `functions --all` to see) |
| `functions --names` | Hidden |
| Direct call `_tgt_clean_krb5 ...` | Works — convention, not enforcement |
| `which _tgt_clean_krb5` | Works — same |

This matches Python's `_private` model: discouraged from view, still
callable if you know the name. Fish enforces visibility, not callability.
Trying to enforce uncallability (runtime guards checking a magic flag,
unset/redefine tricks) adds noise without real protection. Skip.

What this means for the public API:

- The only public function is `tgt` itself.
- Every helper is `_tgt_<verb>[_<noun>]` and gets the convention's
  hidden-by-default behavior.
- `tgt <TAB>` is fully under our control via `completions/tgt.fish` — we
  list only public subcommands and flags there. Internal verbs like
  `_tgt_hosts_write` never appear because we don't put them in the
  completion file.

### Required: `completions/tgt.fish`

A completion file goes alongside this work. Sketch:

```fish
# completions/tgt.fish

# Top-level subcommands
complete -c tgt -n __fish_use_subcommand -a scenario -d 'Manage scenarios'
complete -c tgt -n __fish_use_subcommand -a new      -d 'Create a target in active scenario'
complete -c tgt -n __fish_use_subcommand -a switch   -d 'Switch active target'
complete -c tgt -n __fish_use_subcommand -a list     -d 'List targets in active scenario'
complete -c tgt -n __fish_use_subcommand -a rm       -d 'Remove target'
complete -c tgt -n __fish_use_subcommand -a show     -d 'Show target details'
complete -c tgt -n __fish_use_subcommand -a ingest   -d 'Run BloodHound ingest'

# Flags
complete -c tgt -l help     -s h -d 'Show help'
complete -c tgt -l show     -d 'Show current state'
complete -c tgt -l revoke   -d 'Clear active target env'
complete -c tgt -l add-host -d 'Add hostname(s) to active target'
complete -c tgt -l rm-host  -d 'Remove hostname(s) from active target'
complete -c tgt -l set-dc   -d 'Set domain controller'

# Dynamic: target alias completion in active scenario
function __tgt_targets
    set -q TGT_SCENARIO; or return
    set -q TGT_HOME;     or set -l TGT_HOME ~/.config/fish/tgt
    set -l dir $TGT_HOME/scenarios/$TGT_SCENARIO/targets
    test -d $dir; or return
    string replace -r '\.fish$' '' (ls $dir)
end

complete -c tgt -n '__fish_seen_subcommand_from switch rm show' -a '(__tgt_targets)'

# Scenario name completion
function __tgt_scenarios
    set -q TGT_HOME; or set -l TGT_HOME ~/.config/fish/tgt
    test -d $TGT_HOME/scenarios; or return
    ls $TGT_HOME/scenarios
end

complete -c tgt -n '__fish_seen_subcommand_from scenario' \
    -a 'new switch list rm show'
complete -c tgt -n '__fish_seen_subcommand_from scenario; \
    and __fish_seen_subcommand_from switch rm show' \
    -a '(__tgt_scenarios)'
```

Note `__tgt_*` (double underscore) for completion-only helpers — fish's
own convention for completion-internal functions, even more hidden.

## Out of scope

Whether `_tgt_update_krb5` and `_tgt_clean_krb5` should merge into a single
`_tgt_krb5` with subcommands. Probably not worth it; keep the surface flat
until a third krb5 helper appears.
