# Add or replace the active target's realm + KDC in the krb5 config
# file. Single atomic write via _tgt_krb5_write (was three separate
# sudo'd sed/sh -c invocations before).
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

    # Drop any pre-existing block for this realm before adding the
    # fresh one. (clean writes the file once; we re-read below.)
    _tgt_clean_krb5 $realm

    set -l content ""
    test -f $krb5; and set content (command cat $krb5 | string collect)

    # 1. default_realm: replace the value if the line is present;
    # otherwise inject the line under [libdefaults] (creating the
    # section if absent).
    if string match -rq '(?m)^[ \t]*default_realm[ \t]*=' -- $content
        set content (string replace -r -- '(?m)^([ \t]*)default_realm[ \t]*=.*$' "\$1default_realm = $realm" $content | string collect)
    else if string match -rq '\[libdefaults\]' -- $content
        set content (string replace -r -- '(\[libdefaults\])' "\$1\n\tdefault_realm = $realm" $content | string collect)
    else
        set content "[libdefaults]
	default_realm = $realm

$content"
    end

    # 2. Realm block. _tgt_clean_krb5 above removed any existing one.
    set -l realm_block "    $realm = {
        kdc = $kdc_host
    }"
    if string match -rq '\[realms\]' -- $content
        set content (string replace -r -- '(\[realms\])' "\$1
$realm_block" $content | string collect)
    else
        # Ensure trailing newline, then append a fresh [realms] section.
        if not string match -rq '\n$' -- $content
            set content "$content"\n
        end
        set content "$content
[realms]
$realm_block
"
    end

    printf '%s' $content | _tgt_krb5_write
    echo "  ✓ krb5.conf: default_realm = $realm, kdc = $kdc_host"
end
