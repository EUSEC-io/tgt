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
# Edit: user explicitly clears kdc-IP (was set, now blanked + confirmed
# yes). Resolver MUST NOT re-fill it from /etc/hosts or DNS — the
# clear is intentional.
#
_test_setup_home
# Pre-existing manual /etc/hosts line that WOULD fill in the IP if
# the resolver weren't honoring the explicit-clear intent.
echo "10.10.10.42 ms01.dante.local" > $TGT_HOSTS_FILE
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 --domain dante.local --kdc-host dc01.dante.local --kdc-ip 10.10.10.5 >/dev/null

# Edit: keep domain/realm, change host to ms01 (which IS in /etc/hosts),
# explicitly clear the IP via the `!` sentinel.
set -gx TGT_ASK_QUEUE \
    "" \
    "" \
    ms01.dante.local \
    "!" \
    "" \
    ""
_tgt_dc_edit_wizard dante dc01 >/dev/null

_tgt_dc_clear_runtime
_tgt_dc_load dante dc01

@test "dc resolve (edit, IP explicitly cleared): IP stays unset" \
    (set -q TGT_DC_IP; echo $status) -ne 0
@test "dc resolve (edit, IP explicitly cleared): IP_SOURCE stays unset" \
    (set -q TGT_DC_IP_SOURCE; echo $status) -ne 0
@test "dc resolve (edit, IP cleared, host changed): host updated" \
    "$TGT_DC_HOST" = ms01.dante.local
_test_teardown

#
# Edit: user changes host but leaves IP empty (it was already empty).
# Resolver fires for the new host because no explicit-clear intent
# was registered (cur_kdc_ip was empty too).
#
_test_setup_home
echo "10.10.10.42 ms01.dante.local" > $TGT_HOSTS_FILE
_tgt_scenario_cli new dante >/dev/null
# Create with host only (so cur_kdc_ip starts empty).
tgt dc new dc01 --domain dante.local --kdc-host dc01.dante.local >/dev/null
# Note: dc01.dante.local isn't in /etc/hosts, so dc01 starts with
# no IP after the create-time resolve fails.

# Edit: change host to ms01.dante.local (which IS in /etc/hosts).
# Empty kdc_ip prompt (no default → no confirm), so IP stays empty
# but skip flag stays 0 (cur was also empty).
set -gx TGT_ASK_QUEUE \
    "" \
    "" \
    ms01.dante.local \
    "" \
    "" \
    ""
_tgt_dc_edit_wizard dante dc01 >/dev/null

_tgt_dc_clear_runtime
_tgt_dc_load dante dc01

@test "dc resolve (edit, host changed, IP was always empty): IP filled from /etc/hosts" \
    "$TGT_DC_IP" = 10.10.10.42
@test "dc resolve (edit, host changed): IP_SOURCE = hosts" \
    "$TGT_DC_IP_SOURCE" = hosts
_test_teardown
