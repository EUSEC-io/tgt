# Common pentest-relevant UDP ports — sister to _tgt_ports_interesting_tcp.
# Override via $TGT_INTERESTING_UDP.
function _tgt_ports_interesting_udp
    if set -q TGT_INTERESTING_UDP
        printf '%s\n' $TGT_INTERESTING_UDP
        return
    end
    printf '%s\n' \
        53 88 123 137 161 389 500 4500 5353
end
