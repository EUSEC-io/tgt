source (status dirname)/helpers.fish

#
# Auto-save: tgt --add-host persists the updated $TGT_HOSTS into the
# active target's registry file, so a later switch reflects the change.
#
_test_setup_home
set -gx TGT_HOSTS_FILE (mktemp)
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 10.10.10.5
_tgt_target_cli new web01 >/dev/null
tgt --add-host web01.dante.local intranet.dante.local >/dev/null

set -e TGT TGT_HOSTS
_tgt_target_load dante web01

@test "auto-save after --add-host: TGT round-trips" "$TGT" = "10.10.10.5"
@test "auto-save after --add-host: TGT_HOSTS round-trips as list" \
    (count $TGT_HOSTS) -eq 2
@test "auto-save after --add-host: includes web01.dante.local" \
    (contains web01.dante.local $TGT_HOSTS; echo $status) -eq 0
_test_teardown

#
# Auto-save: tgt --rm-host persists too — including the case where
# all hostnames are removed (TGT_HOSTS becomes unset on disk).
#
_test_setup_home
set -gx TGT_HOSTS_FILE (mktemp)
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 10.10.10.5
_tgt_target_cli new web01 >/dev/null
tgt --add-host a.dante b.dante c.dante >/dev/null
tgt --rm-host b.dante >/dev/null

set -e TGT TGT_HOSTS
_tgt_target_load dante web01

@test "auto-save after --rm-host: 2 hosts remain" \
    (count $TGT_HOSTS) -eq 2
@test "auto-save after --rm-host: removed host gone" \
    (contains b.dante $TGT_HOSTS; echo $status) -ne 0
_test_teardown

#
# Switch clears stale env: switching to a target with fewer fields
# defined unsets the inherited values from the previous target.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
# Build "populated" target with TGT + TGT_HOSTS
set -gx TGT 1.1.1.1
set -gx TGT_HOSTS host1 host2
_tgt_target_save dante populated
# Build "bare" target with nothing set
set -e TGT TGT_HOSTS
_tgt_target_save dante bare

# Load populated, then switch to bare; bare has no fields → all should clear.
_tgt_target_cli switch populated >/dev/null
@test "before switch to bare: TGT loaded from populated" "$TGT" = "1.1.1.1"
@test "before switch to bare: TGT_HOSTS loaded from populated" \
    (count $TGT_HOSTS) -eq 2

_tgt_target_cli switch bare >/dev/null
@test "after switch to bare: TGT cleared (was 1.1.1.1)" \
    (set -q TGT; echo $status) -ne 0
@test "after switch to bare: TGT_HOSTS cleared" \
    (set -q TGT_HOSTS; echo $status) -ne 0
@test "after switch: TGT_ACTIVE updated to bare" "$TGT_ACTIVE" = bare
_test_teardown

#
# Switch with partial overlap: target B has TGT but no TGT_HOSTS.
# After switching A → B, TGT updates to B's value, TGT_HOSTS clears.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 1.1.1.1
set -gx TGT_HOSTS host1 host2
_tgt_target_save dante a
set -e TGT_HOSTS
set -gx TGT 2.2.2.2
_tgt_target_save dante b

_tgt_target_cli switch a >/dev/null
@test "switched to A: TGT and TGT_HOSTS both present" \
    "$TGT" = "1.1.1.1"; and test (count $TGT_HOSTS) -eq 2
_tgt_target_cli switch b >/dev/null
@test "switched to B: TGT updated to B's value" "$TGT" = "2.2.2.2"
@test "switched to B: TGT_HOSTS cleared (B has no hosts)" \
    (set -q TGT_HOSTS; echo $status) -ne 0
_test_teardown

#
# TGT_PORT is a transient runtime selection (set via `tgt ports`),
# not part of the saved registry — switching targets must clear it.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_save dante a
set -gx TGT 2.2.2.2
_tgt_target_save dante b
_tgt_target_cli switch a >/dev/null
set -gx TGT_PORT 445
_tgt_target_cli switch b >/dev/null
@test "switch: TGT_PORT cleared (transient, doesn't follow target)" \
    (set -q TGT_PORT; echo $status) -ne 0
_test_teardown
