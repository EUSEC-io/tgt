# Render the scenario dashboard: scenario metadata + a per-target
# state table, plus the scenario's DC and credential lists. All
# read from the registry without polluting the current shell.
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
    else
        set_color cyan
        echo "  ─── targets ($count) ─────────────────────────────────"
        set_color normal
        set_color --bold
        printf '    %-13s %-24s %-5s\n' target host hosts
        set_color normal

        set -l active_alias ""
        if test "$is_active" = yes; and set -q TGT_ACTIVE
            set active_alias $TGT_ACTIVE
        end

        for target in $targets
            set -l line (_tgt_target_inspect $name $target)
            set -l fields (string split \t -- $line)
            # alias, host, hosts_count
            set -l marker "  "
            set -l is_active_target 0
            if test "$target" = "$active_alias"
                set marker " *"
                set is_active_target 1
            end

            printf '  %s ' $marker
            test $is_active_target -eq 1; and set_color --bold green
            printf '%-13s' $fields[1]
            set_color normal
            printf ' %-24s ' $fields[2]
            if test "$fields[3]" -gt 0
                printf '%-5s' $fields[3]
            else
                set_color brblack; printf '%-5s' 0; set_color normal
            end
            echo ""
        end
    end

    # ── Credentials (per-scenario) ──
    set -l creds (_tgt_cred_list $name)
    set -l cred_count (count $creds)
    if test $cred_count -gt 0
        set -l active_cred (_tgt_cred_get_active $name 2>/dev/null)
        echo ""
        set_color cyan
        echo "  ─── credentials ($cred_count) ────────────────────────"
        set_color normal
        for c in $creds
            set -l line (_tgt_cred_inspect $name $c)
            set -l f (string split \t -- $line)
            # alias, username, has_password, domain, notes
            set -l marker "  "
            test "$c" = "$active_cred"; and set marker " *"
            printf '  %s ' $marker
            test "$c" = "$active_cred"; and set_color --bold green
            printf '%-13s' $f[1]
            set_color normal
            printf ' %-20s ' $f[2]
            if test "$f[3]" = Y
                set_color red; printf 'pw:Y '; set_color normal
            else
                set_color brblack; printf 'pw:N '; set_color normal
            end
            printf '%-20s %s\n' $f[4] $f[5]
        end
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
