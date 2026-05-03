source (status dirname)/helpers.fish

#
# _tgt_workspace_root: default + override.
#
@test "workspace_root: default is ~/Documents/pentest" \
    (_tgt_workspace_root) = $HOME/Documents/pentest

set -gx TGT_WORKSPACE_ROOT /tmp/some/where
@test "workspace_root: honors \$TGT_WORKSPACE_ROOT" \
    (_tgt_workspace_root) = /tmp/some/where
set -e TGT_WORKSPACE_ROOT

#
# _tgt_workspace_layout: default + override + invalid.
#
@test "workspace_layout: default is flat" \
    (_tgt_workspace_layout) = flat

set -gx TGT_WORKSPACE_LAYOUT nested
@test "workspace_layout: nested honored" \
    (_tgt_workspace_layout) = nested

set -gx TGT_WORKSPACE_LAYOUT flat
@test "workspace_layout: flat honored" \
    (_tgt_workspace_layout) = flat

set -gx TGT_WORKSPACE_LAYOUT bogus
@test "workspace_layout: invalid value falls back to flat" \
    (_tgt_workspace_layout) = flat
set -e TGT_WORKSPACE_LAYOUT

#
# _tgt_workspace_autocreate: opt-in via truthy values.
#
@test "autocreate: unset → disabled" \
    (_tgt_workspace_autocreate; echo $status) -ne 0

for v in 1 true yes on TRUE Yes On
    set -gx TGT_WORKSPACE_AUTOCREATE $v
    @test "autocreate: '$v' enables" \
        (_tgt_workspace_autocreate; echo $status) -eq 0
end

for v in 0 false no off random
    set -gx TGT_WORKSPACE_AUTOCREATE $v
    @test "autocreate: '$v' does not enable" \
        (_tgt_workspace_autocreate; echo $status) -ne 0
end
set -e TGT_WORKSPACE_AUTOCREATE

#
# _tgt_workspace_dir: flat ignores target.
#
_test_setup_workspace
@test "dir: flat scenario only" \
    (_tgt_workspace_dir dante) = "$TGT_WORKSPACE_ROOT/dante"
@test "dir: flat ignores target arg" \
    (_tgt_workspace_dir dante web01) = "$TGT_WORKSPACE_ROOT/dante"
_test_teardown

#
# _tgt_workspace_dir: nested differentiates scenario vs target.
#
_test_setup_workspace
set -gx TGT_WORKSPACE_LAYOUT nested
@test "dir: nested scenario root" \
    (_tgt_workspace_dir dante) = "$TGT_WORKSPACE_ROOT/dante"
@test "dir: nested with target" \
    (_tgt_workspace_dir dante web01) = "$TGT_WORKSPACE_ROOT/dante/web01"
_test_teardown

#
# _tgt_workspace_create: flat layout produces scenario-level subfolders.
#
_test_setup_workspace
_tgt_workspace_create dante
set -l d $TGT_WORKSPACE_ROOT/dante
@test "create flat: scenario dir exists" -d $d
@test "create flat: scans/ exists"        -d "$d/scans"
@test "create flat: loot/ exists"         -d "$d/loot"
@test "create flat: exploits/ exists"     -d "$d/exploits"
@test "create flat: screenshots/ exists"  -d "$d/screenshots"
@test "create flat: notes.md exists"      -e "$d/notes.md"
@test "create flat: no _report/ at scenario level" \
    ! -d "$d/_report"
_test_teardown

#
# _tgt_workspace_create: idempotent (running twice is safe).
#
_test_setup_workspace
_tgt_workspace_create dante
echo "user data" > $TGT_WORKSPACE_ROOT/dante/notes.md
_tgt_workspace_create dante
@test "create flat: idempotent — preserves user-edited notes.md" \
    (cat $TGT_WORKSPACE_ROOT/dante/notes.md) = "user data"
_test_teardown

#
# _tgt_workspace_create: nested without target only creates scenario-level.
#
_test_setup_workspace
set -gx TGT_WORKSPACE_LAYOUT nested
_tgt_workspace_create dante
set -l d $TGT_WORKSPACE_ROOT/dante
@test "create nested (no target): _report/findings exists"     -d "$d/_report/findings"
@test "create nested (no target): _report/screenshots exists"  -d "$d/_report/screenshots"
@test "create nested (no target): _engagement.md exists"       -e "$d/_engagement.md"
@test "create nested (no target): no scans/ at scenario level" \
    ! -d "$d/scans"
