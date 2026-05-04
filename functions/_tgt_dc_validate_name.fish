# Same rules as targets/scenarios — alias maps 1:1 to a filename
# and a /etc/hosts tag, so reject anything else.
function _tgt_dc_validate_name --argument-names name
    test -n "$name"; or return 1
    string match -rq '^[A-Za-z0-9_][A-Za-z0-9_-]*$' -- $name
end
