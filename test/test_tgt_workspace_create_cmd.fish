source (status dirname)/helpers.fish

#
# `tgt workspace create` (no active target): builds scenario root + scenario template.
#
_test_setup_home
_test_setup_workspace
_tgt_scenario_cli new dante >/dev/null
_tgt_workspace_cli workspace create >/dev/null

@test "workspace create (no target, flat): scenario dir exists" \
    -d "$TGT_WORKSPACE_ROOT/dante"
@test "workspace create (no target, flat): scans/ created (default template)" \
    -d "$TGT_WORKSPACE_ROOT/dante/scans"
_test_teardown

#
# `tgt workspace create` with an active target (nested): builds the
# target dir alongside the scenario tree.
#
_test_setup_home
_test_setup_workspace
set -gx TGT_WORKSPACE_LAYOUT nested
_tgt_scenario_cli new dante >/dev/null
_tgt_target_cli new web01 --no-edit >/dev/null
_tgt_workspace_cli workspace create >/dev/null

@test "workspace create (active target, nested): target dir exists" \
    -d "$TGT_WORKSPACE_ROOT/dante/web01"
@test "workspace create (active target, nested): target scans/ exists" \
    -d "$TGT_WORKSPACE_ROOT/dante/web01/scans"
_test_teardown

#
# `tgt workspace create <alias>`: explicit alias overrides active.
#
_test_setup_home
_test_setup_workspace
set -gx TGT_WORKSPACE_LAYOUT nested
_tgt_scenario_cli new dante >/dev/null
_tgt_target_cli new web01 --no-edit >/dev/null
_tgt_target_cli new dc01  --no-edit >/dev/null
_tgt_workspace_cli workspace create web01 >/dev/null

@test "workspace create <alias>: web01 dir exists" \
    -d "$TGT_WORKSPACE_ROOT/dante/web01"
_test_teardown

#
# `tgt workspace create` works even when autocreate is disabled —
# this is the manual escape hatch.
#
_test_setup_home
_test_setup_workspace
# Autocreate intentionally NOT set
_tgt_scenario_cli new dante >/dev/null
@test "scenario new (autocreate=off): folder NOT auto-created" \
    ! -d "$TGT_WORKSPACE_ROOT/dante"
_tgt_workspace_cli workspace create >/dev/null
@test "workspace create (manual, autocreate=off): folder created" \
    -d "$TGT_WORKSPACE_ROOT/dante"
_test_teardown

#
# `tgt workspace create` errors when no active scenario.
#
_test_setup_workspace
set -l rc (_tgt_workspace_cli workspace create 2>/dev/null; echo $status)
@test "workspace create (no scenario): non-zero" $rc -ne 0
_test_teardown

#
# `tgt workspace bogus` errors out.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -l rc2 (_tgt_workspace_cli workspace bogus 2>/dev/null; echo $status)
@test "workspace (bogus verb): non-zero" $rc2 -ne 0
_test_teardown

#
# Completion: `tgt workspace <TAB>` offers create.
#
function _names; complete -C $argv | string replace -r '\t.*$' ''; end
set -l ws_names (_names 'tgt workspace ')
@test "completion: tgt workspace offers create" \
    (contains create $ws_names; echo $status) -eq 0
