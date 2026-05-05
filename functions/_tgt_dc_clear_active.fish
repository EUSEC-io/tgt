# Drop the per-scenario active DC marker. Idempotent.
function _tgt_dc_clear_active --argument-names scenario
    set -l file (_tgt_dc_active_file $scenario)
    test -f $file; and command rm -f -- $file
    return 0
end
