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
        echo "tgt $verb: no active scenario — run \`tgt scenario new <name>\` or \`tgt scenario switch <name>\` first" >&2
        return 1
    end
    set -l scenario $TGT_SCENARIO

    if not _tgt_scenario_exists $scenario
        echo "tgt $verb: active scenario '$scenario' is missing from the registry" >&2
        return 1
    end

    switch $verb
        case new
            if test (count $rest) -lt 1
                echo "Usage: tgt new <alias>" >&2
                return 1
            end
            set -l alias $rest[1]
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
            echo "✓ target '$alias' created in '$scenario' and activated"
            echo "  Run \`tgt\` to fill in IP / port / creds — they'll be saved automatically."
            return 0

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
            for v in TGT TGT_PORT TGT_USERNAME TGT_PASSWORD TGT_AD_DOMAIN TGT_DC TGT_HOSTS
                set -q $v; and _tgt_unexport $v
            end
            _tgt_target_load $scenario $alias
            _tgt_export TGT_ACTIVE $alias
            echo "✓ active target: $scenario:$alias"
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

        case rm
            set -l alias $rest[1]
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
            return 0

        case '*'
            echo "tgt: unknown target subcommand '$verb'" >&2
            return 1
    end
end
