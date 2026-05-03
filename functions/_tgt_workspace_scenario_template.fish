# Per-scenario folder/file template, applied at the scenario root in
# nested layout (alongside per-target subfolders). Empty in flat
# layout — the scenario dir there is populated by the target template.
#
# Override via $TGT_WORKSPACE_SCENARIO_TEMPLATE (fish list).
function _tgt_workspace_scenario_template
    if set -q TGT_WORKSPACE_SCENARIO_TEMPLATE
        printf '%s\n' $TGT_WORKSPACE_SCENARIO_TEMPLATE
    else
        printf '%s\n' _report/findings/ _report/screenshots/ _engagement.md
    end
end