_test_teardown

#
# _tgt_workspace_create: nested with target creates per-target subfolders.
#
_test_setup_workspace
set -gx TGT_WORKSPACE_LAYOUT nested
_tgt_workspace_create dante web01
set -l t $TGT_WORKSPACE_ROOT/dante/web01
@test "create nested (target): target dir exists"          -d $t
@test "create nested (target): scans/ exists"              -d "$t/scans"
@test "create nested (target): loot/ exists"               -d "$t/loot"
@test "create nested (target): exploits/ exists"           -d "$t/exploits"
@test "create nested (target): screenshots/ exists"        -d "$t/screenshots"
@test "create nested (target): notes.md exists"            -e "$t/notes.md"
@test "create nested (target): scenario _report kept too"  -d "$TGT_WORKSPACE_ROOT/dante/_report/findings"
_test_teardown

#
# Hook: `tgt scenario new` with autocreate enabled creates the dir.
#
_test_setup_home
_test_setup_workspace
set -gx TGT_WORKSPACE_AUTOCREATE 1
_tgt_scenario_cli new dante >/dev/null
@test "scenario new (autocreate=on): scenario dir created" \
    -d "$TGT_WORKSPACE_ROOT/dante"
@test "scenario new (autocreate=on): scans/ created (flat layout)" \
    -d "$TGT_WORKSPACE_ROOT/dante/scans"
_test_teardown

#
# Hook: without autocreate, `tgt scenario new` does NOT create the dir.
#
_test_setup_home
_test_setup_workspace
_tgt_scenario_cli new dante >/dev/null
@test "scenario new (autocreate=off): scenario dir NOT created" \
    ! -d "$TGT_WORKSPACE_ROOT/dante"
_test_teardown

#
# Hook: `tgt new <alias>` with autocreate + nested creates target subdir.
#
_test_setup_home
_test_setup_workspace
set -gx TGT_WORKSPACE_AUTOCREATE 1
set -gx TGT_WORKSPACE_LAYOUT nested
_tgt_scenario_cli new dante >/dev/null
_tgt_target_cli new web01 >/dev/null
@test "target new (nested + autocreate): target dir created" \
    -d "$TGT_WORKSPACE_ROOT/dante/web01"
@test "target new (nested + autocreate): scans/ created" \
    -d "$TGT_WORKSPACE_ROOT/dante/web01/scans"
_test_teardown

#
# tgt path: requires active scenario.
#
_test_setup_workspace
set -l rc (_tgt_workspace_cli path 2>/dev/null; echo $status)
@test "path: errors when no active scenario" $rc -ne 0
_test_teardown

#
# tgt path: returns scenario dir in flat layout.
#
_test_setup_home
_test_setup_workspace
_tgt_scenario_cli new dante >/dev/null
mkdir -p $TGT_WORKSPACE_ROOT/dante
@test "path (flat, no target): returns scenario dir" \
    (_tgt_workspace_cli path) = "$TGT_WORKSPACE_ROOT/dante"
_test_teardown

#
# tgt path: in nested with active target, returns target dir.
#
_test_setup_home
_test_setup_workspace
set -gx TGT_WORKSPACE_LAYOUT nested
_tgt_scenario_cli new dante >/dev/null
mkdir -p $TGT_WORKSPACE_ROOT/dante/web01
set -gx TGT_ACTIVE web01
@test "path (nested, active target): returns target dir" \
    (_tgt_workspace_cli path) = "$TGT_WORKSPACE_ROOT/dante/web01"
@test "path --scenario: returns scenario dir even when target active" \
    (_tgt_workspace_cli path --scenario) = "$TGT_WORKSPACE_ROOT/dante"
_test_teardown

#
# tgt path: positional alias overrides active target (nested).
#
_test_setup_home
_test_setup_workspace
set -gx TGT_WORKSPACE_LAYOUT nested
_tgt_scenario_cli new dante >/dev/null
mkdir -p $TGT_WORKSPACE_ROOT/dante/dc01
set -gx TGT_ACTIVE web01
@test "path (nested, alias arg): overrides active" \
    (_tgt_workspace_cli path dc01) = "$TGT_WORKSPACE_ROOT/dante/dc01"
