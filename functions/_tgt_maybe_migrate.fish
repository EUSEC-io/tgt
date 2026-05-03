# One-shot upgrade path for users who had $TGT* universal vars set
# before scenarios existed. On the first tgt invocation after the
# upgrade, snapshot whatever state they had into a "default" scenario
# with a "default" target so it shows up in `tgt list` and tooling
# like the prompt segment works without a manual `tgt scenario new`.
#
# Heuristic: migrate only when no scenarios directory exists yet.
# Once the user has any scenarios state at all, this becomes a no-op
# forever — explicit `tgt scenario rm default` followed by another
# `tgt` invocation won't recreate it.
function _tgt_maybe_migrate
    set -q TGT_SCENARIO; and return
    set -q TGT; or return
    test -d (_tgt_home)/scenarios; and return

    _tgt_scenario_create default
    _tgt_export TGT_SCENARIO default
    _tgt_export TGT_ACTIVE default
    _tgt_target_save default default
end
