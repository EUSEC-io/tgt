# Output the active scenario name, or "default" when $TGT_SCENARIO unset.
# Used to compose /etc/hosts tags so legacy single-target use keeps
# working unchanged while scenarios+targets opt into proper namespacing.
function _tgt_active_scenario_name
    if set -q TGT_SCENARIO
        echo $TGT_SCENARIO
    else
        echo default
    end
end