_test_teardown

#
# tgt cd: cd-s into the resolved dir.
#
_test_setup_home
_test_setup_workspace
_tgt_scenario_cli new dante >/dev/null
mkdir -p $TGT_WORKSPACE_ROOT/dante
set -l before $PWD
_tgt_workspace_cli cd
@test "cd: pwd is now scenario dir" \
    "$PWD" = "$TGT_WORKSPACE_ROOT/dante"
cd $before
_test_teardown

#
# tgt cd: missing dir → error, pwd unchanged.
#
_test_setup_home
_test_setup_workspace
_tgt_scenario_cli new dante >/dev/null
set -l before $PWD
set -l rc (_tgt_workspace_cli cd 2>/dev/null; echo $status)
@test "cd (no dir): returns non-zero" $rc -ne 0
@test "cd (no dir): pwd unchanged" "$PWD" = "$before"
_test_teardown

#
# tgt scenario rm --purge-workspace removes the folder.
#
_test_setup_home
_test_setup_workspace
_test_setup_hosts empty.txt
set -gx TGT_WORKSPACE_AUTOCREATE 1
_tgt_scenario_cli new dante >/dev/null
_tgt_scenario_cli rm dante --purge-workspace >/dev/null
@test "scenario rm --purge: dir removed" \
    ! -d "$TGT_WORKSPACE_ROOT/dante"
_test_teardown

#
# tgt scenario rm WITHOUT --purge-workspace leaves the folder.
#
_test_setup_home
_test_setup_workspace
_test_setup_hosts empty.txt
set -gx TGT_WORKSPACE_AUTOCREATE 1
_tgt_scenario_cli new dante >/dev/null
_tgt_scenario_cli rm dante >/dev/null
@test "scenario rm (no purge): dir preserved" \
    -d "$TGT_WORKSPACE_ROOT/dante"
_test_teardown

#
# tgt rm --purge-workspace (nested) removes the target dir.
#
_test_setup_home
_test_setup_workspace
_test_setup_hosts empty.txt
set -gx TGT_WORKSPACE_AUTOCREATE 1
set -gx TGT_WORKSPACE_LAYOUT nested
_tgt_scenario_cli new dante >/dev/null
_tgt_target_cli new web01 >/dev/null
_tgt_target_cli rm web01 --purge-workspace >/dev/null
@test "target rm --purge (nested): target dir removed" \
    ! -d "$TGT_WORKSPACE_ROOT/dante/web01"
@test "target rm --purge (nested): scenario dir preserved" \
    -d "$TGT_WORKSPACE_ROOT/dante"
_test_teardown

#
# tgt rm --purge-workspace (flat) is a no-op (with a notice on stdout).
#
_test_setup_home
_test_setup_workspace
_test_setup_hosts empty.txt
set -gx TGT_WORKSPACE_AUTOCREATE 1
_tgt_scenario_cli new dante >/dev/null
_tgt_target_cli new web01 >/dev/null
set -l out (_tgt_target_cli rm web01 --purge-workspace 2>&1 | string collect)
@test "target rm --purge (flat): scenario dir preserved" \
    -d "$TGT_WORKSPACE_ROOT/dante"
@test "target rm --purge (flat): notes that flat has no per-target folder" \
    (string match -rq 'flat' -- $out; echo $status) -eq 0
_test_teardown

#
# _tgt_workspace_purge: refuses paths outside workspace root (safety).
#
_test_setup_workspace
# Layout that would put the target's path under root → should succeed
mkdir -p $TGT_WORKSPACE_ROOT/dante
_tgt_workspace_purge dante >/dev/null
@test "purge: removes scenario dir under root" \
    ! -d "$TGT_WORKSPACE_ROOT/dante"

# Workspace root itself must never be removed
mkdir -p $TGT_WORKSPACE_ROOT/keep
set -l rc2 (_tgt_workspace_purge "" 2>/dev/null; echo $status)
@test "purge: empty scenario name → non-zero" $rc2 -ne 0
@test "purge: workspace root preserved when scenario empty" \
    -d "$TGT_WORKSPACE_ROOT/keep"
_test_teardown
