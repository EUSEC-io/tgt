source (status dirname)/helpers.fish

# ── target rename ──────────────────────────────────────────────

#
# tgt rename <old> <new>: moves the registry file, retags /etc/hosts,
# updates TGT_ACTIVE if it was the renamed target.
#
_test_setup_home
_test_setup_hosts empty.txt
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 10.10.10.5
_tgt_target_cli new web01 --no-edit >/dev/null
_tgt_target_save dante web01
_tgt_hosts_add dante web01 10.10.10.5 web01.dante.local

_tgt_target_cli rename web01 web02 >/dev/null

@test "target rename: new file exists" \
    -e (_tgt_target_file dante web02)
@test "target rename: old file gone" \
    ! -e (_tgt_target_file dante web01)
@test "target rename: TGT_ACTIVE updated" \
    "$TGT_ACTIVE" = web02
@test "target rename: /etc/hosts retagged" \
    (string match -rq '# tgt:dante:web02' -- (cat $TGT_HOSTS_FILE); echo $status) -eq 0
@test "target rename: old tag gone" \
    (string match -rq '# tgt:dante:web01' -- (cat $TGT_HOSTS_FILE); echo $status) -ne 0
_test_teardown

#
# tgt rename <new>: implicit "rename active target".
#
_test_setup_home
_test_setup_hosts empty.txt
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_cli new web01 --no-edit >/dev/null
_tgt_target_save dante web01

_tgt_target_cli rename web02 >/dev/null

@test "target rename (single arg): renames active" \
    "$TGT_ACTIVE" = web02
@test "target rename (single arg): web02 file exists" \
    -e (_tgt_target_file dante web02)
_test_teardown

#
# tgt rename: rejects existing alias.
#
_test_setup_home
_test_setup_hosts empty.txt
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_cli new web01 --no-edit >/dev/null
_tgt_target_cli new dc01 --no-edit >/dev/null
set -l rc (_tgt_target_cli rename web01 dc01 2>/dev/null; echo $status)

@test "target rename: rejects existing alias" $rc -ne 0
@test "target rename (failed): web01 still exists" \
    -e (_tgt_target_file dante web01)
_test_teardown

#
# tgt rename: rejects invalid alias (special chars).
#
_test_setup_home
_test_setup_hosts empty.txt
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_cli new web01 --no-edit >/dev/null
set -l rc2 (_tgt_target_cli rename web01 "bad name" 2>/dev/null; echo $status)
@test "target rename: rejects invalid alias" $rc2 -ne 0
_test_teardown

#
# tgt rename: same name → no-op error.
#
_test_setup_home
_test_setup_hosts empty.txt
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_cli new web01 --no-edit >/dev/null
set -l rc3 (_tgt_target_cli rename web01 web01 2>/dev/null; echo $status)
@test "target rename: rejects identical name" $rc3 -ne 0
_test_teardown

#
# tgt rename (nested layout): moves the per-target workspace folder.
#
_test_setup_home
_test_setup_hosts empty.txt
_test_setup_workspace
set -gx TGT_WORKSPACE_LAYOUT nested
set -gx TGT_WORKSPACE_AUTOCREATE 1
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_cli new web01 --no-edit >/dev/null
@test "target rename setup: web01 dir exists" \
    -d "$TGT_WORKSPACE_ROOT/dante/web01"

_tgt_target_cli rename web01 web02 >/dev/null

@test "target rename (nested): web02 dir exists" \
    -d "$TGT_WORKSPACE_ROOT/dante/web02"
@test "target rename (nested): web01 dir gone" \
    ! -d "$TGT_WORKSPACE_ROOT/dante/web01"
_test_teardown

# ── scenario rename ────────────────────────────────────────────

#
# tgt scenario rename <old> <new>: moves the scenario dir, retags
# all targets in /etc/hosts, updates TGT_SCENARIO.
#
_test_setup_home
_test_setup_hosts empty.txt
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_cli new web01 --no-edit >/dev/null
_tgt_target_save dante web01
_tgt_hosts_add dante web01 1.1.1.1 web01.dante

_tgt_scenario_cli rename dante dante2 >/dev/null

@test "scenario rename: new dir exists" \
    -d (_tgt_scenario_dir dante2)
@test "scenario rename: old dir gone" \
    ! -d (_tgt_scenario_dir dante)
@test "scenario rename: TGT_SCENARIO updated" \
    "$TGT_SCENARIO" = dante2
@test "scenario rename: /etc/hosts retagged" \
    (string match -rq '# tgt:dante2:web01' -- (cat $TGT_HOSTS_FILE); echo $status) -eq 0
@test "scenario rename: old tag gone" \
    (string match -rq '# tgt:dante:web01' -- (cat $TGT_HOSTS_FILE); echo $status) -ne 0
_test_teardown

#
# tgt scenario rename <new>: implicit rename active scenario.
#
_test_setup_home
_test_setup_hosts empty.txt
_tgt_scenario_cli new dante >/dev/null
_tgt_scenario_cli rename dante2 >/dev/null

@test "scenario rename (single arg): renames active" \
    "$TGT_SCENARIO" = dante2
@test "scenario rename (single arg): old gone" \
    ! -d (_tgt_scenario_dir dante)
_test_teardown

#
# tgt scenario rename: rejects existing name.
#
_test_setup_home
_test_setup_hosts empty.txt
_tgt_scenario_cli new dante >/dev/null
_tgt_scenario_cli new acme >/dev/null
set -l rc4 (_tgt_scenario_cli rename dante acme 2>/dev/null; echo $status)
@test "scenario rename: rejects existing name" $rc4 -ne 0
_test_teardown

#
# tgt scenario rename: moves the workspace folder.
#
_test_setup_home
_test_setup_hosts empty.txt
_test_setup_workspace
set -gx TGT_WORKSPACE_AUTOCREATE 1
_tgt_scenario_cli new dante >/dev/null

_tgt_scenario_cli rename dante dante2 >/dev/null

@test "scenario rename: new workspace dir exists" \
    -d "$TGT_WORKSPACE_ROOT/dante2"
@test "scenario rename: old workspace dir gone" \
    ! -d "$TGT_WORKSPACE_ROOT/dante"
_test_teardown
