# Add or replace the active target's realm + KDC in /etc/krb5.conf.
function _tgt_update_krb5
    if not set -q TGT_AD_DOMAIN
        return
    end

    set -l realm (string upper $TGT_AD_DOMAIN)
    set -l kdc_host ""

    if set -q TGT_DC
        set kdc_host $TGT_DC
    else if set -q TGT
        set kdc_host $TGT
    else
        return
    end

    _tgt_clean_krb5 $realm
    sudo sed -i "s/^\s*default_realm\s*=.*/\tdefault_realm = $realm/" /etc/krb5.conf

    set -l realm_block "\n    $realm = {\n        kdc = $kdc_host\n    }"

    if grep -q "^\[realms\]" /etc/krb5.conf
        sudo sed -i "/^\[realms\]/a\\    $realm = {\n        kdc = $kdc_host\n    }" /etc/krb5.conf
    else
        sudo sh -c "printf '\n[realms]\n    $realm = {\n        kdc = $kdc_host\n    }\n' >> /etc/krb5.conf"
    end

    echo "  ✓ krb5.conf: default_realm = $realm, kdc = $kdc_host"
end
