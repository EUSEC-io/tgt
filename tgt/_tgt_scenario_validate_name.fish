# Check that a scenario name is safe for use as a directory and tag.
# Allowed: letters, digits, underscore, hyphen. No leading hyphen.
function _tgt_scenario_validate_name --argument-names name
    test -n "$name"; or return 1
    string match -rq '^[A-Za-z0-9_][A-Za-z0-9_-]*$' -- $name
end
