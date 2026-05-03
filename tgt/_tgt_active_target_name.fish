# Output the active target alias, or "default" when $TGT_ACTIVE unset.
# Pairs with _tgt_active_scenario_name to compose /etc/hosts tags.
function _tgt_active_target_name
    if set -q TGT_ACTIVE
        echo $TGT_ACTIVE
    else
        echo default
    end
end
