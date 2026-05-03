# Dispatch for `tgt scenario <subcommand>`. Called from tgt.fish.
function _tgt_scenario_cli
    set -l sub $argv[1]
    set -l rest $argv[2..]

    switch "$sub"
        case ""
            # Interactive menu when gum is available + we have a TTY;
            # help text otherwise (scripts, CI, tests).
            if command -q gum; and not set -q TGT_TEST_MODE; and isatty stdin
                _tgt_scenario_menu
                return $status
            end
            _tgt_scenario_help
            return 0

        case -h --help
            _tgt_scenario_help
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
            set_color --bold
            printf '  %-15s %-8s %-6s %-4s\n' scenario targets creds AD
            set_color normal
            for s in $scenarios
                set -l line (_tgt_scenario_inspect $s)
                set -l fields (string split \t -- $line)
                # fields: name, count, creds, ad
                set -l marker "  "
                set -l is_active 0
                if test "$s" = "$active"
                    set marker "* "
                    set is_active 1
                end
                printf '%s' $marker
                test $is_active -eq 1; and set_color --bold green
                printf '%-15s' $fields[1]
                set_color normal
                printf ' %-8d ' $fields[2]
                if test "$fields[3]" = Y
                    set_color red; printf '%-6s' Y; set_color normal
                else
                    set_color brblack; printf '%-6s' N; set_color normal
                end
                if test "$fields[4]" = Y
                    set_color yellow; printf '%-4s' Y; set_color normal
                else
                    set_color brblack; printf '%-4s' N; set_color normal
                end
                echo ""
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
            _tgt_scenario_show $name
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
            # Collect all unique realms used by this scenario's targets
            # before destroying the registry, so we can clean krb5.conf
            # afterwards (only if no other scenario still uses them).
            set -l realms
            for target in (_tgt_target_list $name)
                set -l r (_tgt_target_ad_realm $name $target)
                test -z "$r"; and continue
                contains -- $r $realms; or set -a realms $r
            end
            _tgt_hosts_revoke_scenario $name
            _tgt_scenario_destroy $name
            if set -q TGT_SCENARIO; and test "$TGT_SCENARIO" = "$name"
                _tgt_unexport TGT_SCENARIO
            end
            for r in $realms
                if not _tgt_realm_in_use $r
                    _tgt_clean_krb5 $r
                    echo "  ✓ removed $r from /etc/krb5.conf"
                end
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
