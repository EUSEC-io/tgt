# Hot-swap /etc/hosts on a scenario change. Removes lines tagged
# for the old scenario, then adds lines for every target in the
# new scenario (read from each target's persisted file). Single
# atomic write — one sudo prompt regardless of how many targets.
#
# Either argument may be empty (e.g. first scenario activation
# passes no old; new-empty scenario passes no targets to add).
# No-op when old == new or when nothing actually changed.
function _tgt_hosts_swap_scenario --argument-names old new
    test "$old" = "$new"; and return 0

    set -l hosts_file (_tgt_hosts_file)
    set -l lines (command cat $hosts_file 2>/dev/null)
    set -l keep
    set -l modified 0

    # ── Step 1: filter out lines tagged for the old scenario ──
    if test -n "$old"
        set -l old_pat "# tgt:$old:"
        for line in $lines
            if string match -q "*$old_pat*" -- $line
                set modified 1
            else
                set -a keep $line
            end
        end
    else
        set keep $lines
    end

    # ── Step 2: add the new scenario's targets' /etc/hosts lines ──
    if test -n "$new"
        for target in (_tgt_target_list $new)
            set -l file (_tgt_target_file $new $target)
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
            set -l tag "# tgt:$new:$target"
            set -l names_str (string join " " -- $hosts)
            set -a keep "$tgt $names_str $tag"
            set modified 1
        end
    end

    test $modified -eq 0; and return 0
    printf '%s\n' $keep | _tgt_hosts_write
end
