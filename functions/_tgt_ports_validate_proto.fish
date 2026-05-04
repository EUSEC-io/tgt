# True iff $proto is "tcp" or "udp" (lowercased).
function _tgt_ports_validate_proto --argument-names proto
    test "$proto" = tcp; or test "$proto" = udp
end
