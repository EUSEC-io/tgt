source (status dirname)/helpers.fish

#
# `tgt config reset` clears all workspace globals (and the config
# file if it exists). _test_setup_home gives a tmp $TGT_HOME so the
# config file path resolves into the tmp dir, not the user's real
# ~/.config/fish/tgt/config.fish.
#
_test_setup_home
set -gx TGT_WORKSPACE_ROOT /tmp/foo
set -gx TGT_WORKSPACE_LAYOUT nested
set -gx TGT_WORKSPACE_AUTOCREATE 1
set -gx TGT_WORKSPACE_TARGET_TEMPLATE a/ b
set -gx TGT_WORKSPACE_SCENARIO_TEMPLATE c/ d

_tgt_config_cli reset >/dev/null

@test "config reset: TGT_WORKSPACE_ROOT cleared" \
    (set -q TGT_WORKSPACE_ROOT; echo $status) -ne 0
@test "config reset: TGT_WORKSPACE_LAYOUT cleared" \
    (set -q TGT_WORKSPACE_LAYOUT; echo $status) -ne 0
@test "config reset: TGT_WORKSPACE_AUTOCREATE cleared" \
    (set -q TGT_WORKSPACE_AUTOCREATE; echo $status) -ne 0
@test "config reset: TGT_WORKSPACE_TARGET_TEMPLATE cleared" \
    (set -q TGT_WORKSPACE_TARGET_TEMPLATE; echo $status) -ne 0
@test "config reset: TGT_WORKSPACE_SCENARIO_TEMPLATE cleared" \
    (set -q TGT_WORKSPACE_SCENARIO_TEMPLATE; echo $status) -ne 0
_test_teardown

#
# `tgt config reset` is safe when nothing is set.
#
_test_setup_home
set -l rc (_tgt_config_cli reset >/dev/null 2>&1; echo $status)
@test "config reset (empty): exits 0" $rc -eq 0
_test_teardown

#
# `tgt config show` emits the same output as `tgt workspace`.
#
_test_setup_home
set -l show_out  (_tgt_config_cli show 2>&1 | string collect)
@test "config show: mentions 'tgt workspace' header" \
    (string match -rq 'tgt workspace' -- $show_out; echo $status) -eq 0
_test_teardown

#
# `tgt config bogus` errors and points to --help.
#
_test_setup_home
set -l rc2 (_tgt_config_cli bogus >/dev/null 2>&1; echo $status)
@test "config (bogus verb): non-zero exit" $rc2 -ne 0
_test_teardown

#
# `tgt config --help` exits 0.
#
_test_setup_home
set -l rc3 (_tgt_config_cli --help >/dev/null 2>&1; echo $status)
@test "config --help: exits 0" $rc3 -eq 0
_test_teardown

#
# _tgt_ask_multiline: when EDITOR is a no-op (true), input list
# round-trips through the parser (skipping comments and blanks).
#
set -gx EDITOR true
set -gx TGT_TEST_MODE 1
set -l parsed (_tgt_ask_multiline "label" alpha/ beta gamma/sub/ 2>/dev/null)
@test "ask_multiline (no-op editor): 3 entries round-trip" \
    (count $parsed) -eq 3
@test "ask_multiline (no-op editor): contains alpha/" \
    (contains alpha/ $parsed; echo $status) -eq 0
@test "ask_multiline (no-op editor): contains beta" \
    (contains beta $parsed; echo $status) -eq 0
@test "ask_multiline (no-op editor): contains gamma/sub/" \
    (contains gamma/sub/ $parsed; echo $status) -eq 0
set -e EDITOR
_test_teardown

#
# Completions: `tgt config <TAB>` offers edit/show/reset.
#
function _names; complete -C $argv | string replace -r '\t.*$' ''; end
set -l cfg_names (_names 'tgt config ')
@test "completion: config offers edit"  (contains edit  $cfg_names; echo $status) -eq 0
@test "completion: config offers show"  (contains show  $cfg_names; echo $status) -eq 0
@test "completion: config offers reset" (contains reset $cfg_names; echo $status) -eq 0
