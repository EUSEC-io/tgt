# Read a target's registry file and emit a tab-separated state line
# WITHOUT loading values into the current shell:
#   alias\thost\thosts_count
#
# Credentials and AD info are no longer per-target — see
# `tgt cred list` and `tgt dc list` for the scenario's entries.
function _tgt_target_inspect --argument-names scenario alias
    set -l file (_tgt_target_file $scenario $alias)
    test -f $file; or return 1

    set -l tgt ""
    set -l hosts_count 0
    while read -l line
        set -l m (string match -r '^_tgt_export\s+(\S+)\s+(.*)$' -- $line)
        test (count $m) -lt 3; and continue
        switch $m[2]
            case TGT
                set tgt $m[3]
            case TGT_HOSTS
                set hosts_count (count (string split " " -- $m[3]))
        end
    end < $file

    set -l host_part $tgt
    test -z "$host_part"; and set host_part "—"

    printf '%s\t%s\t%d\n' $alias $host_part $hosts_count
end
