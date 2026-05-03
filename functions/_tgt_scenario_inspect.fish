# Aggregate state for a scenario:  name\ttargets_count\tcreds(Y/N)\tAD(Y/N)
# Reads target files via _tgt_target_inspect — no side effects on
# the current shell. creds=Y if any target has both username and
# password set; AD=Y if any target has TGT_AD_DOMAIN set.
function _tgt_scenario_inspect --argument-names name
    test -z "$name"; and return 1
    set -l targets (_tgt_target_list $name)
    set -l count (count $targets)
    set -l any_creds N
    set -l any_ad N
    for target in $targets
        set -l line (_tgt_target_inspect $name $target)
        set -l fields (string split \t -- $line)
        # fields: alias, host, creds, ad, hosts_count
        test "$fields[3]" = Y; and set any_creds Y
        test "$fields[4]" = Y; and set any_ad Y
    end
    printf '%s\t%d\t%s\t%s\n' $name $count $any_creds $any_ad
end
