# Path to the per-scenario "active DC" marker file. Plain text,
# contains the alias of the currently-active DC for that scenario.
# Absent when no DC has been activated yet.
function _tgt_dc_active_file --argument-names scenario
    echo (_tgt_scenario_dir $scenario)/.active-dc
end
