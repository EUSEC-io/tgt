# Help text for `tgt scenario`. Extracted so `_tgt_scenario_cli` and
# the gum-driven menu can both fall back to it.
function _tgt_scenario_help
    echo ""
    echo "  tgt scenario — manage engagement / lab scenarios"
    echo ""
    echo "    tgt scenario new <name>      Create a new scenario, switch to it"
    echo "    tgt scenario list            List scenarios (active marked)"
    echo "    tgt scenario show [name]     Show scenario details"
    echo "    tgt scenario switch <name>   Make a scenario active"
    echo "    tgt scenario rename [<old>] <new>"
    echo "                                 Rename a scenario (or the active one)."
    echo "                                 Updates /etc/hosts tags + workspace folder."
    echo "    tgt scenario rm <name> [--purge-workspace]"
    echo "                                 Delete a scenario + its /etc/hosts entries."
    echo "                                 With --purge-workspace, also rm -rf its folder."
    echo ""
end
