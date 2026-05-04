source (status dirname)/helpers.fish

#
# Empty record set → non-zero exit.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_cli new web01 --no-edit >/dev/null
@test "ports_pick: empty list returns non-zero" \
    (_tgt_ports_pick dante web01 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# TGT_PICKER_TEST_RESULT bypasses the picker entirely.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_cli new web01 --no-edit >/dev/null
_tgt_ports_add dante web01 445 tcp microsoft-ds ""
set -gx TGT_PICKER_TEST_RESULT "445/tcp"
@test "ports_pick: TEST_RESULT bypass returns the supplied value" \
    (_tgt_ports_pick dante web01) = "445/tcp"
set -e TGT_PICKER_TEST_RESULT
_test_teardown

#
# Numbered fallback (no fzf) returns the keyed port/proto for choice 1.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_cli new web01 --no-edit >/dev/null
_tgt_ports_add dante web01 22 tcp ssh ""
_tgt_ports_add dante web01 445 tcp microsoft-ds ""
set -gx TGT_PICKER_NO_FZF 1
set -gx TGT_PICKER_USE_STDIN 1
@test "ports_pick (numbered fallback): choice 1 returns 22/tcp" \
    (echo 1 | _tgt_ports_pick dante web01) = "22/tcp"
@test "ports_pick (numbered fallback): choice 2 returns 445/tcp" \
    (echo 2 | _tgt_ports_pick dante web01) = "445/tcp"
@test "ports_pick (numbered fallback): out-of-range → non-zero" \
    (echo 9 | _tgt_ports_pick dante web01 2>/dev/null; echo $status) -ne 0
@test "ports_pick (numbered fallback): non-numeric → non-zero" \
    (echo nope | _tgt_ports_pick dante web01 2>/dev/null; echo $status) -ne 0
set -e TGT_PICKER_NO_FZF TGT_PICKER_USE_STDIN
_test_teardown
