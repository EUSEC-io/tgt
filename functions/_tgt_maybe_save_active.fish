# Persist the current $TGT* env state into the active target's
# registry file, but only if there's a registered active target to
# write to. Used after operations that mutate the target's data
# (--add-host, --rm-host) so the registry stays in sync with
# runtime state.
function _tgt_maybe_save_active
    set -q TGT_SCENARIO; or return
    set -q TGT_ACTIVE; or return
    _tgt_scenario_exists $TGT_SCENARIO; or return
    _tgt_target_save $TGT_SCENARIO $TGT_ACTIVE
end
