# Render the krb5 realm block for one DC entry. Output:
#
#     # tgt:dc:<scenario>:<alias>
#     <REALM> = {
#         kdc = <kdc-value>
#         [admin_server = <admin-value>]
#     }
#
# Picks host over IP for both kdc and admin_server when both are
# stored — the host-form pairs naturally with the /etc/hosts
# mapping the DC creation flow writes. Returns non-zero (no output)
# when the entry has no realm or no kdc value.
function _tgt_krb5_render_dc --argument-names scenario alias
    set -l file (_tgt_dc_file $scenario $alias)
    test -f $file; or return 1

    set -l realm ""
    set -l kdc_host ""
    set -l kdc_ip ""
    set -l admin_host ""
    set -l admin_ip ""
    while read -l ln
        set -l m (string match -r '^_tgt_export\s+(\S+)\s+(.*)$' -- $ln)
        test (count $m) -lt 3; and continue
        switch $m[2]
            case TGT_DC_REALM
                set realm $m[3]
            case TGT_DC_HOST
                set kdc_host $m[3]
            case TGT_DC_IP
                set kdc_ip $m[3]
            case TGT_DC_ADMIN_HOST
                set admin_host $m[3]
            case TGT_DC_ADMIN_IP
                set admin_ip $m[3]
        end
    end < $file

    test -z "$realm"; and return 1

    set -l kdc $kdc_host
    test -z "$kdc"; and set kdc $kdc_ip
    test -z "$kdc"; and return 1

    set -l admin $admin_host
    test -z "$admin"; and set admin $admin_ip

    echo "    # tgt:dc:$scenario:$alias"
    echo "    $realm = {"
    echo "        kdc = $kdc"
    test -n "$admin"; and echo "        admin_server = $admin"
    echo "    }"
end
