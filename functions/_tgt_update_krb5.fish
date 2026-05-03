# Add or replace the active target's realm + KDC in the krb5 config file.
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

    set -l krb5 (_tgt_krb5_file)

    _tgt_clean_krb5 $realm
    _tgt_sudo sed -i "s/^\s*default_realm\s*=.*/\tdefault_realm = $realm/" $krb5

    if grep -q "^\[realms\]" $krb5
        _tgt_sudo sed -i "/^\[realms\]/a\\    $realm = {\n        kdc = $kdc_host\n    }" $krb5
    else
        _tgt_sudo sh -c "printf '\n[realms]\n    $realm = {\n        kdc = $kdc_host\n    }\n' >> $krb5"
    end

    echo "  ✓ krb5.conf: default_realm = $realm, kdc = $kdc_host"
end
