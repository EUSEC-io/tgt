# List all registered scenarios, one name per line. No output if none.
function _tgt_scenario_list
    set -l scenarios_dir (_tgt_home)/scenarios
    test -d $scenarios_dir; or return 0
    for entry in $scenarios_dir/*
        test -d $entry; and command basename $entry
    end
end
