# Returns 0 if the named target exists in the named scenario, 1 otherwise.
function _tgt_target_exists --argument-names scenario target
    _tgt_scenario_validate_name $scenario; or return 1
    _tgt_target_validate_name $target; or return 1
    test -f (_tgt_target_file $scenario $target)
end
