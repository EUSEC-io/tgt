# Erase the active DC's runtime env vars. Mirrors
# `_tgt_clear_target_runtime` but for the DC half. Doesn't touch
# /etc/krb5.conf or /etc/hosts — those are scenario-level state and
# get rewritten via the apply functions, not per-call.
function _tgt_dc_clear_runtime
    for v in TGT_DC TGT_DC_NAME TGT_DC_DOMAIN TGT_DC_REALM \
             TGT_DC_HOST TGT_DC_IP TGT_DC_ADMIN_HOST TGT_DC_ADMIN_IP
        set -q $v; and _tgt_unexport $v
    end
end
