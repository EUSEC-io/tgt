# Returns 0 if the named scenario has the archived marker file,
# 1 otherwise. Marker is just a touch file at <scenario_dir>/.archived.
function _tgt_scenario_archived --argument-names name
    test -z "$name"; and return 1
    test -f (_tgt_scenario_dir $name)/.archived
end
