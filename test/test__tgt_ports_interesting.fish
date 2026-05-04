source (status dirname)/helpers.fish

#
# Default sets contain the expected pentester staples.
#
set -l default_tcp (_tgt_ports_interesting_tcp)
@test "interesting_tcp default: includes 445 (SMB)" \
    (contains 445 $default_tcp; echo $status) -eq 0
@test "interesting_tcp default: includes 22 (SSH)" \
    (contains 22 $default_tcp; echo $status) -eq 0
@test "interesting_tcp default: includes 3389 (RDP)" \
    (contains 3389 $default_tcp; echo $status) -eq 0
@test "interesting_tcp default: includes 5985 (WinRM)" \
    (contains 5985 $default_tcp; echo $status) -eq 0
@test "interesting_tcp default: excludes 31337 (random high port)" \
    (contains 31337 $default_tcp; echo $status) -ne 0

set -l default_udp (_tgt_ports_interesting_udp)
@test "interesting_udp default: includes 161 (SNMP)" \
    (contains 161 $default_udp; echo $status) -eq 0
@test "interesting_udp default: includes 88 (Kerberos)" \
    (contains 88 $default_udp; echo $status) -eq 0
@test "interesting_udp default: excludes 9999" \
    (contains 9999 $default_udp; echo $status) -ne 0

#
# Env overrides replace the default set wholesale.
#
set -gx TGT_INTERESTING_TCP 31337 31338
@test "interesting_tcp override: returns the user's list" \
    (count (_tgt_ports_interesting_tcp)) -eq 2
@test "interesting_tcp override: 31337 listed" \
    (contains 31337 (_tgt_ports_interesting_tcp); echo $status) -eq 0
@test "interesting_tcp override: 445 dropped" \
    (contains 445 (_tgt_ports_interesting_tcp); echo $status) -ne 0
set -e TGT_INTERESTING_TCP

set -gx TGT_INTERESTING_UDP 161
@test "interesting_udp override: only 161 in set" \
    (count (_tgt_ports_interesting_udp)) -eq 1
@test "interesting_udp override: 88 dropped" \
    (contains 88 (_tgt_ports_interesting_udp); echo $status) -ne 0
set -e TGT_INTERESTING_UDP

#
# is_interesting respects proto.
#
@test "is_interesting: 445/tcp → yes" \
    (_tgt_ports_is_interesting 445 tcp; echo $status) -eq 0
@test "is_interesting: 445/udp → no (445 not in udp default)" \
    (_tgt_ports_is_interesting 445 udp; echo $status) -ne 0
@test "is_interesting: 161/udp → yes" \
    (_tgt_ports_is_interesting 161 udp; echo $status) -eq 0
@test "is_interesting: 161/tcp → no" \
    (_tgt_ports_is_interesting 161 tcp; echo $status) -ne 0
@test "is_interesting: 31337/tcp → no (not in default)" \
    (_tgt_ports_is_interesting 31337 tcp; echo $status) -ne 0
@test "is_interesting: bogus proto → no" \
    (_tgt_ports_is_interesting 80 sctp; echo $status) -ne 0

#
# Honors TGT_INTERESTING_TCP override for the membership test too.
#
set -gx TGT_INTERESTING_TCP 31337
@test "is_interesting: 31337/tcp → yes after override" \
    (_tgt_ports_is_interesting 31337 tcp; echo $status) -eq 0
@test "is_interesting: 445/tcp → no after override (445 dropped)" \
    (_tgt_ports_is_interesting 445 tcp; echo $status) -ne 0
set -e TGT_INTERESTING_TCP
