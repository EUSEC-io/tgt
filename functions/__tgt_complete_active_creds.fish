# Emit credential aliases in the active scenario, one per line,
# for completions.
function __tgt_complete_active_creds
    set -q TGT_SCENARIO; or return
    _tgt_cred_list $TGT_SCENARIO 2>/dev/null
end
