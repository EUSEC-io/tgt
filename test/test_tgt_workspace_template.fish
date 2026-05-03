source (status dirname)/helpers.fish

#
# Defaults match the previously hardcoded set.
#
set -l target_default (_tgt_workspace_target_template)
@test "target template default: contains scans/" \
    (contains scans/ $target_default; echo $status) -eq 0
@test "target template default: contains loot/" \
    (contains loot/ $target_default; echo $status) -eq 0
@test "target template default: contains notes.md" \
    (contains notes.md $target_default; echo $status) -eq 0

set -l scenario_default (_tgt_workspace_scenario_template)
@test "scenario template default: contains _report/findings/" \
    (contains _report/findings/ $scenario_default; echo $status) -eq 0
@test "scenario template default: contains _engagement.md" \
    (contains _engagement.md $scenario_default; echo $status) -eq 0

#
# Override via env var. List values become per-line entries.
#
set -gx TGT_WORKSPACE_TARGET_TEMPLATE custom1/ custom2.txt
set -l overridden (_tgt_workspace_target_template)
@test "target template override: 2 entries" \
    (count $overridden) -eq 2
@test "target template override: includes custom1/" \
    (contains custom1/ $overridden; echo $status) -eq 0
@test "target template override: includes custom2.txt" \
    (contains custom2.txt $overridden; echo $status) -eq 0
set -e TGT_WORKSPACE_TARGET_TEMPLATE

#
# _tgt_workspace_apply_template: trailing-slash → dir, else file.
#
set -l base (mktemp -d)
_tgt_workspace_apply_template $base alpha/ beta.md gamma/sub/
@test "apply: alpha is a dir"          -d "$base/alpha"
@test "apply: beta.md is a file"       -f "$base/beta.md"
@test "apply: nested gamma/sub is dir" -d "$base/gamma/sub"
rm -rf $base

#
# _tgt_workspace_apply_template: nested file paths get parent dirs created.
#
set -l base2 (mktemp -d)
_tgt_workspace_apply_template $base2 deep/down/file.txt
@test "apply: parent of deep file exists" -d "$base2/deep/down"
@test "apply: deep file exists"           -f "$base2/deep/down/file.txt"
rm -rf $base2

#
# Custom templates flow into _tgt_workspace_create (flat layout).
#
_test_setup_workspace
set -gx TGT_WORKSPACE_TARGET_TEMPLATE recon/ creds.txt
_tgt_workspace_create dante
@test "create flat (custom): recon/ exists" \
    -d "$TGT_WORKSPACE_ROOT/dante/recon"
@test "create flat (custom): creds.txt exists" \
    -f "$TGT_WORKSPACE_ROOT/dante/creds.txt"
@test "create flat (custom): default scans/ NOT created" \
    ! -d "$TGT_WORKSPACE_ROOT/dante/scans"
_test_teardown

#
# Custom templates flow into _tgt_workspace_create (nested layout):
# scenario_template at scenario level + target_template at target level.
#
_test_setup_workspace
set -gx TGT_WORKSPACE_LAYOUT nested
set -gx TGT_WORKSPACE_TARGET_TEMPLATE recon/ creds.txt
set -gx TGT_WORKSPACE_SCENARIO_TEMPLATE timeline.md
_tgt_workspace_create dante web01
@test "create nested (custom): scenario timeline.md present" \
    -f "$TGT_WORKSPACE_ROOT/dante/timeline.md"
@test "create nested (custom): scenario default _report NOT present" \
    ! -d "$TGT_WORKSPACE_ROOT/dante/_report"
@test "create nested (custom): target recon/ present" \
    -d "$TGT_WORKSPACE_ROOT/dante/web01/recon"
@test "create nested (custom): target creds.txt present" \
    -f "$TGT_WORKSPACE_ROOT/dante/web01/creds.txt"
_test_teardown
