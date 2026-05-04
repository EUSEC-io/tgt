# Emit DC aliases in the active scenario, one per line, for completions.
function __tgt_complete_active_dcs
    set -q TGT_SCENARIO; or return
    _tgt_dc_list $TGT_SCENARIO 2>/dev/null
end
