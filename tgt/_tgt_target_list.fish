# List target aliases in a scenario, one per line. No output if scenario
# is missing or has no targets.
function _tgt_target_list --argument-names scenario
    _tgt_scenario_validate_name $scenario; or return 1
    set -l targets_dir (_tgt_scenario_dir $scenario)/targets
    test -d $targets_dir; or return 0
    for entry in $targets_dir/*.fish
        test -f $entry; or continue
        command basename $entry .fish
    end
end
