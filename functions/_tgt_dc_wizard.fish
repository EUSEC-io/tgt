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
    set -l kdc_ip   (_tgt_ask_text "KDC IP (optional)" "")
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
    set -l admin_ip   (_tgt_ask_text "admin_server IP (optional)" "")

    # Stage env vars and finalize.
    set -gx TGT_DC_DOMAIN $domain
    set -gx TGT_DC_REALM $realm
    test -n "$kdc_host"   ; and set -gx TGT_DC_HOST $kdc_host
    test -n "$kdc_ip"     ; and set -gx TGT_DC_IP $kdc_ip
    test -n "$admin_host" ; and set -gx TGT_DC_ADMIN_HOST $admin_host
    test -n "$admin_ip"   ; and set -gx TGT_DC_ADMIN_IP $admin_ip

    _tgt_dc_finalize_new $scenario $alias
    or return $status

    set_color green; echo "✓ DC '$alias' created in '$scenario' and activated"; set_color normal
end
