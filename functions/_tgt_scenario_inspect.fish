# Aggregate state for a scenario:  name\ttargets_count\tcreds(Y/N)\tdcs_count
# Reads target files via _tgt_target_inspect (no shell pollution).
# `creds=Y` if any target has both username and password set;
# `dcs_count` is the number of DC entries in the scenario.
function _tgt_scenario_inspect --argument-names name
    test -z "$name"; and return 1
    set -l targets (_tgt_target_list $name)
    set -l count (count $targets)
    set -l any_creds N
    for target in $targets
        set -l line (_tgt_target_inspect $name $target)
        set -l fields (string split \t -- $line)
        # fields: alias, host, creds, hosts_count
        test "$fields[3]" = Y; and set any_creds Y
    end
    set -l dcs_count (count (_tgt_dc_list $name))
    printf '%s\t%d\t%s\t%d\n' $name $count $any_creds $dcs_count
end
