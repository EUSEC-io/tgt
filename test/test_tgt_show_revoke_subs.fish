source (status dirname)/helpers.fish

#
# `tgt show` mirrors `tgt --show`: prints the same env summary
# block. We don't snapshot the entire output (color codes drift),
# but the recognizable rows must appear.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 10.10.10.5
_tgt_target_cli new web01 --no-edit >/dev/null

set -l out_subcmd (tgt show 2>&1 | string collect)
set -l out_flag   (tgt --show 2>&1 | string collect)

@test "tgt show: prints TGT row" \
    (string match -q '*TGT*=*10.10.10.5*' -- $out_subcmd; echo $status) -eq 0
@test "tgt show: equivalent output to tgt --show" \
    "$out_subcmd" = "$out_flag"
_test_teardown

#
# `tgt revoke` mirrors `tgt --revoke`: clears the runtime state.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 10.10.10.5
_tgt_target_cli new web01 --no-edit >/dev/null
tgt revoke >/dev/null
@test "tgt revoke: TGT cleared" \
    (set -q TGT; echo $status) -ne 0
@test "tgt revoke: TGT_ACTIVE cleared (target deselected)" \
    (set -q TGT_ACTIVE; echo $status) -ne 0
@test "tgt revoke: TGT_SCENARIO kept" \
    "$TGT_SCENARIO" = dante
_test_teardown

#
# `tgt revoke` (no creds, no host) is a clean no-op + zero exit.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
@test "tgt revoke (clean): exit 0" \
    (tgt revoke >/dev/null 2>&1; echo $status) -eq 0
_test_teardown

#
# `tgt` with no args in test mode falls through to help (no wizard).
# It must not silently drop into edit mode the way the v1 surface did.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_cli new web01 --no-edit >/dev/null
# Capture help output. With TGT_TEST_MODE set, the picker is gated
# off so we get help text.
set -l out (tgt 2>&1 | string collect)
@test "tgt (no args, test mode): emits help" \
    (string match -q '*tgt — target environment manager*' -- $out; echo $status) -eq 0
@test "tgt (no args, test mode): does NOT run the wizard" \
    (string match -q '*interactive target setup*' -- $out; echo $status) -ne 0
_test_teardown
