# Render the scenario dashboard: scenario metadata + a per-target
# state table (host, creds, hostnames count) and a DC list, all
# read from the registry without loading any of it into the
# current shell.
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
    printf '    %-13s %-24s %-6s %-5s\n' target host creds hosts
    set_color normal

    set -l active_alias ""
    if test "$is_active" = yes; and set -q TGT_ACTIVE
        set active_alias $TGT_ACTIVE
    end

    for target in $targets
        set -l line (_tgt_target_inspect $name $target)
        set -l fields (string split \t -- $line)
        # alias, host, creds, hosts_count
        set -l marker "  "
        set -l is_active 0
        if test "$target" = "$active_alias"
            set marker " *"
            set is_active 1
        end

        # Render. Fields colored individually:
        #   creds Y → red (damage potential)
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
        if test "$fields[4]" -gt 0
            printf ' %-5s' $fields[4]
        else
            set_color brblack; printf ' %-5s' 0; set_color normal
        end
        echo ""
    end

    # ── DC entries (per-scenario) ──
    set -l dcs (_tgt_dc_list $name)
    set -l dc_count (count $dcs)
    if test $dc_count -gt 0
        set -l active_dc (_tgt_dc_get_active $name 2>/dev/null)
        echo ""
        set_color cyan
        echo "  ─── DCs ($dc_count) ─────────────────────────────────────"
        set_color normal
        for dc in $dcs
            set -l line (_tgt_dc_inspect $name $dc)
            set -l f (string split \t -- $line)
            # alias, domain, realm, kdc, admin
            set -l marker "  "
            test "$dc" = "$active_dc"; and set marker " *"
            printf '  %s ' $marker
            test "$dc" = "$active_dc"; and set_color --bold green
            printf '%-13s' $f[1]
            set_color normal
            printf ' %-20s %-20s %-24s %s\n' $f[2] $f[3] $f[4] $f[5]
        end
    end
    echo ""
end
