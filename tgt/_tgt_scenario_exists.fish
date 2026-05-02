# Returns 0 if the named scenario exists in the registry, 1 otherwise.
function _tgt_scenario_exists --argument-names name
    _tgt_scenario_validate_name $name; or return 1
    test -d (_tgt_scenario_dir $name)
end
