# True iff <port>+<proto> is in the interesting set for that proto.
function _tgt_ports_is_interesting --argument-names port proto
    set -l set
    switch $proto
        case tcp
            set set (_tgt_ports_interesting_tcp)
        case udp
            set set (_tgt_ports_interesting_udp)
        case '*'
            return 1
    end
    contains -- $port $set
end
