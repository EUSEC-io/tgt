# Emit a merged krb5 realm block aggregating ALL the named DC
# aliases that share <realm>. Output:
#
#     # tgt:dc:<scenario>:<alias1>+<alias2>+...
#     <REALM> = {
#         kdc = <kdc1>
#         kdc = <kdc2>           (when two DCs in same realm differ)
#         admin_server = <a1>    (only if any DC supplied one; deduped)
#     }
#
# The merged form is the canonical kerberos style — every krb5
# example uses one block per realm with multiple `kdc =` lines.
# Multiple separate blocks for the same realm name technically
# work in MIT krb5 (the profile parser merges them) but it's
# implementation-dependent and confusing to debug.
#
# kdc value selection per DC: HOST preferred, IP fallback. Same
# rule for admin_server.
function _tgt_krb5_render_realm --argument-names scenario realm
    set -e argv[1..2]
    set -l aliases $argv

    test -z "$realm"; and return 1
    test (count $aliases) -eq 0; and return 1

    set -l kdcs
    set -l admins
    for a in $aliases
        set -l file (_tgt_dc_file $scenario $a)
        test -f $file; or continue
        set -l host ""
        set -l ip ""
        set -l admin_host ""
        set -l admin_ip ""
        while read -l ln
            set -l m (string match -r '^_tgt_export\s+(\S+)\s+(.*)$' -- $ln)
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

        set -l kdc $host
        test -z "$kdc"; and set kdc $ip
        test -n "$kdc"; and begin
            contains -- $kdc $kdcs; or set -a kdcs $kdc
        end

        set -l admin $admin_host
        test -z "$admin"; and set admin $admin_ip
        test -n "$admin"; and begin
            contains -- $admin $admins; or set -a admins $admin
        end
    end

    test (count $kdcs) -eq 0; and return 1

    echo "    # tgt:dc:$scenario:"(string join "+" -- $aliases)
    echo "    $realm = {"
    for k in $kdcs
        echo "        kdc = $k"
    end
    for a in $admins
        echo "        admin_server = $a"
    end
    echo "    }"
end
