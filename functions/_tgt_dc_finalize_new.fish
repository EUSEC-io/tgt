# Finish creating a DC entry: write the staged TGT_DC_* env vars to
# disk, sync /etc/krb5.conf and /etc/hosts, then auto-activate
# (clear staging, reload from the saved file, persist marker, point
# default_realm at the new realm).
#
# Caller is responsible for staging:
#   TGT_DC_DOMAIN, TGT_DC_REALM   — required
#   at least one of TGT_DC_HOST / TGT_DC_IP
#   admin_* fields are optional
function _tgt_dc_finalize_new --argument-names scenario alias
    _tgt_dc_save $scenario $alias
    or return $status
    _tgt_dc_clear_runtime
    _tgt_krb5_apply_scenario $scenario
    _tgt_hosts_apply_scenario $scenario
    _tgt_dc_load $scenario $alias
    _tgt_dc_set_active $scenario $alias
    set -q TGT_DC_REALM; and _tgt_krb5_set_default_realm $TGT_DC_REALM
end
