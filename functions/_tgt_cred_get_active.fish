# Echo the active credential alias for a scenario, or exit 1
# with no output when none is set.
function _tgt_cred_get_active --argument-names scenario
    set -l file (_tgt_cred_active_file $scenario)
    test -f $file; or return 1
    command cat -- $file
end
