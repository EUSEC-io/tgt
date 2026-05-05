# Completions for tgt. Subcommand-aware: target-name completions
# trigger on `tgt switch/rm/cd/path`, scenario-name completions on
# `tgt scenario switch/show/rm`, and the right flags surface in each
# context.

# No file completion by default — most args are alias names.
complete -c tgt -f

set -l top_subs scenario new switch list rm edit rename cd path workspace config prompt ingest hosts ports dc

# ── Top-level subcommands ───────────────────────────────────────────
complete -c tgt -n "not __fish_seen_subcommand_from $top_subs" \
    -a scenario  -d 'Manage scenarios (engagements, lab seasons)'
complete -c tgt -n "not __fish_seen_subcommand_from $top_subs" \
    -a new       -d 'Create a target in the active scenario'
complete -c tgt -n "not __fish_seen_subcommand_from $top_subs" \
    -a switch    -d 'Load a saved target'
complete -c tgt -n "not __fish_seen_subcommand_from $top_subs" \
    -a list      -d 'List targets in the active scenario'
complete -c tgt -n "not __fish_seen_subcommand_from $top_subs" \
    -a rm        -d 'Drop a target + its /etc/hosts entries'
complete -c tgt -n "not __fish_seen_subcommand_from $top_subs" \
    -a edit      -d 'Switch (if needed) + run the wizard for a target'
complete -c tgt -n "not __fish_seen_subcommand_from $top_subs" \
    -a rename    -d 'Rename a target; retags /etc/hosts and moves the workspace folder'
complete -c tgt -n "not __fish_seen_subcommand_from $top_subs" \
    -a hosts     -d 'Multi-line editor for active target hostnames'
complete -c tgt -n "not __fish_seen_subcommand_from $top_subs" \
    -a ports     -d 'Per-target port records (list, import, pick → TGT_PORT)'
complete -c tgt -n "not __fish_seen_subcommand_from $top_subs" \
    -a dc        -d 'Per-scenario DC entries (krb5 realm definitions)'
complete -c tgt -n "not __fish_seen_subcommand_from $top_subs" \
    -a cd        -d 'cd to active target / scenario folder'
complete -c tgt -n "not __fish_seen_subcommand_from $top_subs" \
    -a path      -d 'Print workspace path (no cd)'
complete -c tgt -n "not __fish_seen_subcommand_from $top_subs" \
    -a workspace -d 'Show workspace settings + tree'
complete -c tgt -n "not __fish_seen_subcommand_from $top_subs" \
    -a config    -d 'Interactive editor for workspace settings'
complete -c tgt -n "not __fish_seen_subcommand_from $top_subs" \
    -a prompt    -d 'Install/uninstall the prompt segment'
complete -c tgt -n "not __fish_seen_subcommand_from $top_subs" \
    -a ingest    -d 'Run bloodhound-python'

# Top-level long options
complete -c tgt -n "not __fish_seen_subcommand_from $top_subs" \
    -l show     -d 'Print current target config'
complete -c tgt -n "not __fish_seen_subcommand_from $top_subs" \
    -l revoke   -d 'Clear runtime state, deselect target'
complete -c tgt -n "not __fish_seen_subcommand_from $top_subs" \
    -l add-host -d 'Add hostname for active target'
complete -c tgt -n "not __fish_seen_subcommand_from $top_subs" \
    -l rm-host  -d 'Remove hostname'
complete -c tgt -n "not __fish_seen_subcommand_from $top_subs" \
    -l set-dc   -d 'Set DC + update krb5'
complete -c tgt -n "not __fish_seen_subcommand_from $top_subs" \
    -s h -l help -d 'Show help'

# ── tgt switch / rm / edit <target> (top-level, not scenario) ───────
complete -c tgt -n '__fish_seen_subcommand_from switch; and not __fish_seen_subcommand_from scenario' \
    -a '(__tgt_complete_active_targets)' -d target
complete -c tgt -n '__fish_seen_subcommand_from rm; and not __fish_seen_subcommand_from scenario' \
    -a '(__tgt_complete_active_targets)' -d target
complete -c tgt -n '__fish_seen_subcommand_from rm; and not __fish_seen_subcommand_from scenario' \
    -l purge-workspace -d 'Also rm -rf the workspace folder'
complete -c tgt -n '__fish_seen_subcommand_from edit; and not __fish_seen_subcommand_from scenario' \
    -a '(__tgt_complete_active_targets)' -d target
complete -c tgt -n '__fish_seen_subcommand_from rename; and not __fish_seen_subcommand_from scenario' \
    -a '(__tgt_complete_active_targets)' -d target

# ── tgt new (top-level): can take --no-edit ─────────────────────────
complete -c tgt -n '__fish_seen_subcommand_from new; and not __fish_seen_subcommand_from scenario' \
    -l no-edit -d 'Create the slot but skip the wizard'

# ── tgt cd / tgt path ──────────────────────────────────────────────
complete -c tgt -n '__fish_seen_subcommand_from cd path' \
    -a '(__tgt_complete_active_targets)' -d target
