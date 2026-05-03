# Completions for tgt. Subcommand-aware: target-name completions
# trigger on `tgt switch/rm/cd/path`, scenario-name completions on
# `tgt scenario switch/show/rm`, and the right flags surface in each
# context.

# No file completion by default — most args are alias names.
complete -c tgt -f

set -l top_subs scenario new switch list rm cd path workspace config prompt ingest

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

# ── tgt switch / rm <target> (top-level, not scenario) ──────────────
complete -c tgt -n '__fish_seen_subcommand_from switch; and not __fish_seen_subcommand_from scenario' \
    -a '(__tgt_complete_active_targets)' -d target
complete -c tgt -n '__fish_seen_subcommand_from rm; and not __fish_seen_subcommand_from scenario' \
    -a '(__tgt_complete_active_targets)' -d target
complete -c tgt -n '__fish_seen_subcommand_from rm; and not __fish_seen_subcommand_from scenario' \
    -l purge-workspace -d 'Also rm -rf the workspace folder'

# ── tgt cd / tgt path ──────────────────────────────────────────────
complete -c tgt -n '__fish_seen_subcommand_from cd path' \
    -a '(__tgt_complete_active_targets)' -d target
complete -c tgt -n '__fish_seen_subcommand_from cd path' \
    -s s -l scenario -d 'Use scenario root, not target dir'

# ── tgt scenario <verb> ────────────────────────────────────────────
set -l scenario_subs new list show switch rm

complete -c tgt -n "__fish_seen_subcommand_from scenario; and not __fish_seen_subcommand_from $scenario_subs" \
    -a new    -d 'Create a new scenario, switch to it'
complete -c tgt -n "__fish_seen_subcommand_from scenario; and not __fish_seen_subcommand_from $scenario_subs" \
    -a list   -d 'List scenarios'
complete -c tgt -n "__fish_seen_subcommand_from scenario; and not __fish_seen_subcommand_from $scenario_subs" \
    -a show   -d 'Show scenario details'
complete -c tgt -n "__fish_seen_subcommand_from scenario; and not __fish_seen_subcommand_from $scenario_subs" \
    -a switch -d 'Make a scenario active'
complete -c tgt -n "__fish_seen_subcommand_from scenario; and not __fish_seen_subcommand_from $scenario_subs" \
    -a rm     -d 'Delete a scenario'

# tgt scenario {switch,show,rm} <name>
complete -c tgt -n '__fish_seen_subcommand_from scenario; and __fish_seen_subcommand_from switch show rm' \
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
