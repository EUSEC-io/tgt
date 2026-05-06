source (status dirname)/helpers.fish

#
# /etc/hosts lookup hits an existing manual entry — case-insensitive.
#
_test_setup_home
echo "127.0.0.1 localhost
10.10.10.5 dc01.dante.local
192.168.1.1 my-router" > $TGT_HOSTS_FILE

set -l result (_tgt_resolve_ip dc01.dante.local)
@test "resolve_ip (hosts): match found" \
    (count $result) -eq 2
@test "resolve_ip (hosts): IP correct" \
    "$result[1]" = 10.10.10.5
@test "resolve_ip (hosts): source = hosts" \
    "$result[2]" = hosts

set -l result_uc (_tgt_resolve_ip DC01.DANTE.LOCAL)
@test "resolve_ip (hosts): case-insensitive match" \
    "$result_uc[1]" = 10.10.10.5
@test "resolve_ip (hosts): case-insensitive source = hosts" \
    "$result_uc[2]" = hosts
_test_teardown

#
# /etc/hosts entries written by tgt itself (`# tgt:` tag) are
# IGNORED by the resolver — consulting them creates a feedback
# loop where clearing a field would re-fill from the entry's
# own previous /etc/hosts line.
#
_test_setup_home
echo "10.10.10.5 dc01.dante.local # tgt:dc:dante:dc01" > $TGT_HOSTS_FILE
@test "resolve_ip: tagged tgt lines are skipped (no match)" \
    (_tgt_resolve_ip dc01.dante.local 2>/dev/null; echo $status) -ne 0

# Manual entry for a different host on the same file is still
# found, even though a tagged line is present.
echo "10.10.10.5 dc01.dante.local # tgt:dc:dante:dc01
10.20.20.7 manual.example.com" > $TGT_HOSTS_FILE
set -l result (_tgt_resolve_ip manual.example.com)
@test "resolve_ip: manual line still resolved alongside tagged ones" \
    "$result[1]" = 10.20.20.7
@test "resolve_ip: source = hosts for manual entry" \
    "$result[2]" = hosts
_test_teardown

#
# Unknown host with no fallback → non-zero, no output.
#
_test_setup_home
echo "127.0.0.1 localhost" > $TGT_HOSTS_FILE
@test "resolve_ip: unknown host returns non-zero" \
    (_tgt_resolve_ip nonexistent.invalid 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# Empty hostname → non-zero.
#
_test_setup_home
@test "resolve_ip: empty hostname → non-zero" \
    (_tgt_resolve_ip "" 2>/dev/null; echo $status) -ne 0
_test_teardown