complete -c tgt -n '__fish_seen_subcommand_from cd path' \
    -s s -l scenario -d 'Use scenario root, not target dir'

# ── tgt workspace <verb> ───────────────────────────────────────────
complete -c tgt -n '__fish_seen_subcommand_from workspace; and not __fish_seen_subcommand_from create' \
    -a create -d 'Build folder tree for active scenario / target'
complete -c tgt -n '__fish_seen_subcommand_from workspace; and __fish_seen_subcommand_from create' \
    -a '(__tgt_complete_active_targets)' -d target

# ── tgt scenario <verb> ────────────────────────────────────────────
set -l scenario_subs new list show switch rm rename archive unarchive import

complete -c tgt -n "__fish_seen_subcommand_from scenario; and not __fish_seen_subcommand_from $scenario_subs" \
    -a new       -d 'Create a new scenario, switch to it'
complete -c tgt -n "__fish_seen_subcommand_from scenario; and not __fish_seen_subcommand_from $scenario_subs" \
    -a list      -d 'List scenarios (active by default)'
complete -c tgt -n "__fish_seen_subcommand_from scenario; and not __fish_seen_subcommand_from $scenario_subs" \
    -a show      -d 'Show scenario details'
complete -c tgt -n "__fish_seen_subcommand_from scenario; and not __fish_seen_subcommand_from $scenario_subs" \
    -a switch    -d 'Make a scenario active'
complete -c tgt -n "__fish_seen_subcommand_from scenario; and not __fish_seen_subcommand_from $scenario_subs" \
    -a archive   -d 'Hide a scenario from the default list'
complete -c tgt -n "__fish_seen_subcommand_from scenario; and not __fish_seen_subcommand_from $scenario_subs" \
    -a unarchive -d 'Surface an archived scenario again'
complete -c tgt -n "__fish_seen_subcommand_from scenario; and not __fish_seen_subcommand_from $scenario_subs" \
    -a rename    -d 'Rename a scenario; retags /etc/hosts and moves workspace folder'
complete -c tgt -n "__fish_seen_subcommand_from scenario; and not __fish_seen_subcommand_from $scenario_subs" \
    -a rm        -d 'Delete a scenario'
complete -c tgt -n "__fish_seen_subcommand_from scenario; and not __fish_seen_subcommand_from $scenario_subs" \
    -a import    -d 'Bulk-import each subdir under a path as a scenario'

# `tgt scenario import` flags
complete -c tgt -n '__fish_seen_subcommand_from scenario; and __fish_seen_subcommand_from import' \
    -l copy      -d 'Copy instead of moving the source dirs'
complete -c tgt -n '__fish_seen_subcommand_from scenario; and __fish_seen_subcommand_from import' \
    -l dry-run   -d 'Print the plan without touching anything'
complete -c tgt -n '__fish_seen_subcommand_from scenario; and __fish_seen_subcommand_from import' \
    -l prefix    -d 'Prefix each scenario name with this string' -r
# Re-enable file completion for the path argument.
complete -c tgt -n '__fish_seen_subcommand_from scenario; and __fish_seen_subcommand_from import' -F

# `tgt scenario list` flags
complete -c tgt -n '__fish_seen_subcommand_from scenario; and __fish_seen_subcommand_from list' \
    -s a -l all      -d 'Include archived scenarios'
complete -c tgt -n '__fish_seen_subcommand_from scenario; and __fish_seen_subcommand_from list' \
    -l archived       -d 'Show only archived scenarios'

# `tgt scenario switch` flag
complete -c tgt -n '__fish_seen_subcommand_from scenario; and __fish_seen_subcommand_from switch' \
    -s a -l all      -d 'Include archived in the picker'

# tgt scenario {switch,show,rm} <name>
complete -c tgt -n '__fish_seen_subcommand_from scenario; and __fish_seen_subcommand_from switch show rm rename archive unarchive' \
    -a '(__tgt_complete_scenarios)' -d scenario
complete -c tgt -n '__fish_seen_subcommand_from scenario; and __fish_seen_subcommand_from rm' \
    -l purge-workspace -d 'Also rm -rf the workspace folder'

# ── tgt config <verb> ──────────────────────────────────────────────
set -l config_subs edit show reset

complete -c tgt -n "__fish_seen_subcommand_from config; and not __fish_seen_subcommand_from $config_subs" \
    -a edit  -d 'Open the interactive editor (default)'
complete -c tgt -n "__fish_seen_subcommand_from config; and not __fish_seen_subcommand_from $config_subs" \
    -a show  -d 'Print current settings'
complete -c tgt -n "__fish_seen_subcommand_from config; and not __fish_seen_subcommand_from $config_subs" \
    -a reset -d 'Revert all workspace settings to defaults'

# ── tgt prompt <verb> ──────────────────────────────────────────────
set -l prompt_subs install uninstall status

complete -c tgt -n "__fish_seen_subcommand_from prompt; and not __fish_seen_subcommand_from $prompt_subs" \
    -a install   -d 'Wire tgt_prompt into your fish prompt'
