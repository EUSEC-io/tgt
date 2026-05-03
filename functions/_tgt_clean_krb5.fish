# Remove the named realm's block from the krb5 config file.
function _tgt_clean_krb5 --argument-names realm
    set -l krb5 (_tgt_krb5_file)
    test -f $krb5; or return 0

    set -l content (command cat $krb5 | string collect)
    string match -q "*$realm*" -- $content; or return 0

    set -l escaped (string escape --style=regex -- $realm)
    set -l updated (string replace -ar -- "\n?\s*$escaped\s*=\s*\{[^}]*\}" "" $content | string collect)

    test "$content" = "$updated"; and return 0

    printf '%s' $updated | _tgt_krb5_write
end
