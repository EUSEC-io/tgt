# Path to a scenario's directory under the registry root.
function _tgt_scenario_dir --argument-names name
    echo (_tgt_home)/scenarios/$name
end
