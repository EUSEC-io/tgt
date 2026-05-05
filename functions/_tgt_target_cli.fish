# Dispatch for target-level commands within the active scenario:
#   tgt new <alias>      Reserve a target slot, set TGT_ACTIVE
#   tgt switch <alias>   Load the target's saved env vars
#   tgt list             List targets in the active scenario
#   tgt rm <alias>       Drop the target + its /etc/hosts entries
function _tgt_target_cli
    set -l verb $argv[1]
    set -l rest $argv[2..]

    # All target operations require an active scenario.
    if not set -q TGT_SCENARIO
        echo "tgt $verb: no active scenario — run `tgt scenario new <name>` or `tgt scenario switch <name>` first" >&2
        return 1
    end
    set -l scenario $TGT_SCENARIO

    if not _tgt_scenario_exists $scenario
        echo "tgt $verb: active scenario '$scenario' is missing from the registry" >&2
        return 1
    end

    switch $verb
        case new
            argparse --name='tgt new' 'no-edit' -- $rest
            or return 1
            set -l alias ""
            test (count $argv) -ge 1; and set alias $argv[1]
            if test -z "$alias"
                set alias (_tgt_ask_text "New target alias" "")
                if test $status -ne 0; or test -z "$alias"
                    set_color brblack; echo "  cancelled."; set_color normal
                    return 1
                end
            end
            if not _tgt_target_validate_name $alias
                echo "tgt new: invalid alias '$alias' (allowed: A-Z a-z 0-9 _ -)" >&2
                return 1
            end
            if _tgt_target_exists $scenario $alias
                echo "tgt new: target '$alias' already exists in scenario '$scenario'" >&2
                return 1
            end
            _tgt_target_save $scenario $alias
            _tgt_export TGT_ACTIVE $alias
            set_color green; echo "✓ target '$alias' created in '$scenario' and activated"; set_color normal
            if _tgt_workspace_autocreate
                if _tgt_workspace_create $scenario $alias
                    echo "  workspace: "(_tgt_workspace_dir $scenario $alias)
                end
            end
            if set -q _flag_no_edit; or set -q TGT_TEST_MODE
                echo "  Run `tgt` to fill in IP / port / creds — they'll be saved automatically."
                return 0
            end
            # Chain into the wizard. Clear stale env from the previous
            # target first so the wizard starts with empty defaults.
            for v in TGT TGT_USERNAME TGT_PASSWORD TGT_HOSTS
                set -q $v; and _tgt_unexport $v
            end
            _tgt_wizard
            return $status

        case switch
            set -l alias $rest[1]
            if test -z "$alias"
                set -l targets (_tgt_target_list $scenario)
                if test (count $targets) -eq 0
                    echo "tgt switch: no targets in scenario '$scenario'" >&2
                    return 1
                end
                set alias (_tgt_pick "target" $targets)
                test -z "$alias"; and return 1
            end
            if not _tgt_target_exists $scenario $alias
                echo "tgt switch: target '$alias' does not exist in scenario '$scenario'" >&2
                return 1
            end
            # Clear inherited target state so a target file with fewer
            # vars set doesn't carry stale values from the previous one.
            _tgt_clear_target_runtime
            _tgt_target_load $scenario $alias
            _tgt_export TGT_ACTIVE $alias
            set_color green; echo "✓ active target: $scenario:$alias"; set_color normal
            _tgt_target_state_summary
            return 0

        case list
            set -l targets (_tgt_target_list $scenario)
            if test (count $targets) -eq 0
                echo "(no targets in '$scenario')"
                return 0
            end
            set -l active ""
            set -q TGT_ACTIVE; and set active $TGT_ACTIVE
            for t in $targets
                if test "$t" = "$active"
                    echo "* $t"
                else
                    echo "  $t"
                end
            end
            return 0

        case rename
            set -l old ""
            set -l new ""
            if test (count $rest) -ge 2
                set old $rest[1]
                set new $rest[2]
            else if test (count $rest) -ge 1
                if not set -q TGT_ACTIVE
                    echo "tgt rename: no active target. Specify <old> <new>." >&2
                    return 1
                end
                set old $TGT_ACTIVE
                set new $rest[1]
            else
                echo "Usage: tgt rename [<old>] <new>" >&2
                return 1
            end
            if test "$old" = "$new"
                echo "tgt rename: '$old' = '$new', nothing to do" >&2
                return 1
            end
            if not _tgt_target_validate_name $new
                echo "tgt rename: invalid alias '$new' (allowed: A-Z a-z 0-9 _ -)" >&2
                return 1
            end
            if not _tgt_target_exists $scenario $old
                echo "tgt rename: target '$old' does not exist in scenario '$scenario'" >&2
                return 1
            end
            if _tgt_target_exists $scenario $new
                echo "tgt rename: target '$new' already exists in scenario '$scenario'" >&2
                return 1
            end
            set -l old_file (_tgt_target_file $scenario $old)
            set -l new_file (_tgt_target_file $scenario $new)
            if not command mv -- $old_file $new_file
                echo "tgt rename: failed to move registry file" >&2
                return 1
            end
            _tgt_hosts_retag $scenario $old $scenario $new
            # Move per-target workspace folder (nested layout only —
            # flat doesn't have one).
            if test (_tgt_workspace_layout) = nested
                set -l old_ws (_tgt_workspace_dir $scenario $old)
                set -l new_ws (_tgt_workspace_dir $scenario $new)
                if test -d $old_ws; and not test -e $new_ws
                    command mv -- $old_ws $new_ws
                end
            end
            if set -q TGT_ACTIVE; and test "$TGT_ACTIVE" = "$old"
                _tgt_export TGT_ACTIVE $new
            end
            set_color green; echo "✓ renamed target '$old' → '$new'"; set_color normal
            return 0

        case edit
            set -l alias ""
            test (count $rest) -ge 1; and set alias $rest[1]
            if test -n "$alias"
                if not _tgt_target_exists $scenario $alias
                    echo "tgt edit: target '$alias' does not exist in scenario '$scenario'" >&2
                    return 1
                end
                if not set -q TGT_ACTIVE; or test "$TGT_ACTIVE" != "$alias"
                    _tgt_target_cli switch $alias
                    or return $status
                end
            else if not set -q TGT_ACTIVE
                echo "tgt edit: no active target. Specify <alias> or run `tgt switch` first." >&2
                return 1
            end
            if set -q TGT_TEST_MODE
                # Don't drop into the wizard during tests.
                return 0
            end
            _tgt_wizard
            return $status

        case rm
            argparse --name='tgt rm' 'purge-workspace' -- $rest
            or return 1
            set -l alias ""
            test (count $argv) -ge 1; and set alias $argv[1]
            if test -z "$alias"
                set -l targets (_tgt_target_list $scenario)
                if test (count $targets) -eq 0
                    echo "tgt rm: no targets in scenario '$scenario'" >&2
                    return 1
                end
                set alias (_tgt_pick "target to remove" $targets)
                test -z "$alias"; and return 1
            end
            if not _tgt_target_exists $scenario $alias
                echo "tgt rm: target '$alias' does not exist in scenario '$scenario'" >&2
                return 1
            end
            _tgt_hosts_revoke $scenario $alias
            _tgt_target_destroy $scenario $alias
            if set -q TGT_ACTIVE; and test "$TGT_ACTIVE" = "$alias"
                _tgt_unexport TGT_ACTIVE
            end
            echo "✓ target '$alias' removed from '$scenario'"
            if set -q _flag_purge_workspace
                set -l layout (_tgt_workspace_layout)
                if test "$layout" = nested
                    _tgt_workspace_purge $scenario $alias
                else
                    echo "  --purge-workspace: skipped (layout is flat — no per-target folder to remove)"
                end
            end
            return 0

        case '*'
            echo "tgt: unknown target subcommand '$verb'" >&2
            return 1
    end
end
