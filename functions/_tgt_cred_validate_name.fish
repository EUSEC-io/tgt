# Same rules as targets / scenarios / DCs — alias maps 1:1 to a
# filename, so reject anything that wouldn't be safe there.
function _tgt_cred_validate_name --argument-names name
    test -n "$name"; or return 1
    string match -rq '^[A-Za-z0-9_][A-Za-z0-9_-]*$' -- $name
end
