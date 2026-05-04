# Common pentest-relevant TCP ports — the "look at this" set. The
# picker/list highlights any record matching one of these so that
# scrolling through a long port table you spot the high-signal ones
# immediately.
#
# Override per-shell or universally:
#   set -gx TGT_INTERESTING_TCP 21 22 80 443 445 3389
#
# Pre-baked default leans toward AD + common service exposure.
function _tgt_ports_interesting_tcp
    if set -q TGT_INTERESTING_TCP
        printf '%s\n' $TGT_INTERESTING_TCP
        return
    end
    printf '%s\n' \
        21 22 23 25 53 80 88 110 135 139 143 389 \
        443 445 464 593 636 1433 2049 3268 3269 \
        3306 3389 5432 5985 5986 8080 8443
end
