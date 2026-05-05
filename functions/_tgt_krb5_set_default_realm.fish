# Set [libdefaults]/default_realm to the named realm. Creates the
# section + line if either is missing. Atomic write via _tgt_krb5_write.
function _tgt_krb5_set_default_realm --argument-names realm
    test -n "$realm"; or return 1

    set -l krb5 (_tgt_krb5_file)
    set -l content ""
    test -f $krb5; and set content (command cat -- $krb5 | string collect)

    if string match -rq '(?m)^[ \t]*default_realm[ \t]*=' -- $content
        set content (string replace -r -- '(?m)^([ \t]*)default_realm[ \t]*=.*$' "\$1default_realm = $realm" $content | string collect)
    else if string match -rq '\[libdefaults\]' -- $content
        set content (string replace -r -- '(\[libdefaults\])' "\$1\n\tdefault_realm = $realm" $content | string collect)
    else
        set content "[libdefaults]
	default_realm = $realm

$content"
    end

    printf '%s' $content | _tgt_krb5_write
end
