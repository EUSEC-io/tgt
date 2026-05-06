# Interactive wizard for `tgt dc new`. Prompts for each field with
# clear hints — the kdc/admin pair explains that you can give the
# hostname, IP, or both, and what each form means in the resulting
# /etc/krb5.conf and /etc/hosts.
#
# After collection it stages the TGT_DC_* env vars and delegates
# to _tgt_dc_finalize_new (save → sync → auto-activate).
function _tgt_dc_wizard --argument-names scenario init_alias
    set -l alias $init_alias
    if test -z "$alias"
        set alias (_tgt_ask_text "DC alias (e.g. dc01)" "")
        if test $status -ne 0; or test -z "$alias"
            set_color brblack; echo "  cancelled."; set_color normal
            return 1
        end
    end
    if not _tgt_dc_validate_name $alias
        echo "tgt dc new: invalid alias '$alias' (allowed: A-Z a-z 0-9 _ -)" >&2
        return 1
    end
    if _tgt_dc_exists $scenario $alias
        echo "tgt dc new: DC '$alias' already exists in scenario '$scenario'" >&2
        return 1
    end

    # Domain (lowercase, required).
    set -l domain (_tgt_ask_text "AD domain (lowercase, e.g. dante.local)" "")
    if test -z "$domain"
        echo "tgt dc new: --domain is required" >&2
        return 1
    end

    # Realm — default to upper(domain), accept overrides for the
    # rare non-canonical case (e.g. host-as-realm). Always uppercase.
    set -l realm_default (string upper -- $domain)
    set -l realm (_tgt_ask_text "Kerberos realm" $realm_default)
    set realm (string upper -- $realm)

    # KDC pair — explain the host/ip duality once.
    echo
    set_color brblack
    echo "  KDC — provide hostname, IP, or both:"
    echo "    • host alone   krb5 uses the hostname (DNS must resolve it)"
    echo "    • IP alone     krb5 uses the IP directly"
    echo "    • both         krb5 uses the hostname; /etc/hosts maps it to the IP"
    set_color normal
    set -l kdc_host (_tgt_ask_text "KDC hostname (optional)" "")

    # In-wizard resolution: if the user supplied a hostname, try
    # to resolve it now so the IP prompt's default is the freshly
    # discovered value. Press Enter to accept, or type a different IP.
    set -l kdc_ip_default ""
    set -l kdc_ip_default_src ""
    if test -n "$kdc_host"
        set -l result (_tgt_resolve_ip $kdc_host)
        if test (count $result) -ge 2
            set kdc_ip_default $result[1]
            set kdc_ip_default_src $result[2]
            set_color brblack >&2
            echo "    [resolved $kdc_host → $result[1] via $result[2]]" >&2
            set_color normal >&2
        end
    end
    set -l kdc_ip (_tgt_ask_text "KDC IP (optional)" $kdc_ip_default)
    if test -z "$kdc_host"; and test -z "$kdc_ip"
        echo "tgt dc new: at least one of KDC hostname or IP is required" >&2
        return 1
    end

    # admin_server (optional).
    echo
    set_color brblack
    echo "  admin_server (optional — used for password changes via kpasswd):"
    set_color normal
    set -l admin_host (_tgt_ask_text "admin_server hostname (optional)" "")

    set -l admin_ip_default ""
    set -l admin_ip_default_src ""
    if test -n "$admin_host"
        set -l result (_tgt_resolve_ip $admin_host)
        if test (count $result) -ge 2
            set admin_ip_default $result[1]
            set admin_ip_default_src $result[2]
            set_color brblack >&2
            echo "    [resolved $admin_host → $result[1] via $result[2]]" >&2
            set_color normal >&2
        end
    end
    set -l admin_ip (_tgt_ask_text "admin_server IP (optional)" $admin_ip_default)

    # Clear stale state first — absent answers should land as
    # unset, not pick up the previously-active DC's values.
    _tgt_dc_clear_runtime
    # Stage env vars and finalize.
    set -gx TGT_DC_DOMAIN $domain
    set -gx TGT_DC_REALM $realm
    test -n "$kdc_host"   ; and set -gx TGT_DC_HOST $kdc_host
    test -n "$kdc_ip"     ; and set -gx TGT_DC_IP $kdc_ip
    # IP source: if user accepted the in-wizard resolved default,
    # attribute to the resolver. Otherwise it's user input — and
    # `_tgt_dc_finalize_new` will mark TGT_DC_IP_SOURCE=user via
    # its own logic when SOURCE isn't already set.
    if test -n "$kdc_ip"; and test "$kdc_ip" = "$kdc_ip_default"; and test -n "$kdc_ip_default_src"
        set -gx TGT_DC_IP_SOURCE $kdc_ip_default_src
    end
    test -n "$admin_host" ; and set -gx TGT_DC_ADMIN_HOST $admin_host
    test -n "$admin_ip"   ; and set -gx TGT_DC_ADMIN_IP $admin_ip
    if test -n "$admin_ip"; and test "$admin_ip" = "$admin_ip_default"; and test -n "$admin_ip_default_src"
        set -gx TGT_DC_ADMIN_IP_SOURCE $admin_ip_default_src
    end

    _tgt_dc_finalize_new $scenario $alias
    or return $status

    set_color green; echo "✓ DC '$alias' created in '$scenario' and activated"; set_color normal
end
