# Read a DC's file and emit a tab-separated state line WITHOUT
# loading anything into the current shell:
#
#   alias\tdomain\trealm\tkdc\tadmin
#
# `kdc` and `admin` resolve to the host form when known, else the IP,
# else "—" — matching what `_tgt_dc_load` would derive into TGT_DC.
function _tgt_dc_inspect --argument-names scenario alias
    set -l file (_tgt_dc_file $scenario $alias)
    test -f $file; or return 1

    set -l domain ""
    set -l realm ""
    set -l host ""
    set -l ip ""
    set -l admin_host ""
    set -l admin_ip ""
    while read -l line
        set -l m (string match -r '^_tgt_export\s+(\S+)\s+(.*)$' -- $line)
        test (count $m) -lt 3; and continue
        switch $m[2]
            case TGT_DC_DOMAIN
                set domain $m[3]
            case TGT_DC_REALM
                set realm $m[3]
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

    set -l kdc $host
    test -z "$kdc"; and set kdc $ip
    set -l admin $admin_host
    test -z "$admin"; and set admin $admin_ip

    test -z "$domain"; and set domain "—"
    test -z "$realm"; and set realm "—"
    test -z "$kdc"; and set kdc "—"
    test -z "$admin"; and set admin "—"

    printf '%s\t%s\t%s\t%s\t%s\n' $alias $domain $realm $kdc $admin
end
