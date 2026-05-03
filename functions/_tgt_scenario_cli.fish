# Dispatch for `tgt scenario <subcommand>`. Called from tgt.fish.
function _tgt_scenario_cli
    set -l sub $argv[1]
    set -l rest $argv[2..]

    switch "$sub"
        case "" -h --help
            echo ""
            echo "  tgt scenario — manage engagement / lab scenarios"
            echo ""
            echo "    tgt scenario new <name>      Create a new scenario, switch to it"
            echo "    tgt scenario list            List scenarios (active marked)"
            echo "    tgt scenario show [name]     Show scenario details"
            echo "    tgt scenario switch <name>   Make a scenario active"
            echo "    tgt scenario rm <name> [--purge-workspace]"
            echo "                                 Delete a scenario + its /etc/hosts entries."
            echo "                                 With --purge-workspace, also rm -rf its folder."
            echo ""
            return 0

        case new
            if test (count $rest) -lt 1
                echo "Usage: tgt scenario new <name>" >&2
                return 1
            end
            set -l name $rest[1]
            if not _tgt_scenario_validate_name $name
                echo "tgt scenario: invalid name '$name' (allowed: A-Z a-z 0-9 _ -)" >&2
                return 1
            end
            if _tgt_scenario_exists $name
                echo "tgt scenario: '$name' already exists" >&2
                return 1
            end
            _tgt_scenario_create $name
            _tgt_export TGT_SCENARIO $name
            echo "✓ scenario '$name' created and active"
            if _tgt_workspace_autocreate
                if _tgt_workspace_create $name
                    echo "  workspace: "(_tgt_workspace_dir $name)
                end
            end
            return 0

        case list
            set -l active ""
            set -q TGT_SCENARIO; and set active $TGT_SCENARIO
            set -l scenarios (_tgt_scenario_list)
            if test (count $scenarios) -eq 0
                echo "(no scenarios)"
                return 0
            end
            for s in $scenarios
                if test "$s" = "$active"
                    echo "* $s"
                else
                    echo "  $s"
                end
            end
            return 0

        case show
            set -l name $rest[1]
            if test -z "$name"
                if not set -q TGT_SCENARIO
                    echo "tgt scenario show: no active scenario (\$TGT_SCENARIO unset)" >&2
                    return 1
                end
                set name $TGT_SCENARIO
            end
            if not _tgt_scenario_exists $name
                echo "tgt scenario: '$name' does not exist" >&2
                return 1
            end
            echo "  scenario:  $name"
            if set -q TGT_SCENARIO; and test "$TGT_SCENARIO" = "$name"
                echo "  active:    yes"
            else
                echo "  active:    no"
            end
            echo "  dir:       "(_tgt_scenario_dir $name)
            return 0

        case switch
            set -l name $rest[1]
            if test -z "$name"
                set -l scenarios (_tgt_scenario_list)
                if test (count $scenarios) -eq 0
                    echo "tgt scenario switch: no scenarios registered" >&2
                    return 1
                end
                set name (_tgt_pick "scenario" $scenarios)
                test -z "$name"; and return 1
            end
            if not _tgt_scenario_exists $name
                echo "tgt scenario: '$name' does not exist" >&2
                return 1
            end
            _tgt_export TGT_SCENARIO $name
            echo "✓ active scenario: $name"
            return 0

        case rm
            argparse --name='tgt scenario rm' 'purge-workspace' -- $rest
            or return 1
            set -l name ""
            test (count $argv) -ge 1; and set name $argv[1]
            if test -z "$name"
                set -l scenarios (_tgt_scenario_list)
                if test (count $scenarios) -eq 0
                    echo "tgt scenario rm: no scenarios registered" >&2
                    return 1
                end
                set name (_tgt_pick "scenario to remove" $scenarios)
                test -z "$name"; and return 1
            end
            if not _tgt_scenario_exists $name
                echo "tgt scenario: '$name' does not exist" >&2
                return 1
            end
            _tgt_hosts_revoke_scenario $name
            _tgt_scenario_destroy $name
            if set -q TGT_SCENARIO; and test "$TGT_SCENARIO" = "$name"
                _tgt_unexport TGT_SCENARIO
            end
            echo "✓ scenario '$name' removed"
            if set -q _flag_purge_workspace
                _tgt_workspace_purge $name
            end
            return 0

        case '*'
            echo "tgt scenario: unknown subcommand '$sub'" >&2
            echo "Try: tgt scenario --help" >&2
            return 1
    end
end
