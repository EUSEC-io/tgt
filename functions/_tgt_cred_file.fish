# Path to a credential entry's storage file under its scenario.
# Sits in `creds/` next to `targets/` and `dcs/`.
function _tgt_cred_file --argument-names scenario alias
    echo (_tgt_scenario_dir $scenario)/creds/$alias.fish
end
