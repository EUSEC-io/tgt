# Snapshot the current TGT_DC_* env vars (raw fields only — DOMAIN,
# REALM, HOST, IP, ADMIN_HOST, ADMIN_IP) into a DC entry file.
#
# TGT_DC and TGT_DC_NAME are NOT stored — they're derived at load
# time (TGT_DC = HOST preferred, IP fallback; TGT_DC_NAME = alias
# from the file path). Storing only the raw inputs means the file
# stays canonical even if the load-time derivation rule changes.
function _tgt_dc_save --argument-names scenario alias
    _tgt_scenario_validate_name $scenario; or return 1
    _tgt_dc_validate_name $alias; or return 1
    _tgt_scenario_exists $scenario; or return 1

    set -l file (_tgt_dc_file $scenario $alias)
    command mkdir -p (dirname $file)
    set -l tmp (command mktemp)

    for var in TGT_DC_DOMAIN TGT_DC_REALM TGT_DC_HOST TGT_DC_IP TGT_DC_ADMIN_HOST TGT_DC_ADMIN_IP
        if set -q $var
            set -l escaped (string escape -- $$var)
            echo "_tgt_export $var "(string join " " -- $escaped) >> $tmp
        end
    end

    command mv $tmp $file
end
