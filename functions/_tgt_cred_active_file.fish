# Path to the per-scenario "active credential" marker file. Plain
# text, contains the alias of the currently-active credential for
# that scenario. Absent when no credential has been activated.
function _tgt_cred_active_file --argument-names scenario
    echo (_tgt_scenario_dir $scenario)/.active-cred
end