complete -c tgt -n "__fish_seen_subcommand_from prompt; and not __fish_seen_subcommand_from $prompt_subs" \
    -a uninstall -d 'Remove the managed prompt file(s)'
complete -c tgt -n "__fish_seen_subcommand_from prompt; and not __fish_seen_subcommand_from $prompt_subs" \
    -a status    -d 'Show what is installed'

complete -c tgt -n '__fish_seen_subcommand_from prompt; and __fish_seen_subcommand_from install' \
    -s r -l right -d 'Install into fish_right_prompt (default)'
complete -c tgt -n '__fish_seen_subcommand_from prompt; and __fish_seen_subcommand_from install' \
    -s l -l left  -d 'Install into fish_prompt'
complete -c tgt -n '__fish_seen_subcommand_from prompt; and __fish_seen_subcommand_from install' \
    -s f -l force -d 'Overwrite existing custom prompt (back up first)'

# ── tgt ports <verb> ───────────────────────────────────────────────
set -l ports_subs list add rm clear comment unset

complete -c tgt -n "__fish_seen_subcommand_from ports; and not __fish_seen_subcommand_from $ports_subs" \
    -a list    -d 'List recorded ports for the active target'
complete -c tgt -n "__fish_seen_subcommand_from ports; and not __fish_seen_subcommand_from $ports_subs" \
    -a add     -d 'Import nmap output, or add a single <port>[/<proto>]'
complete -c tgt -n "__fish_seen_subcommand_from ports; and not __fish_seen_subcommand_from $ports_subs" \
    -a rm      -d 'Remove a record by <port>[/<proto>]'
complete -c tgt -n "__fish_seen_subcommand_from ports; and not __fish_seen_subcommand_from $ports_subs" \
    -a clear   -d 'Drop all records for the active target'
complete -c tgt -n "__fish_seen_subcommand_from ports; and not __fish_seen_subcommand_from $ports_subs" \
    -a unset   -d 'Clear $TGT_PORT (records kept)'
complete -c tgt -n "__fish_seen_subcommand_from ports; and not __fish_seen_subcommand_from $ports_subs" \
    -a comment -d 'Set/replace the comment on an existing record'

# `tgt ports add` takes a file path (nmap output) or a port spec —
# re-enable file completion so paths work, but keep argument-style
# completions for the manual form via the dispatcher itself.
complete -c tgt -n '__fish_seen_subcommand_from ports; and __fish_seen_subcommand_from add' -F

# ── tgt dc <verb> ──────────────────────────────────────────────────
set -l dc_subs list show rm new switch unset

complete -c tgt -n "__fish_seen_subcommand_from dc; and not __fish_seen_subcommand_from $dc_subs" \
    -a list   -d 'List DCs in the active scenario'
complete -c tgt -n "__fish_seen_subcommand_from dc; and not __fish_seen_subcommand_from $dc_subs" \
    -a show   -d 'Show details for a DC'
complete -c tgt -n "__fish_seen_subcommand_from dc; and not __fish_seen_subcommand_from $dc_subs" \
    -a new    -d 'Create a DC entry (auto-activates)'
complete -c tgt -n "__fish_seen_subcommand_from dc; and not __fish_seen_subcommand_from $dc_subs" \
    -a switch -d 'Activate a DC (loads env, sets default_realm)'
complete -c tgt -n "__fish_seen_subcommand_from dc; and not __fish_seen_subcommand_from $dc_subs" \
    -a unset  -d 'Clear active-DC env vars + per-scenario marker'
complete -c tgt -n "__fish_seen_subcommand_from dc; and not __fish_seen_subcommand_from $dc_subs" \
    -a rm     -d 'Remove a DC entry'

# show / rm / switch: complete from active-scenario DC aliases
complete -c tgt -n '__fish_seen_subcommand_from dc; and __fish_seen_subcommand_from show rm switch' \
    -a '(__tgt_complete_active_dcs)' -d dc

# `tgt dc new` flag completions
complete -c tgt -n '__fish_seen_subcommand_from dc; and __fish_seen_subcommand_from new' \
    -l domain     -d 'AD domain (lowercase, e.g. dante.local)' -r
complete -c tgt -n '__fish_seen_subcommand_from dc; and __fish_seen_subcommand_from new' \
    -l realm      -d 'Kerberos realm (default: upper(domain))' -r
complete -c tgt -n '__fish_seen_subcommand_from dc; and __fish_seen_subcommand_from new' \
    -l kdc-host   -d 'KDC FQDN (used in krb5.conf when set)' -r
complete -c tgt -n '__fish_seen_subcommand_from dc; and __fish_seen_subcommand_from new' \
    -l kdc-ip     -d 'KDC IP (paired with --kdc-host writes /etc/hosts)' -r
complete -c tgt -n '__fish_seen_subcommand_from dc; and __fish_seen_subcommand_from new' \
    -l admin-host -d 'admin_server FQDN (optional)' -r
complete -c tgt -n '__fish_seen_subcommand_from dc; and __fish_seen_subcommand_from new' \
    -l admin-ip   -d 'admin_server IP (optional)' -r
