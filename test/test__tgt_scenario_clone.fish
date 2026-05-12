source (status dirname)/helpers.fish

#
# clone helper: targets, port records, DCs, and the active-DC marker
# all copy across.
#
_test_setup_home
_tgt_scenario_cli new src >/dev/null
set -gx TGT 10.10.10.5
_tgt_target_cli new web01 --no-edit >/dev/null
_tgt_ports_add src web01 22 tcp ssh ""
_tgt_ports_add src web01 80 tcp http "internal"
set -gx TGT 10.10.10.10
_tgt_target_cli new dc01 --no-edit >/dev/null
tgt dc new realdc --domain src.local --kdc-host dc01.src.local --kdc-ip 10.10.10.5 >/dev/null

_tgt_scenario_clone src dest

@test "clone: dest scenario exists" \
    (_tgt_scenario_exists dest; echo $status) -eq 0
@test "clone: src scenario still exists" \
    (_tgt_scenario_exists src; echo $status) -eq 0
@test "clone: web01 target carried over" \
    (_tgt_target_exists dest web01; echo $status) -eq 0
@test "clone: dc01 target carried over" \
    (_tgt_target_exists dest dc01; echo $status) -eq 0
@test "clone: target count matches source (2)" \
    (count (_tgt_target_list dest)) -eq 2
@test "clone: web01.ports file carried over" \
    (test -f $TGT_HOME/scenarios/dest/targets/web01.ports; echo $status) -eq 0
@test "clone: web01 port records intact" \
    (count (_tgt_ports_list dest web01)) -eq 2
@test "clone: realdc DC entry carried over" \
    (_tgt_dc_exists dest realdc; echo $status) -eq 0
@test "clone: DC count matches source (1)" \
    (count (_tgt_dc_list dest)) -eq 1
@test "clone: .active-dc marker carried over" \
    (_tgt_dc_get_active dest) = realdc
_test_teardown

#
# clone DOES NOT copy source's workspace contents (scans, loot, etc.) —
# but the CLI `tgt scenario clone` does auto-create an empty workspace
# folder for the clone when TGT_WORKSPACE_AUTOCREATE is on (mirrors
# `tgt scenario new`).
#
_test_setup_home
set -gx TGT_WORKSPACE_ROOT (mktemp -d)
set -gx TGT_WORKSPACE_AUTOCREATE 1
_tgt_scenario_cli new src >/dev/null
set -gx TGT 10.10.10.5
_tgt_target_cli new web01 --no-edit >/dev/null
# Drop a fake artifact in the workspace so we'd notice if it copied.
mkdir -p $TGT_WORKSPACE_ROOT/src/scans
echo "fake scan" > $TGT_WORKSPACE_ROOT/src/scans/nmap.txt

# Helper-level clone: no autocreate — just registry copy.
_tgt_scenario_clone src dest
@test "clone (helper): source workspace untouched" \
    (test -f $TGT_WORKSPACE_ROOT/src/scans/nmap.txt; echo $status) -eq 0
@test "clone (helper): dest workspace dir NOT created (helper doesn't autocreate)" \
    (test -d $TGT_WORKSPACE_ROOT/dest; echo $status) -ne 0

# CLI clone: autocreate kicks in.
_tgt_scenario_cli clone src dest2 >/dev/null
@test "clone (CLI, autocreate): dest workspace dir IS created" \
    (test -d $TGT_WORKSPACE_ROOT/dest2; echo $status) -eq 0
@test "clone (CLI, autocreate): source's scan file NOT copied to dest2" \
    (test -f $TGT_WORKSPACE_ROOT/dest2/scans/nmap.txt; echo $status) -ne 0
_test_teardown

#
# clone copies credentials + the .active-cred marker (mirror of DC).
#
_test_setup_home
_tgt_scenario_cli new src >/dev/null
tgt cred new admin --username Administrator --password hunter2 >/dev/null
tgt cred new svc --username svc-web --password p2 >/dev/null
# admin was created first, svc is currently active (last-new wins).
# Switch back to admin so the active marker matches.
tgt cred switch admin >/dev/null

_tgt_scenario_clone src dest

@test "clone: admin cred carried over" \
    (_tgt_cred_exists dest admin; echo $status) -eq 0
@test "clone: svc cred carried over" \
    (_tgt_cred_exists dest svc; echo $status) -eq 0
@test "clone: cred count matches source (2)" \
    (count (_tgt_cred_list dest)) -eq 2
