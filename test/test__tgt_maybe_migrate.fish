source (status dirname)/helpers.fish

#
# No-op when nothing to migrate (no $TGT, no scenarios dir).
#
_test_setup_home
_tgt_maybe_migrate
@test "migrate: no $TGT → no scenarios dir created" \
    (test -d $TGT_HOME/scenarios; echo $status) -ne 0
@test "migrate: TGT_SCENARIO stays unset" \
    (set -q TGT_SCENARIO; echo $status) -ne 0
_test_teardown

#
# First run with legacy $TGT: creates default scenario + target,
# sets active env vars, snapshots the legacy state.
#
_test_setup_home
set -gx TGT 10.10.11.5
set -gx TGT_USERNAME admin
set -gx TGT_HOSTS forest.htb dc01.htb.local
_tgt_maybe_migrate
@test "migrate: default scenario exists" \
    (_tgt_scenario_exists default; echo $status) -eq 0
@test "migrate: default target exists" \
    (_tgt_target_exists default default; echo $status) -eq 0
@test "migrate: TGT_SCENARIO set to default" "$TGT_SCENARIO" = default
@test "migrate: TGT_ACTIVE set to default" "$TGT_ACTIVE" = default
# Snapshotted legacy state should round-trip via load.
set -e TGT TGT_USERNAME TGT_HOSTS
_tgt_target_load default default
@test "migrate: snapshot preserved TGT" "$TGT" = "10.10.11.5"
@test "migrate: snapshot preserved TGT_USERNAME" "$TGT_USERNAME" = "admin"
@test "migrate: snapshot preserved TGT_HOSTS as list" \
    (count $TGT_HOSTS) -eq 2
_test_teardown

#
# No re-migration once scenarios dir exists. Even if the user nukes
# the default scenario, the existence of the scenarios/ parent dir
# means migration won't fire again.
#
_test_setup_home
set -gx TGT 10.10.11.5
_tgt_maybe_migrate                    # First run — migrates.
_tgt_scenario_destroy default         # User decides to remove it.
set -e TGT_SCENARIO TGT_ACTIVE         # And clears their env.
_tgt_maybe_migrate                    # Second run — should NOT recreate.
@test "migrate: doesn't recreate default after explicit destroy" \
    (_tgt_scenario_exists default; echo $status) -ne 0
@test "migrate: TGT_SCENARIO stays unset on second run" \
    (set -q TGT_SCENARIO; echo $status) -ne 0
_test_teardown

#
# Skips when TGT_SCENARIO is already set (user is already in
# scenario context, even if it's a custom one).
#
_test_setup_home
set -gx TGT 10.10.11.5
set -gx TGT_SCENARIO custom
_tgt_maybe_migrate
@test "migrate: doesn't fire when TGT_SCENARIO already set" \
    (test -d $TGT_HOME/scenarios/default; echo $status) -ne 0
_test_teardown

#
# Idempotent: a second call after migration is a no-op.
#
_test_setup_home
set -gx TGT 10.10.11.5
_tgt_maybe_migrate
set -l mtime_after_first (stat -c '%Y' $TGT_HOME/scenarios/default/targets/default.fish)
_tgt_maybe_migrate
set -l mtime_after_second (stat -c '%Y' $TGT_HOME/scenarios/default/targets/default.fish)
@test "migrate: second call doesn't rewrite the target file" \
    "$mtime_after_first" = "$mtime_after_second"
_test_teardown
