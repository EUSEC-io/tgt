source (status dirname)/helpers.fish

#
# DC create with --kdc-host (no IP) + matching /etc/hosts entry:
# resolver fills in IP_SOURCE=hosts after save.
#
_test_setup_home
# Pre-populate /etc/hosts with a manual entry.
echo "10.10.10.5 dc01.dante.local" > $TGT_HOSTS_FILE
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 --domain dante.local --kdc-host dc01.dante.local >/dev/null

# Reload to confirm what's persisted.
_tgt_dc_clear_runtime
_tgt_dc_load dante dc01

@test "dc resolve (hosts): TGT_DC_IP filled from /etc/hosts" \
    "$TGT_DC_IP" = 10.10.10.5
@test "dc resolve (hosts): TGT_DC_IP_SOURCE = hosts" \
    "$TGT_DC_IP_SOURCE" = hosts
@test "dc resolve (hosts): TGT_DC_HOST preserved" \
    "$TGT_DC_HOST" = dc01.dante.local
_test_teardown

#
# DC create with both --kdc-host AND --kdc-ip: resolver doesn't run,
# IP_SOURCE marked as user.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 --domain dante.local --kdc-host dc01.dante.local --kdc-ip 10.10.10.5 >/dev/null

_tgt_dc_clear_runtime
_tgt_dc_load dante dc01

@test "dc resolve (user-provided): TGT_DC_IP_SOURCE = user" \
    "$TGT_DC_IP_SOURCE" = user
_test_teardown

#
# DC create with only --kdc-host and the host isn't in /etc/hosts:
# resolver tries DNS. With no DNS available (or `host` failing on a
# .invalid TLD), IP stays unset, source stays unset.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 --domain dante.local --kdc-host nope.invalid >/dev/null

_tgt_dc_clear_runtime
_tgt_dc_load dante dc01

@test "dc resolve (no match): TGT_DC_IP stays unset" \
    (set -q TGT_DC_IP; echo $status) -ne 0
@test "dc resolve (no match): TGT_DC_IP_SOURCE stays unset" \
    (set -q TGT_DC_IP_SOURCE; echo $status) -ne 0
_test_teardown

#
# Edit wizard: user provides only host (clears the IP); resolver
# refills the IP from /etc/hosts on save.
#
_test_setup_home
echo "10.10.10.42 ms01.dante.local" > $TGT_HOSTS_FILE
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 --domain dante.local --kdc-host dc01.dante.local --kdc-ip 10.10.10.5 >/dev/null

# Edit: keep domain/realm/host, change host to ms01 (which is in
# /etc/hosts at .42), clear IP via empty + y.
set -gx TGT_ASK_QUEUE \
    "" \
    "" \
    ms01.dante.local \
    "" y \
    "" ""
_tgt_dc_edit_wizard dante dc01 >/dev/null

_tgt_dc_clear_runtime
_tgt_dc_load dante dc01

@test "dc resolve (edit, host changed): IP refilled from /etc/hosts" \
    "$TGT_DC_IP" = 10.10.10.42
@test "dc resolve (edit, host changed): IP_SOURCE = hosts" \
    "$TGT_DC_IP_SOURCE" = hosts
_test_teardown
