source (status dirname)/helpers.fish

#
# No active scenario → empty (caller stays in CWD).
#
@test "ingest_output_dir: empty when no scenario active" \
    (_tgt_ingest_output_dir | count) -eq 0

#
# Scenario set, but workspace dir doesn't exist → empty (don't
# auto-route into a directory that hasn't been created yet).
#
_test_setup_workspace
set -gx TGT_SCENARIO dante
@test "ingest_output_dir: empty when workspace dir missing" \
    (_tgt_ingest_output_dir | count) -eq 0
_test_teardown

#
# Flat: scenario dir exists → routes to <scenario>/loot.
#
_test_setup_workspace
set -gx TGT_SCENARIO dante
mkdir -p $TGT_WORKSPACE_ROOT/dante
@test "ingest_output_dir: flat routes to scenario/loot" \
    (_tgt_ingest_output_dir) = "$TGT_WORKSPACE_ROOT/dante/loot"
_test_teardown

#
# Nested: scenario + target, target dir exists → routes to
# <scenario>/<target>/loot.
#
_test_setup_workspace
set -gx TGT_WORKSPACE_LAYOUT nested
set -gx TGT_SCENARIO dante
set -gx TGT_ACTIVE web01
mkdir -p $TGT_WORKSPACE_ROOT/dante/web01
@test "ingest_output_dir: nested + target routes to target/loot" \
    (_tgt_ingest_output_dir) = "$TGT_WORKSPACE_ROOT/dante/web01/loot"
_test_teardown

#
# Nested: scenario only (no active target), scenario dir exists →
# routes to scenario/loot (same path the flat layout would produce).
#
_test_setup_workspace
set -gx TGT_WORKSPACE_LAYOUT nested
set -gx TGT_SCENARIO dante
mkdir -p $TGT_WORKSPACE_ROOT/dante
@test "ingest_output_dir: nested + no target routes to scenario/loot" \
    (_tgt_ingest_output_dir) = "$TGT_WORKSPACE_ROOT/dante/loot"
_test_teardown
