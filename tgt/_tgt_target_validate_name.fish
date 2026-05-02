# Check that a target alias is safe for use as a filename and tag.
# Same rules as scenario names — names map 1:1 to filesystem entries.
function _tgt_target_validate_name --argument-names name
    test -n "$name"; or return 1
    string match -rq '^[A-Za-z0-9_][A-Za-z0-9_-]*$' -- $name
end
