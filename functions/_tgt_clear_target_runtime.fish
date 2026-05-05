# Erase the active target's runtime env vars (host, credentials,
# port, hostnames). Does NOT touch TGT_DC_* vars — those are
# scenario-level state managed by `tgt dc switch/unset`. Does not
# touch TGT_SCENARIO, TGT_ACTIVE, or workspace settings.
function _tgt_clear_target_runtime
    for v in TGT TGT_PORT TGT_USERNAME TGT_PASSWORD TGT_HOSTS
        set -q $v; and _tgt_unexport $v
    end
end
