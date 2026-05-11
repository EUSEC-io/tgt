# Emit the aliases of every credential entry in a scenario, one
# per line. No output (and exit 0) when the scenario has none.
function _tgt_cred_list --argument-names scenario
    set -l dir (_tgt_scenario_dir $scenario)/creds
    test -d $dir; or return 0
    for f in $dir/*.fish
        test -f $f; or continue
        basename $f .fish
    end
end
