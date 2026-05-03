# Remove the named realm's block from the krb5 config file. If the
# `default_realm` line in [libdefaults] points at the removed realm,
# reset it to one of the remaining realms (or ATHENA.MIT.EDU as a
# neutral fallback when none are left).
function _tgt_clean_krb5 --argument-names realm
    set -l krb5 (_tgt_krb5_file)
    test -f $krb5; or return 0

    set -l content (command cat $krb5 | string collect)
    string match -q "*$realm*" -- $content; or return 0

    set -l escaped (string escape --style=regex -- $realm)

    # Step 1: drop the realm block from [realms].
    set -l updated (string replace -ar -- "\n?\s*$escaped\s*=\s*\{[^}]*\}" "" $content | string collect)

    # Step 2: if default_realm still names the removed realm, retarget
    # it. Pick the first realm name that survives in [realms]; fall
    # back to ATHENA.MIT.EDU when no realms remain.
    set -l next_realm ATHENA.MIT.EDU
    set -l remaining (string match -ra -- '(?m)^[ \t]*([A-Za-z0-9_.-]+)[ \t]*=[ \t]*\{' $updated)
    # `string match -ra` with one capture: [full1, cap1, full2, cap2, …].
    if test (count $remaining) -ge 2
        set next_realm $remaining[2]
    end
    set -l default_pattern '(?m)^([ \t]*)default_realm[ \t]*=[ \t]*'$escaped'[ \t]*$'
    set -l default_replacement '$1default_realm = '$next_realm
    set updated (string replace -r -- $default_pattern $default_replacement $updated | string collect)

    test "$content" = "$updated"; and return 0

    printf '%s' $updated | _tgt_krb5_write
end
