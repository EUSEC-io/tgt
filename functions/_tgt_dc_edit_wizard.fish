# Interactive editor for an existing DC entry. Mirrors the new
# wizard's prompts but pre-fills each with the entry's current
# value, so an empty answer re-keeps it (or, for optional fields,
# clears it).
#
# After save: re-applies krb5 + /etc/hosts (since realm / kdc / ip
# may have changed). If the DC being edited is the scenario's
# active one, also reloads env vars and re-sets default_realm so
# the shell reflects the new values immediately.
function _tgt_dc_edit_wizard --argument-names scenario alias
    if not _tgt_dc_exists $scenario $alias
        echo "tgt dc edit: DC '$alias' does not exist in scenario '$scenario'" >&2
        return 1
    end

    # Read current fields without polluting the shell.
    set -l cur_domain ""
    set -l cur_realm ""
    set -l cur_kdc_host ""
    set -l cur_kdc_ip ""
    set -l cur_admin_host ""
    set -l cur_admin_ip ""
    set -l file (_tgt_dc_file $scenario $alias)
    while read -l line
        set -l m (string match -r '^_tgt_export\s+(\S+)\s+(.*)$' -- $line)
        test (count $m) -lt 3; and continue
        switch $m[2]
            case TGT_DC_DOMAIN
                set cur_domain $m[3]
            case TGT_DC_REALM
                set cur_realm $m[3]
            case TGT_DC_HOST
                set cur_kdc_host $m[3]
            case TGT_DC_IP
                set cur_kdc_ip $m[3]
            case TGT_DC_ADMIN_HOST
                set cur_admin_host $m[3]
            case TGT_DC_ADMIN_IP
                set cur_admin_ip $m[3]
        end
    end < $file

    set -l domain (_tgt_ask_text "AD domain (lowercase, e.g. dante.local)" $cur_domain)
    if test -z "$domain"
        echo "tgt dc edit: domain is required" >&2
        return 1
    end

    set -l realm_default $cur_realm
    test -z "$realm_default"; and set realm_default (string upper -- $domain)
    set -l realm (_tgt_ask_text "Kerberos realm" $realm_default)
    set realm (string upper -- $realm)

    echo
    set_color brblack
    echo "  KDC — hostname, IP, or both. '!' on a field clears it:"
    echo "    • host alone   krb5 uses the hostname (DNS must resolve it)"
    echo "    • IP alone     krb5 uses the IP directly"
    echo "    • both         krb5 uses the hostname; /etc/hosts maps it to the IP"
    set_color normal
    set -l kdc_host (_tgt_ask_text_optional "KDC hostname (optional)" $cur_kdc_host)

    # If the host changed (or is set when no IP is yet known), try
    # to resolve it inline so the IP prompt's default is the freshly
    # discovered value. The user can press Enter to accept, or type
    # their own (or `!` to clear).
    set -l kdc_ip_default $cur_kdc_ip
    set -l kdc_ip_default_src ""
    if test -n "$kdc_host"; and begin; test "$kdc_host" != "$cur_kdc_host"; or test -z "$cur_kdc_ip"; end
        set -l result (_tgt_resolve_ip $kdc_host)
        if test (count $result) -ge 2
            set kdc_ip_default $result[1]
            set kdc_ip_default_src $result[2]
            set_color brblack >&2
            echo "    [resolved $kdc_host → $result[1] via $result[2]]" >&2
            set_color normal >&2
        end
    end
    set -l kdc_ip (_tgt_ask_text_optional "KDC IP (optional)" $kdc_ip_default)
    if test -z "$kdc_host"; and test -z "$kdc_ip"
        echo "tgt dc edit: at least one of KDC hostname or IP is required" >&2
        return 1
    end

    echo
    set_color brblack
    echo "  admin_server (optional — used for password changes via kpasswd):"
    set_color normal
    set -l admin_host (_tgt_ask_text_optional "admin_server hostname (optional)" $cur_admin_host)

    set -l admin_ip_default $cur_admin_ip
    set -l admin_ip_default_src ""
    if test -n "$admin_host"; and begin; test "$admin_host" != "$cur_admin_host"; or test -z "$cur_admin_ip"; end
        set -l result (_tgt_resolve_ip $admin_host)
        if test (count $result) -ge 2
            set admin_ip_default $result[1]
            set admin_ip_default_src $result[2]
            set_color brblack >&2
            echo "    [resolved $admin_host → $result[1] via $result[2]]" >&2
            set_color normal >&2
        end
    end
    set -l admin_ip (_tgt_ask_text_optional "admin_server IP (optional)" $admin_ip_default)

    # Capture explicit "user just cleared this" intent — we'll
    # tell the resolver to skip these fields so the IP isn't
    # quietly re-filled from a leftover /etc/hosts entry or DNS
    # record after the user said "Clear it".
    set -l skip_kdc 0
    set -l skip_admin 0
    test -n "$cur_kdc_ip"   ; and test -z "$kdc_ip"   ; and set skip_kdc 1
    test -n "$cur_admin_ip" ; and test -z "$admin_ip" ; and set skip_admin 1

    # Clear staging slots first so blanked answers actually drop the
    # corresponding TGT_DC_* line instead of inheriting old state.
    for v in TGT_DC_DOMAIN TGT_DC_REALM \
             TGT_DC_HOST TGT_DC_IP TGT_DC_IP_SOURCE \
             TGT_DC_ADMIN_HOST TGT_DC_ADMIN_IP TGT_DC_ADMIN_IP_SOURCE
        set -q $v; and _tgt_unexport $v
    end
    set -gx TGT_DC_DOMAIN $domain
    set -gx TGT_DC_REALM $realm
    test -n "$kdc_host"   ; and set -gx TGT_DC_HOST $kdc_host
    test -n "$kdc_ip"     ; and set -gx TGT_DC_IP $kdc_ip
    # IP source: if the user accepted the in-wizard resolved
    # default, attribute to the resolver. Otherwise it's user input.
    if test -n "$kdc_ip"
        if test "$kdc_ip" = "$kdc_ip_default"; and test -n "$kdc_ip_default_src"
            set -gx TGT_DC_IP_SOURCE $kdc_ip_default_src
        else
            set -gx TGT_DC_IP_SOURCE user
        end
    end
    test -n "$admin_host" ; and set -gx TGT_DC_ADMIN_HOST $admin_host
    test -n "$admin_ip"   ; and set -gx TGT_DC_ADMIN_IP $admin_ip
    if test -n "$admin_ip"
        if test "$admin_ip" = "$admin_ip_default"; and test -n "$admin_ip_default_src"
            set -gx TGT_DC_ADMIN_IP_SOURCE $admin_ip_default_src
        else
            set -gx TGT_DC_ADMIN_IP_SOURCE user
        end
    end

    _tgt_dc_save $scenario $alias
    or return $status

    # Resolve any missing IPs (host given, ip empty). Skip flags
    # honor the "user cleared this" intent.
    _tgt_dc_resolve_missing $scenario $alias $skip_kdc $skip_admin

    _tgt_krb5_apply_scenario $scenario
    _tgt_hosts_apply_scenario $scenario

    # Always rebuild the runtime around whichever DC is active for
    # this scenario — editing should never leave the shell in a
    # half-staged state. If the just-edited DC is the active one,
    # the reload picks up its new values; if a different DC is
    # active, its env is restored (the staging from this wizard
    # was transient). If no DC is active, runtime stays cleared.
    set -l active (_tgt_dc_get_active $scenario 2>/dev/null)
    _tgt_dc_clear_runtime
    if test -n "$active"
        _tgt_dc_load $scenario $active
        set -q TGT_DC_REALM; and _tgt_krb5_set_default_realm $TGT_DC_REALM
    end

    set_color green; echo "✓ DC '$alias' updated in '$scenario'"; set_color normal
end
