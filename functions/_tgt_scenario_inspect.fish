# Aggregate state for a scenario:
#   name\ttargets_count\tcreds_count\tdcs_count
#
# Creds and DCs are scenario-level entities now, so the row shows
# how many of each the scenario has rather than a Y/N derived
# from target state.
function _tgt_scenario_inspect --argument-names name
    test -z "$name"; and return 1
    set -l targets_count (count (_tgt_target_list $name))
    set -l creds_count (count (_tgt_cred_list $name))
    set -l dcs_count (count (_tgt_dc_list $name))
    printf '%s\t%d\t%d\t%d\n' $name $targets_count $creds_count $dcs_count
end
