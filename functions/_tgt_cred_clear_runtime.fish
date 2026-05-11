# Erase the active credential's runtime env vars. Mirrors
# `_tgt_dc_clear_runtime` and `_tgt_clear_target_runtime` but
# for credentials. Both the raw stored fields (TGT_CRED_*) and
# the derived public fields (TGT_USERNAME / TGT_PASSWORD) are
# wiped so tools don't see stale state after switch/unset.
function _tgt_cred_clear_runtime
    for v in TGT_USERNAME TGT_PASSWORD \
             TGT_CRED_NAME TGT_CRED_USERNAME TGT_CRED_PASSWORD \
             TGT_CRED_DOMAIN TGT_CRED_NOTES
        set -q $v; and _tgt_unexport $v
    end
end
