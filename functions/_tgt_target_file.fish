# Path to a target's registry file under its scenario.
function _tgt_target_file --argument-names scenario target
    echo (_tgt_scenario_dir $scenario)/targets/$target.fish
end
