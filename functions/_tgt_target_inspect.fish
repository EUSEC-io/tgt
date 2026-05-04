# Read a target's registry file and emit a tab-separated state line
# WITHOUT loading values into the current shell:
#   alias\thost\tcreds(Y/N)\tAD(Y/N)\thosts_count
function _tgt_target_inspect --argument-names scenario alias
    set -l file (_tgt_target_file $scenario $alias)
    test -f $file; or return 1

    set -l tgt ""
    set -l user ""
    set -l pass ""
    set -l ad ""
    set -l hosts_count 0
    while read -l line
        set -l m (string match -r '^_tgt_export\s+(\S+)\s+(.*)$' -- $line)
        test (count $m) -lt 3; and continue
        set -l var $m[2]
        set -l val $m[3]
        switch $var
            case TGT
                set tgt $val
            case TGT_USERNAME
                set user $val
            case TGT_PASSWORD
                set pass set
            case TGT_AD_DOMAIN
                set ad $val
            case TGT_HOSTS
                set hosts_count (count (string split " " -- $val))
        end
    end < $file

    set -l host_part $tgt
    test -z "$host_part"; and set host_part "—"

    set -l creds N
    test -n "$user"; and test -n "$pass"; and set creds Y
    set -l ad_part N
    test -n "$ad"; and set ad_part Y
    printf '%s\t%s\t%s\t%s\t%d\n' $alias $host_part $creds $ad_part $hosts_count
end
