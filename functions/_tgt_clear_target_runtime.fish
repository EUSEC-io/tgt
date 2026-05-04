# Erase the active target's runtime env vars (TGT, credentials, AD
# info, hostnames). Does not touch TGT_SCENARIO, TGT_ACTIVE, or
# workspace settings.
function _tgt_clear_target_runtime
    for v in TGT TGT_PORT TGT_USERNAME TGT_PASSWORD TGT_AD_DOMAIN TGT_DC TGT_HOSTS
        set -q $v; and _tgt_unexport $v
    end
end
