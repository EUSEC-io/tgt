source (status dirname)/helpers.fish

#
# _tgt_target_inspect: minimal target (TGT only) → defaults for the rest.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 10.10.10.5
_tgt_target_save dante minimal
set -e TGT
set -l line (_tgt_target_inspect dante minimal)
set -l fields (string split \t -- $line)

@test "inspect minimal: alias is first field" \
    "$fields[1]" = minimal
@test "inspect minimal: host is TGT (no port)" \
    "$fields[2]" = "10.10.10.5"
@test "inspect minimal: creds = N" \
    "$fields[3]" = N
@test "inspect minimal: AD = N" \
    "$fields[4]" = N
@test "inspect minimal: hosts count = 0" \
    "$fields[5]" = 0
_test_teardown

#
# _tgt_target_inspect: fully-loaded target (TGT + creds + AD + hosts).
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 10.10.10.10
set -gx TGT_USERNAME admin
set -gx TGT_PASSWORD secret
set -gx TGT_AD_DOMAIN dante.local
set -gx TGT_HOSTS dc01.dante.local dc01
_tgt_target_save dante dc01
set -e TGT TGT_USERNAME TGT_PASSWORD TGT_AD_DOMAIN TGT_HOSTS
set -l line (_tgt_target_inspect dante dc01)
set -l fields (string split \t -- $line)

@test "inspect full: host is TGT" \
    "$fields[2]" = "10.10.10.10"
@test "inspect full: creds = Y" \
    "$fields[3]" = Y
@test "inspect full: AD = Y" \
    "$fields[4]" = Y
@test "inspect full: hosts count = 2" \
    "$fields[5]" = 2
_test_teardown

#
# _tgt_target_inspect: returns non-zero for missing target file.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -l rc (_tgt_target_inspect dante ghost >/dev/null 2>&1; echo $status)
@test "inspect: missing file → non-zero" $rc -ne 0
_test_teardown

#
# _tgt_scenario_show: empty scenario notes "no targets yet".
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -l out (_tgt_scenario_cli show 2>&1 | string collect)
@test "show (empty scenario): mentions no targets" \
    (string match -rq 'no targets yet' -- $out; echo $status) -eq 0
_test_teardown

#
# _tgt_scenario_show: lists each target, marks the active one.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_cli new web01 --no-edit >/dev/null
set -gx TGT 2.2.2.2
_tgt_target_cli new dc01 --no-edit >/dev/null
# dc01 is active (most recent new). web01 should NOT be marked.
set -l out (_tgt_scenario_cli show 2>&1 | string collect)

@test "show (with targets): lists web01" \
    (string match -rq 'web01' -- $out; echo $status) -eq 0
@test "show (with targets): lists dc01" \
    (string match -rq 'dc01' -- $out; echo $status) -eq 0
@test "show (with targets): mentions targets count" \
    (string match -rq 'targets \(2\)' -- $out; echo $status) -eq 0
_test_teardown

#
# _tgt_scenario_show on a non-active scenario: no row gets the *
# marker (because TGT_ACTIVE belongs to another scenario, if any).
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_cli new web01 --no-edit >/dev/null
_tgt_scenario_cli new acme >/dev/null
# Now active scenario is acme, but we're showing dante.
set -l out (_tgt_scenario_cli show dante 2>&1 | string collect)
@test "show (other scenario): active=no in header" \
    (string match -rq 'active:\s+no' -- $out; echo $status) -eq 0
_test_teardown
