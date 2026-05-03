# Remove a target's registry file. Idempotent.
function _tgt_target_destroy --argument-names scenario target
    _tgt_scenario_validate_name $scenario; or return 1
    _tgt_target_validate_name $target; or return 1
    set -l file (_tgt_target_file $scenario $target)
    test -f $file; or return 0
    command rm -f $file
end
