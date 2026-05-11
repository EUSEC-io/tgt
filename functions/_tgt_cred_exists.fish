# True iff a credential entry with this alias exists in the scenario.
function _tgt_cred_exists --argument-names scenario alias
    test -f (_tgt_cred_file $scenario $alias)
end
