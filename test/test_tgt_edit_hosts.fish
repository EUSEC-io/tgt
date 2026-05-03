source (status dirname)/helpers.fish

#
# `tgt edit <alias>`: switches to that target if not currently active.
# Wizard is skipped under TGT_TEST_MODE.
#
_test_setup_home
_test_setup_hosts empty.txt
_tgt_scenario_cli new dante >/dev/null
_tgt_target_cli new web01 >/dev/null
_tgt_target_cli new dc01  >/dev/null
# dc01 is now active. Edit web01 — should switch + return 0.
_tgt_target_cli edit web01 >/dev/null

@test "edit <alias>: switches active target" \
    "$TGT_ACTIVE" = web01
_test_teardown

#
# `tgt edit <alias>` with the alias already active: still returns 0
# (no switch needed in test mode).
#
_test_setup_home
_test_setup_hosts empty.txt
_tgt_scenario_cli new dante >/dev/null
_tgt_target_cli new web01 >/dev/null
set -l rc (_tgt_target_cli edit web01 >/dev/null 2>&1; echo $status)

@test "edit <alias> (already active): returns 0" $rc -eq 0
@test "edit <alias> (already active): TGT_ACTIVE unchanged" \
    "$TGT_ACTIVE" = web01
_test_teardown

#
# `tgt edit` (no args, no active target) errors out.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -l rc2 (_tgt_target_cli edit >/dev/null 2>&1; echo $status)

@test "edit (no active, no arg): non-zero" $rc2 -ne 0
_test_teardown

#
# `tgt edit nonexistent` errors out.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -l rc3 (_tgt_target_cli edit ghost >/dev/null 2>&1; echo $status)

@test "edit (nonexistent alias): non-zero" $rc3 -ne 0
_test_teardown

#
# `tgt hosts` with no active target errors out.
#
_test_setup_workspace
set -l rc4 (_tgt_hosts_cli >/dev/null 2>&1; echo $status)

@test "hosts (no active target): non-zero" $rc4 -ne 0
_test_teardown

#
# `tgt hosts edit` with EDITOR=true round-trips current TGT_HOSTS
# (file unchanged → parse returns the original entries → revoke +
# re-add yields the same list on disk).
#
_test_setup_home
_test_setup_hosts empty.txt
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 10.10.10.5
_tgt_target_cli new web01 --no-edit >/dev/null
set -gx TGT_HOSTS web01.dante.local intranet.dante.local

set -gx EDITOR true
_tgt_hosts_cli edit >/dev/null

@test "hosts edit (no-op editor): TGT_HOSTS preserved (count)" \
    (count $TGT_HOSTS) -eq 2
@test "hosts edit (no-op editor): web01.dante.local kept" \
    (contains web01.dante.local $TGT_HOSTS; echo $status) -eq 0
@test "hosts edit (no-op editor): intranet.dante.local kept" \
    (contains intranet.dante.local $TGT_HOSTS; echo $status) -eq 0
set -e EDITOR
_test_teardown

#
# `tgt new <alias> --no-edit` skips the wizard chain (existing flow).
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -l out (_tgt_target_cli new web01 --no-edit 2>&1 | string collect)

@test "new --no-edit: target activated" "$TGT_ACTIVE" = web01
@test "new --no-edit: hint about running tgt is shown" \
    (string match -rq 'Run.*tgt' -- $out; echo $status) -eq 0
_test_teardown

#
# Completions: `tgt <TAB>` offers edit and hosts.
#
function _names; complete -C $argv | string replace -r '\t.*$' ''; end
set -l names (_names 'tgt ')
@test "completion: top-level offers edit"  (contains edit  $names; echo $status) -eq 0
@test "completion: top-level offers hosts" (contains hosts $names; echo $status) -eq 0

#
# Completion: `tgt edit <TAB>` lists active scenario's targets.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_target_cli new web01 --no-edit >/dev/null
_tgt_target_cli new dc01  --no-edit >/dev/null
set -l edit_names (_names 'tgt edit ')
@test "completion: tgt edit lists web01" \
    (contains web01 $edit_names; echo $status) -eq 0
@test "completion: tgt edit lists dc01" \
    (contains dc01 $edit_names; echo $status) -eq 0
_test_teardown

#
# Completion: `tgt new -<TAB>` offers --no-edit.
#
set -l new_names (_names 'tgt new -')
@test "completion: tgt new offers --no-edit" \
    (contains -- --no-edit $new_names; echo $status) -eq 0
