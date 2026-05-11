# Alias maps 1:1 to a filename, so reject anything that wouldn't be
# safe there. Allows `.` *inside* the name (e.g. `j.doe`, `svc.sql`)
# but not as the leading character — that would collide with the
# dotfile markers (`.active-cred`, `.archived`) in the same dir, and
# `.` / `..` would mean path-traversal.
function _tgt_cred_validate_name --argument-names name
    test -n "$name"; or return 1
    string match -rq '^[A-Za-z0-9_][A-Za-z0-9_.-]*$' -- $name
end
