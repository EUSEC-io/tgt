# Emit the aliases of all DC entries in a scenario, one per line.
# No output (and exit 0) when the scenario has none.
function _tgt_dc_list --argument-names scenario
    set -l dir (_tgt_scenario_dir $scenario)/dcs
    test -d $dir; or return 0
    for f in $dir/*.fish
        test -f $f; or continue
        basename $f .fish
    end
end
