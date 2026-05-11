# Drop the per-scenario active-cred marker. Idempotent.
function _tgt_cred_clear_active --argument-names scenario
    set -l file (_tgt_cred_active_file $scenario)
    test -f $file; and command rm -f -- $file
    return 0
end
