# Make /etc/hosts reflect ONLY the given scenario's tagged lines.
# Drops every existing tgt-tagged line (any scenario), then adds
# the named scenario's targets' lines (TGT + TGT_HOSTS read from
# each persisted target file). Manual (non-tagged) lines are
# preserved. Single atomic write — one sudo prompt regardless of
# how many targets.
#
# `scenario` may be empty: that just scrubs all tgt-tagged lines.
function _tgt_hosts_apply_scenario --argument-names scenario
    set -l hosts_file (_tgt_hosts_file)
    set -l lines (command cat $hosts_file 2>/dev/null)
    set -l keep

    # ── Step 1: drop ALL tgt-tagged lines (any scenario). The
    # active-scenario-only model means /etc/hosts should hold the
    # CURRENT scenario's lines and nothing else from tgt's past.
    for line in $lines
        string match -q "*# tgt:*:*" -- $line; or set -a keep $line
    end

    # ── Step 2: re-add the new scenario's targets' lines.
    if test -n "$scenario"
        for target in (_tgt_target_list $scenario)
            set -l file (_tgt_target_file $scenario $target)
            test -f $file; or continue
            set -l tgt ""
            set -l hosts
            while read -l line
                set -l m (string match -r '^_tgt_export\s+(\S+)\s+(.*)$' -- $line)
                test (count $m) -lt 3; and continue
                switch $m[2]
                    case TGT
                        set tgt $m[3]
                    case TGT_HOSTS
                        set hosts (string split " " -- $m[3])
                end
            end < $file
            test -z "$tgt"; and continue
            test (count $hosts) -eq 0; and continue
            set -l tag "# tgt:$scenario:$target"
            set -l names_str (string join " " -- $hosts)
            set -a keep "$tgt $names_str $tag"
        end

        # ── Step 3: re-add the new scenario's DC entries' lines.
        # Each DC contributes a line for kdc (when both HOST+IP are
        # set) and one for admin_server when its pair differs from
        # the kdc pair. The strip in step 1 already cleared the old
        # tgt:dc:* lines, so we just emit the desired state.
        for dc_alias in (_tgt_dc_list $scenario)
            set -l file (_tgt_dc_file $scenario $dc_alias)
            test -f $file; or continue
            set -l host ""
            set -l ip ""
            set -l admin_host ""
            set -l admin_ip ""
            while read -l line
                set -l m (string match -r '^_tgt_export\s+(\S+)\s+(.*)$' -- $line)
                test (count $m) -lt 3; and continue
                switch $m[2]
                    case TGT_DC_HOST
                        set host $m[3]
                    case TGT_DC_IP
                        set ip $m[3]
                    case TGT_DC_ADMIN_HOST
                        set admin_host $m[3]
                    case TGT_DC_ADMIN_IP
                        set admin_ip $m[3]
                end
            end < $file
            set -l tag "# tgt:dc:$scenario:$dc_alias"
            set -l pairs
            if test -n "$host"; and test -n "$ip"
                set -a pairs "$ip $host"
            end
            if test -n "$admin_host"; and test -n "$admin_ip"
                set -l adm_pair "$admin_ip $admin_host"
                contains -- $adm_pair $pairs; or set -a pairs $adm_pair
            end
            for p in $pairs
                set -a keep "$p $tag"
            end
        end
    end

    # No change → skip the write (avoids spurious sudo prompts).
    set -l before_joined (string join \n -- $lines)
    set -l after_joined (string join \n -- $keep)
    test "$before_joined" = "$after_joined"; and return 0

    printf '%s\n' $keep | _tgt_hosts_write
end
