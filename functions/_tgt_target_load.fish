# Load a target's saved env vars by selectively sourcing its
# registry file. Lines for legacy fields no longer in the current
# schema (TGT_USERNAME / TGT_PASSWORD / TGT_AD_DOMAIN / TGT_DC)
# are skipped — those moved to per-scenario credential and DC
# entries respectively. Re-saving the target later (e.g. via
# `tgt --add-host`) drops the stale lines.
function _tgt_target_load --argument-names scenario target
    _tgt_target_exists $scenario $target; or return 1
    set -l file (_tgt_target_file $scenario $target)
    while read -l line
        string match -rq '^_tgt_export\s+TGT_USERNAME\s'  -- $line; and continue
        string match -rq '^_tgt_export\s+TGT_PASSWORD\s'  -- $line; and continue
        string match -rq '^_tgt_export\s+TGT_AD_DOMAIN\s' -- $line; and continue
        string match -rq '^_tgt_export\s+TGT_DC\s'        -- $line; and continue
        eval $line
    end < $file
end
