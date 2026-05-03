# Map an arbitrary directory name to a valid tgt scenario name.
# Lowercases, replaces any chars outside [A-Z a-z 0-9 _ -] with `-`,
# collapses runs of `-`, trims leading/trailing `-`. Returns
# "unnamed" if nothing usable is left (e.g., an empty / dots-only
# input).
function _tgt_scenario_sanitize_name --argument-names raw
    set -l name (string lower -- $raw)
    set name (string replace -ra '[^a-z0-9_-]' '-' -- $name)
    set name (string replace -ra -- '-+' '-' $name)
    set name (string trim --chars '-' -- $name)
    test -z "$name"; and echo unnamed; or echo $name
end
