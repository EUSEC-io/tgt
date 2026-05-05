# Echo the active DC alias for a scenario, or exit 1 with no output
# when none is set.
function _tgt_dc_get_active --argument-names scenario
    set -l file (_tgt_dc_active_file $scenario)
    test -f $file; or return 1
    command cat -- $file
end