@test "clone: .active-cred marker carried over" \
    (_tgt_cred_get_active dest) = admin
_test_teardown

#
# clone DOES NOT copy the .archived marker (clone starts active).
#
_test_setup_home
_tgt_scenario_cli new src >/dev/null
# Drop the .archived marker directly — archive is a CLI-only verb,
# no standalone helper exposes it.
touch (_tgt_scenario_dir src)/.archived
@test "clone setup: src is archived" \
    (_tgt_scenario_archived src; echo $status) -eq 0

_tgt_scenario_clone src dest
@test "clone: dest is NOT archived" \
    (_tgt_scenario_archived dest; echo $status) -ne 0
_test_teardown

#
# clone DOES NOT activate the new scenario — active stays as before.
#
_test_setup_home
_tgt_scenario_cli new src >/dev/null
@test "clone setup: src is active" "$TGT_SCENARIO" = src
_tgt_scenario_clone src dest
@test "clone: TGT_SCENARIO unchanged (still src)" "$TGT_SCENARIO" = src
_test_teardown

#
# clone validates: src must exist, dest must be valid + free.
#
_test_setup_home
_tgt_scenario_cli new src >/dev/null
@test "clone: missing src → non-zero" \
    (_tgt_scenario_clone ghost dest 2>/dev/null; echo $status) -ne 0
@test "clone: invalid dest name → non-zero" \
    (_tgt_scenario_clone src "bad name" 2>/dev/null; echo $status) -ne 0
@test "clone: existing dest name → non-zero" \
    (_tgt_scenario_clone src src 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# CLI: 2-arg form `tgt scenario clone <src> <new>`.
#
_test_setup_home
_tgt_scenario_cli new src >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_cli new web01 --no-edit >/dev/null
_tgt_scenario_cli new other >/dev/null
# active is now `other`; clone src to dest while in `other`.
_tgt_scenario_cli clone src dest >/dev/null
@test "scenario_cli clone: dest exists" \
    (_tgt_scenario_exists dest; echo $status) -eq 0
@test "scenario_cli clone: dest carried over web01" \
    (_tgt_target_exists dest web01; echo $status) -eq 0
@test "scenario_cli clone: active unchanged (still other)" \
    "$TGT_SCENARIO" = other
_test_teardown

#
# CLI: 1-arg form clones the active scenario.
#
_test_setup_home
_tgt_scenario_cli new src >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_cli new web01 --no-edit >/dev/null
_tgt_scenario_cli clone dest >/dev/null
@test "scenario_cli clone (1-arg): dest cloned from active" \
    (_tgt_target_exists dest web01; echo $status) -eq 0
_test_teardown

#
# CLI: interactive mode (no args) — picker bypass + ask queue.
#
_test_setup_home
_tgt_scenario_cli new src >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_cli new web01 --no-edit >/dev/null
_tgt_scenario_cli new another >/dev/null
set -gx TGT_PICKER_TEST_RESULT src
set -gx TGT_ASK_QUEUE my-clone
_tgt_scenario_cli clone >/dev/null
@test "scenario_cli clone (interactive): picker selected src, queue named my-clone" \
    (_tgt_scenario_exists my-clone; echo $status) -eq 0
@test "scenario_cli clone (interactive): targets carried over from src" \
    (_tgt_target_exists my-clone web01; echo $status) -eq 0
_test_teardown

#
# CLI: rejects clone when src and new name match.
#
_test_setup_home
_tgt_scenario_cli new src >/dev/null
@test "scenario_cli clone: src == new → non-zero" \
    (_tgt_scenario_cli clone src src 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# After clone, switching into the clone applies its DCs to krb5 and
# /etc/hosts (not by clone itself, but by the regular switch flow).
#
_test_setup_home
_tgt_scenario_cli new src >/dev/null
tgt dc new realdc --domain src.local --kdc-host dc01.src.local --kdc-ip 10.10.10.5 >/dev/null
_tgt_scenario_cli clone dest >/dev/null
_tgt_scenario_cli switch dest >/dev/null
@test "after clone+switch: dest realm in krb5" \
    (cat $TGT_KRB5_FILE | string match -q '*SRC.LOCAL = {*'; echo $status) -eq 0
@test "after clone+switch: dest dc hosts entry present" \
    (cat $TGT_HOSTS_FILE | string match -q '*10.10.10.5*dc01.src.local*tgt:dc:dest:realdc*'; echo $status) -eq 0
_test_teardown
