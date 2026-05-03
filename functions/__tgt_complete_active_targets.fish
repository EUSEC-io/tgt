# Emit targets in the active scenario, one per line, for completions.
function __tgt_complete_active_targets
    set -q TGT_SCENARIO; or return
    _tgt_target_list $TGT_SCENARIO 2>/dev/null
end
