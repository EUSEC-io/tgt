# True iff a DC entry with this alias exists in the scenario.
function _tgt_dc_exists --argument-names scenario alias
    test -f (_tgt_dc_file $scenario $alias)
end
