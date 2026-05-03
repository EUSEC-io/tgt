# Returns 0 if any persisted target (across all scenarios) has the
# given uppercase realm as its TGT_AD_DOMAIN, 1 otherwise.
# Used after rm to decide whether to clean the realm from krb5.conf.
function _tgt_realm_in_use --argument-names realm
    test -z "$realm"; and return 1
    for scenario in (_tgt_scenario_list)
        for target in (_tgt_target_list $scenario)
            set -l found (_tgt_target_ad_realm $scenario $target)
            test "$found" = "$realm"; and return 0
        end
    end
    return 1
end
