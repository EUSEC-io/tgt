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
            argparse --name='tgt scenario list' a/all archived -- $rest
            or return 1
            if set -q _flag_all; and set -q _flag_archived
                echo "tgt scenario list: --all and --archived are mutually exclusive" >&2
                return 1
            end
            set -l mode active
            set -q _flag_all; and set mode all
            set -q _flag_archived; and set mode archived

            set -l active ""
            set -q TGT_SCENARIO; and set active $TGT_SCENARIO
            set -l all_scenarios (_tgt_scenario_list)
            set -l filtered
            set -l archived_count 0
            for s in $all_scenarios
                if _tgt_scenario_archived $s
                    set archived_count (math $archived_count + 1)
                    test "$mode" = active; and continue
                else
                    test "$mode" = archived; and continue
                end
                set -a filtered $s
            end

            if test (count $filtered) -eq 0
                if test "$mode" = active; and test $archived_count -gt 0
                    echo "(no active scenarios; $archived_count archived — use --all or --archived to see them)"
                else if test "$mode" = archived
                    echo "(no archived scenarios)"
                else
                    echo "(no scenarios)"
                end
                return 0
            end

            set_color --bold
            printf '  %-15s %-8s %-6s %-4s\n' scenario targets creds AD
            set_color normal
            for s in $filtered
                set -l line (_tgt_scenario_inspect $s)
                set -l fields (string split \t -- $line)
                set -l marker "  "
                set -l is_active 0
                set -l is_archived 0
                if test "$s" = "$active"
                    set marker "* "
                    set is_active 1
                end
                _tgt_scenario_archived $s; and set is_archived 1
                printf '%s' $marker
                test $is_active -eq 1; and set_color --bold green
                test $is_archived -eq 1; and set_color brblack
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
                test $is_archived -eq 1; and set_color brblack; and printf '  [archived]'; and set_color normal
                echo ""
            end

            if test "$mode" = active; and test $archived_count -gt 0
                echo ""
                set_color brblack
                echo "  ($archived_count archived hidden — use --all to see them)"
                set_color normal
            end
            return 0

        case archive
            set -l name ""
            test (count $rest) -ge 1; and set name $rest[1]
            if test -z "$name"
                set -q TGT_SCENARIO; or begin
                    echo "tgt scenario archive: no active scenario. Specify <name>." >&2
                    return 1
                end
                set name $TGT_SCENARIO
            end
            if not _tgt_scenario_exists $name
                echo "tgt scenario archive: '$name' does not exist" >&2
                return 1
            end
            if _tgt_scenario_archived $name
                echo "tgt scenario archive: '$name' is already archived" >&2
                return 0
            end
            touch -- (_tgt_scenario_dir $name)/.archived
            set_color green; echo "✓ archived '$name' (hidden from `tgt scenario list` by default)"; set_color normal
            return 0

        case unarchive
            set -l name ""
            test (count $rest) -ge 1; and set name $rest[1]
            if test -z "$name"
                set -q TGT_SCENARIO; or begin
                    echo "tgt scenario unarchive: no active scenario. Specify <name>." >&2
                    return 1
                end
                set name $TGT_SCENARIO
            end
            if not _tgt_scenario_exists $name
                echo "tgt scenario unarchive: '$name' does not exist" >&2
                return 1
            end
            if not _tgt_scenario_archived $name
                echo "tgt scenario unarchive: '$name' is not archived" >&2
                return 0
            end
            command rm -f -- (_tgt_scenario_dir $name)/.archived
            set_color green; echo "✓ unarchived '$name'"; set_color normal
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
            argparse --name='tgt scenario switch' a/all -- $rest
            or return 1
            set -l name ""
            test (count $argv) -ge 1; and set name $argv[1]
            if test -z "$name"
                set -l all_scenarios (_tgt_scenario_list)
                set -l scenarios
                if set -q _flag_all
                    set scenarios $all_scenarios
                else
                    for s in $all_scenarios
                        _tgt_scenario_archived $s; or set -a scenarios $s
                    end
                end
                if test (count $scenarios) -eq 0
                    if test (count $all_scenarios) -eq 0
                        echo "tgt scenario switch: no scenarios registered" >&2
                    else
                        echo "tgt scenario switch: no active scenarios (use --all to include archived)" >&2
                    end
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
            _tgt_scenario_archived $name; and begin
                set_color brblack
                echo "  (note: '$name' is archived; `tgt scenario unarchive` to surface it in default list)"
                set_color normal
            end
            return 0

        case rename
            set -l old ""
            set -l new ""
            if test (count $rest) -ge 2
                set old $rest[1]
                set new $rest[2]
            else if test (count $rest) -ge 1
                if not set -q TGT_SCENARIO
                    echo "tgt scenario rename: no active scenario. Specify <old> <new>." >&2
                    return 1
                end
                set old $TGT_SCENARIO
                set new $rest[1]
            else
                echo "Usage: tgt scenario rename [<old>] <new>" >&2
                return 1
            end
            if test "$old" = "$new"
                echo "tgt scenario rename: same name, nothing to do" >&2
                return 1
            end
            if not _tgt_scenario_validate_name $new
                echo "tgt scenario rename: invalid name '$new' (allowed: A-Z a-z 0-9 _ -)" >&2
                return 1
            end
            if not _tgt_scenario_exists $old
                echo "tgt scenario rename: '$old' does not exist" >&2
                return 1
            end
            if _tgt_scenario_exists $new
                echo "tgt scenario rename: '$new' already exists" >&2
                return 1
            end
            set -l old_dir (_tgt_scenario_dir $old)
            set -l new_dir (_tgt_scenario_dir $new)
            if not command mv -- $old_dir $new_dir
                echo "tgt scenario rename: failed to move scenario dir" >&2
                return 1
            end
            # Retag /etc/hosts entries for every target in the scenario.
            for target in (_tgt_target_list $new)
                _tgt_hosts_retag $old $target $new $target
            end
            # Move the scenario's workspace folder if present.
            set -l old_ws (_tgt_workspace_dir $old)
            set -l new_ws (_tgt_workspace_dir $new)
            if test -d $old_ws; and not test -e $new_ws
                command mv -- $old_ws $new_ws
            end
            if set -q TGT_SCENARIO; and test "$TGT_SCENARIO" = "$old"
                _tgt_export TGT_SCENARIO $new
            end
            set_color green; echo "✓ renamed scenario '$old' → '$new'"; set_color normal
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
