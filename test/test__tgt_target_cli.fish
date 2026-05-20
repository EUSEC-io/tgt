source (status dirname)/helpers.fish

#
# Active-name helpers: defaults vs. set values.
#
@test "active_scenario_name: 'default' when unset" \
    (_tgt_active_scenario_name) = default
@test "active_target_name: 'default' when unset" \
    (_tgt_active_target_name) = default
set -gx TGT_SCENARIO dante
set -gx TGT_ACTIVE web01
@test "active_scenario_name: returns \$TGT_SCENARIO when set" \
    (_tgt_active_scenario_name) = dante
@test "active_target_name: returns \$TGT_ACTIVE when set" \
    (_tgt_active_target_name) = web01
set -e TGT_SCENARIO TGT_ACTIVE

#
# tgt new: errors without active scenario.
#
_test_setup_home
@test "target_cli new: errors when no scenario active" \
    (_tgt_target_cli new web01 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# tgt new: creates target slot, sets TGT_ACTIVE.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_target_cli new web01 >/dev/null
@test "target_cli new: target file created" \
    (_tgt_target_exists dante web01; echo $status) -eq 0
@test "target_cli new: TGT_ACTIVE set" "$TGT_ACTIVE" = web01
_test_teardown

#
# tgt new: rejects duplicates.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_target_cli new web01 >/dev/null
@test "target_cli new: rejects duplicate alias" \
    (_tgt_target_cli new web01 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# tgt new: rejects invalid alias.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
@test "target_cli new: rejects invalid alias" \
    (_tgt_target_cli new "bad alias" 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# tgt switch: loads env vars from registry.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 172.16.10.20
set -gx TGT_HOSTS web01.dante.local intranet.dante.local
_tgt_target_cli new web01 >/dev/null
# Clear env, switch should reload from registry
set -e TGT TGT_HOSTS TGT_ACTIVE
_tgt_target_cli switch web01 >/dev/null
@test "target_cli switch: TGT loaded" "$TGT" = "172.16.10.20"
@test "target_cli switch: TGT_HOSTS loaded" (count $TGT_HOSTS) -eq 2
@test "target_cli switch: TGT_ACTIVE set" "$TGT_ACTIVE" = web01
_test_teardown

#
# tgt switch: rejects nonexistent target.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
@test "target_cli switch: rejects nonexistent" \
    (_tgt_target_cli switch nope 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# tgt list: empty / populated, marks active.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
@test "target_cli list: empty scenario" \
    (_tgt_target_cli list) = "(no targets in 'dante')"
set -gx TGT 1.2.3.4
_tgt_target_cli new web01 >/dev/null
_tgt_target_cli new dc01 >/dev/null
set -l output (_tgt_target_cli list)
@test "target_cli list: 2 entries after creating 2 targets" \
    (count $output) -eq 2
@test "target_cli list: dc01 marked active (just-created)" \
    (string match -rq '^\* dc01' -- $output; echo $status) -eq 0
@test "target_cli list: web01 not active" \
    (string match -rq '^  web01' -- $output; echo $status) -eq 0
_test_teardown

#
# tgt rm: removes registry + hosts entries, clears TGT_ACTIVE if removed-self.
#
_test_setup_home
set -gx TGT_HOSTS_FILE (mktemp)
printf "127.0.0.1\tlocalhost\n" > $TGT_HOSTS_FILE
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 172.16.10.20
_tgt_target_cli new web01 >/dev/null
_tgt_hosts_add dante web01 172.16.10.20 web01.dante.local
_tgt_target_cli rm web01 >/dev/null
@test "target_cli rm: target file gone" \
    (_tgt_target_exists dante web01; echo $status) -ne 0
@test "target_cli rm: hosts entry gone" \
    (cat $TGT_HOSTS_FILE | string match -q "*tgt:dante:web01*"; echo $status) -ne 0
@test "target_cli rm: user lines preserved" \
    (cat $TGT_HOSTS_FILE | string match -q "*localhost*"; echo $status) -eq 0
@test "target_cli rm: TGT_ACTIVE cleared (removed-self)" \
    (set -q TGT_ACTIVE; echo $status) -ne 0
_test_teardown

#
# tgt rm: keeps TGT_ACTIVE when a different target is removed.
#
_test_setup_home
set -gx TGT_HOSTS_FILE (mktemp)
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 1.2.3.4
_tgt_target_cli new web01 >/dev/null
_tgt_target_cli new dc01 >/dev/null
# dc01 is now active (just-created)
_tgt_target_cli rm web01 >/dev/null
@test "target_cli rm: TGT_ACTIVE unchanged when removing non-active" \
    "$TGT_ACTIVE" = dc01
_test_teardown

#
# tgt rm: errors on missing target.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
@test "target_cli rm: errors on nonexistent" \
    (_tgt_target_cli rm nope 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# Unknown verb dispatched to _tgt_target_cli → error.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
@test "target_cli: unknown verb returns nonzero" \
    (_tgt_target_cli garbage 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# tgt edit <alias> --host / --hosts — non-interactive flag mode.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_target_cli new web --no-edit >/dev/null
set -gx TGT 10.10.10.10
set -gx TGT_HOSTS "web.dante.local"
_tgt_target_save dante web
_tgt_clear_target_runtime

_tgt_target_cli new db --no-edit >/dev/null
set -gx TGT 10.10.10.20
_tgt_target_save dante db
_tgt_clear_target_runtime
_tgt_target_cli switch web >/dev/null   # web is active

# Edit the NON-active target (db). Active state must be preserved.
_tgt_target_cli edit db --host 10.10.10.99 >/dev/null
set -l file (_tgt_target_file dante db)
@test "target edit --host (other target): host updated on disk" \
    (grep -q "TGT 10.10.10.99" $file; echo $status) -eq 0
@test "target edit (other target): active target unchanged" \
    "$TGT_ACTIVE" = web
@test "target edit (other target): active TGT preserved" \
    "$TGT" = 10.10.10.10
@test "target edit (other target): active TGT_HOSTS preserved" \
    "$TGT_HOSTS" = "web.dante.local"
_test_teardown

#
# Editing the currently-active target updates the live TGT_HOSTS
# env to the new value (so /etc/hosts can re-sync correctly).
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_target_cli new web --no-edit >/dev/null
set -gx TGT 10.10.10.10
set -gx TGT_HOSTS "old.dante.local"
_tgt_target_save dante web
_tgt_clear_target_runtime
_tgt_target_cli switch web >/dev/null

_tgt_target_cli edit web --hosts "new.dante.local extra.dante.local" >/dev/null
@test "target edit (active): TGT_HOSTS in env updated" \
    "$TGT_HOSTS" = "new.dante.local extra.dante.local"
@test "target edit (active): TGT preserved" \
    "$TGT" = 10.10.10.10
_test_teardown

#
# Empty --hosts clears the on-disk field.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_target_cli new web --no-edit >/dev/null
set -gx TGT 10.10.10.10
set -gx TGT_HOSTS "web.dante.local"
_tgt_target_save dante web
_tgt_clear_target_runtime

_tgt_target_cli edit web --hosts "" >/dev/null
set -l file (_tgt_target_file dante web)
@test "target edit --hosts '': line removed from disk" \
    (grep -q TGT_HOSTS $file; echo $status) -ne 0
@test "target edit --hosts '': TGT line preserved" \
    (grep -q "TGT 10.10.10.10" $file; echo $status) -eq 0
_test_teardown

#
# No alias + no active target + flag → error (alias is required
# when no target is active).
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_target_cli new web --no-edit >/dev/null
set -gx TGT 10.10.10.10
_tgt_target_save dante web
_tgt_clear_target_runtime
# `tgt … new` auto-activates the new target; clear TGT_ACTIVE
# so this test exercises the "no active target" branch.
set -q TGT_ACTIVE; and _tgt_unexport TGT_ACTIVE

set -l rc (_tgt_target_cli edit --host 10.10.10.99 2>/dev/null; echo $status)
@test "target edit (no alias, no active): non-zero" "$rc" -ne 0
_test_teardown
