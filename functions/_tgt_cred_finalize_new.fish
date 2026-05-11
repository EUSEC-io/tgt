# Finish creating a credential entry: save the staged TGT_CRED_*
# env vars to disk, then auto-activate (clear staging, reload from
# the saved file, persist marker). Mirrors `_tgt_dc_finalize_new`.
#
# Caller is responsible for staging:
#   TGT_CRED_USERNAME           — required
#   TGT_CRED_PASSWORD / DOMAIN / NOTES — optional
function _tgt_cred_finalize_new --argument-names scenario alias
    _tgt_cred_save $scenario $alias
    or return $status

    _tgt_cred_clear_runtime
    _tgt_cred_load $scenario $alias
    _tgt_cred_set_active $scenario $alias
end
