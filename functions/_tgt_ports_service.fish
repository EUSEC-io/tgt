# Set/replace the service name on an existing record. Comment is
# preserved. Mirrors `_tgt_ports_comment` — errors if no matching
# record exists (a service rename targets a known port, not a way
# to register a port indirectly).
function _tgt_ports_service --argument-names scenario target port proto service
    _tgt_ports_validate_port $port; or return 1
    _tgt_ports_validate_proto $proto; or return 1

    set -l file (_tgt_ports_file $scenario $target)
    test -f $file; or return 1

    set -l found 0
    set -l comment ""
    while read -l line
        set -l fields (string split \t -- $line)
        if test (count $fields) -ge 2; and test "$fields[1]" = "$port"; and test "$fields[2]" = "$proto"
            set found 1
            test (count $fields) -ge 4; and set comment $fields[4]
            break
        end
    end < $file

    test $found -eq 1; or return 1
    _tgt_ports_add $scenario $target $port $proto $service $comment
end
