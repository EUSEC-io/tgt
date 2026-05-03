# Render the scenario dashboard: scenario metadata + a per-target
# state table (host, creds, AD, hostnames count) read from the
# registry without loading any of it into the current shell.
function _tgt_scenario_show --argument-names name
    set -l is_active no
    set -q TGT_SCENARIO; and test "$TGT_SCENARIO" = "$name"; and set is_active yes

    echo ""
    set_color --bold cyan; echo "  scenario:  $name"; set_color normal
    echo "  active:    $is_active"
    echo "  dir:       "(_tgt_scenario_dir $name)

    set -l targets (_tgt_target_list $name)
    set -l count (count $targets)
    echo ""

    if test $count -eq 0
        set_color brblack; echo "  no targets yet — `tgt new <alias>` to add one"; set_color normal
        echo ""
        return 0
    end

    set_color cyan
    echo "  ─── targets ($count) ─────────────────────────────────"
    set_color normal
    set_color --bold
    printf '    %-13s %-24s %-6s %-4s %-5s\n' target host creds AD hosts
    set_color normal

    set -l active_alias ""
    if test "$is_active" = yes; and set -q TGT_ACTIVE
        set active_alias $TGT_ACTIVE
    end

    for target in $targets
        set -l line (_tgt_target_inspect $name $target)
        set -l fields (string split \t -- $line)
        # alias, host_port, creds, ad, hosts_count
        set -l marker "  "
        set -l is_active 0
        if test "$target" = "$active_alias"
            set marker " *"
            set is_active 1
        end

        # Render. Fields colored individually:
        #   creds Y → red (damage potential)
        #   AD    Y → yellow
        #   hosts 0 → dim
        printf '  %s ' $marker
        test $is_active -eq 1; and set_color --bold green
        printf '%-13s' $fields[1]
        set_color normal
        printf ' %-24s ' $fields[2]
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
        if test "$fields[5]" -gt 0
            printf ' %-5s' $fields[5]
        else
            set_color brblack; printf ' %-5s' 0; set_color normal
        end
        echo ""
    end
    echo ""
end
