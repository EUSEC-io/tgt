# Path to a DC entry's storage file under its scenario. Sits in
# `dcs/` next to `targets/`.
function _tgt_dc_file --argument-names scenario alias
    echo (_tgt_scenario_dir $scenario)/dcs/$alias.fish
end
