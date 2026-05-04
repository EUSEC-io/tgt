# Path to a target's port records file under its scenario. Sits next
# to the `<target>.fish` registry as `<target>.ports` so the two stay
# together, but uses a plain tab-separated format (not sourced).
function _tgt_ports_file --argument-names scenario target
    echo (_tgt_scenario_dir $scenario)/targets/$target.ports
end
