# Look at a saved DC entry and fill in any missing IPs by resolving
# the corresponding host (kdc-host → kdc-ip; admin-host → admin-ip).
# Records the source ("hosts" or "dns") in the matching `*_SOURCE`
# field so `tgt dc show` can attribute it later.
#
# Only runs at create/edit time — the apply_scenario step doesn't
# trigger this. DNS probes are too expensive to repeat on every
# scenario switch.
#
# Per-field skip flags (third + fourth args, "1" to skip):
# the edit wizard sets these when the user explicitly cleared a
# field, so an "I want this empty" intent isn't quietly undone by
# the resolver re-filling from /etc/hosts or DNS.
function _tgt_dc_resolve_missing --argument-names scenario alias skip_kdc skip_admin
    set -l file (_tgt_dc_file $scenario $alias)
    test -f $file; or return 1

    # Load the entry's current values into locals (no shell pollution).
    set -l host ""
    set -l ip ""
    set -l ip_src ""
    set -l admin_host ""
    set -l admin_ip ""
    set -l admin_ip_src ""
    while read -l line
        set -l m (string match -r '^_tgt_export\s+(\S+)\s+(.*)$' -- $line)
        test (count $m) -lt 3; and continue
        switch $m[2]
            case TGT_DC_HOST
                set host $m[3]
            case TGT_DC_IP
                set ip $m[3]
            case TGT_DC_IP_SOURCE
                set ip_src $m[3]
            case TGT_DC_ADMIN_HOST
                set admin_host $m[3]
            case TGT_DC_ADMIN_IP
                set admin_ip $m[3]
            case TGT_DC_ADMIN_IP_SOURCE
                set admin_ip_src $m[3]
        end
    end < $file

    set -l changed 0

    if test "$skip_kdc" != "1"
        if test -n "$host"; and test -z "$ip"
            set -l result (_tgt_resolve_ip $host)
            if test (count $result) -ge 2
                set ip $result[1]
                set ip_src $result[2]
                set changed 1
            end
        end
    end

    if test "$skip_admin" != "1"
        if test -n "$admin_host"; and test -z "$admin_ip"
            set -l result (_tgt_resolve_ip $admin_host)
            if test (count $result) -ge 2
                set admin_ip $result[1]
                set admin_ip_src $result[2]
                set changed 1
            end
        end
    end

    test $changed -eq 0; and return 0

    # Re-stage the env so _tgt_dc_save writes the updated file. We
    # also need the other fields (domain, realm, host, admin_host)
    # so save snapshots a complete record. Re-read them.
    set -l domain ""
    set -l realm ""
    while read -l line
        set -l m (string match -r '^_tgt_export\s+(\S+)\s+(.*)$' -- $line)
        test (count $m) -lt 3; and continue
        switch $m[2]
            case TGT_DC_DOMAIN
                set domain $m[3]
            case TGT_DC_REALM
                set realm $m[3]
        end
    end < $file

    _tgt_dc_clear_runtime
    set -gx TGT_DC_DOMAIN $domain
    set -gx TGT_DC_REALM $realm
    test -n "$host"      ; and set -gx TGT_DC_HOST $host
    test -n "$ip"        ; and set -gx TGT_DC_IP $ip
    test -n "$ip_src"    ; and set -gx TGT_DC_IP_SOURCE $ip_src
    test -n "$admin_host"; and set -gx TGT_DC_ADMIN_HOST $admin_host
    test -n "$admin_ip"  ; and set -gx TGT_DC_ADMIN_IP $admin_ip
    test -n "$admin_ip_src"; and set -gx TGT_DC_ADMIN_IP_SOURCE $admin_ip_src
    _tgt_dc_save $scenario $alias
end
