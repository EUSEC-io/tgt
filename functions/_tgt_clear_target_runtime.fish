# Erase the active target's runtime env vars (host, port, hostnames).
# Credentials and DC info are scenario-level now — managed by
# `tgt cred switch/unset` and `tgt dc switch/unset`. Does NOT touch
# TGT_SCENARIO, TGT_ACTIVE, or workspace settings.
function _tgt_clear_target_runtime
    for v in TGT TGT_PORT TGT_HOSTS
        set -q $v; and _tgt_unexport $v
    end
end
