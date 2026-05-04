# True iff $port is a valid port number (1-65535).
function _tgt_ports_validate_port --argument-names port
    test -n "$port"; or return 1
    string match -rq '^[0-9]+$' -- $port; or return 1
    test "$port" -ge 1; and test "$port" -le 65535
end
