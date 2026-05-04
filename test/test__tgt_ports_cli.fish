source (status dirname)/helpers.fish

#
# tgt ports: errors when no active target.
#
_test_setup_home
@test "ports_cli: errors when no scenario active" \
    (_tgt_ports_cli list 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# tgt ports: errors when scenario active but no target selected.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
@test "ports_cli: errors when no target active" \
    (_tgt_ports_cli list 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# tgt ports list: empty target → friendly note.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_cli new web01 --no-edit >/dev/null
set -l out (_tgt_ports_cli list 2>&1 | string collect)
@test "ports_cli list: empty → 'no ports recorded' note" \
    (string match -q '*no ports recorded*' -- $out; echo $status) -eq 0
_test_teardown

#
# tgt ports add <port>[/proto] [service] [comment]: manual upsert.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_cli new web01 --no-edit >/dev/null
_tgt_ports_cli add 445/tcp microsoft-ds "SMB" >/dev/null
_tgt_ports_cli add 22 ssh >/dev/null     # default proto = tcp
set -l recs (_tgt_ports_list dante web01)
@test "ports_cli add: 2 records after manual add" (count $recs) -eq 2
@test "ports_cli add: 22 defaulted to tcp" \
    (string match -q '22*tcp*ssh*' -- $recs[1]; echo $status) -eq 0
@test "ports_cli add: 445/tcp service+comment captured" \
    (string match -q '*445*microsoft-ds*SMB*' -- $recs[2]; echo $status) -eq 0
_test_teardown

#
# tgt ports add <file>: imports gnmap.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_cli new web01 --no-edit >/dev/null
_tgt_ports_cli add $_test_dir/fixtures/nmap/multihost.gnmap >/dev/null
@test "ports_cli add (file): imported records present" \
    (count (_tgt_ports_list dante web01)) -eq 4
_test_teardown

#
# tgt ports add: rejects bad spec.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_cli new web01 --no-edit >/dev/null
@test "ports_cli add: bogus port → non-zero" \
    (_tgt_ports_cli add abc/tcp 2>/dev/null; echo $status) -ne 0
@test "ports_cli add: bogus proto → non-zero" \
    (_tgt_ports_cli add 80/sctp 2>/dev/null; echo $status) -ne 0
@test "ports_cli add: missing arg → non-zero" \
    (_tgt_ports_cli add 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# tgt ports rm: drops record by spec.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_cli new web01 --no-edit >/dev/null
_tgt_ports_cli add 22/tcp ssh >/dev/null
_tgt_ports_cli add 80/tcp http >/dev/null
_tgt_ports_cli rm 80/tcp >/dev/null
@test "ports_cli rm: 1 record left" \
    (count (_tgt_ports_list dante web01)) -eq 1
@test "ports_cli rm: bare port defaults to tcp" \
    (_tgt_ports_cli rm 22 >/dev/null; echo $status) -eq 0
@test "ports_cli rm: 0 records left" \
    (count (_tgt_ports_list dante web01)) -eq 0
_test_teardown

#
# tgt ports clear: wipes everything.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_cli new web01 --no-edit >/dev/null
_tgt_ports_cli add 22/tcp ssh >/dev/null
_tgt_ports_cli add 80/tcp http >/dev/null
_tgt_ports_cli clear >/dev/null
@test "ports_cli clear: 0 records left" \
    (count (_tgt_ports_list dante web01)) -eq 0
_test_teardown

#
# tgt ports comment: replaces comment, errors if record missing.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_cli new web01 --no-edit >/dev/null
_tgt_ports_cli add 445/tcp microsoft-ds "old" >/dev/null
_tgt_ports_cli comment 445/tcp "new comment text" >/dev/null
set -l line (_tgt_ports_list dante web01)
set -l fields (string split \t -- $line)
@test "ports_cli comment: replaced text" \
    "$fields[4]" = "new comment text"
@test "ports_cli comment: missing record → non-zero" \
    (_tgt_ports_cli comment 999/tcp "x" 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# tgt ports (no args): runs picker and exports TGT_PORT.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_cli new web01 --no-edit >/dev/null
_tgt_ports_cli add 22/tcp ssh >/dev/null
_tgt_ports_cli add 445/tcp microsoft-ds >/dev/null
set -gx TGT_PICKER_TEST_RESULT "445/tcp"
_tgt_ports_cli >/dev/null
@test "ports_cli (no args): TGT_PORT exported as bare number" \
    "$TGT_PORT" = 445
set -e TGT_PICKER_TEST_RESULT
_test_teardown

#
# Unknown verb is rejected (no silent fallthrough).
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_cli new web01 --no-edit >/dev/null
@test "ports_cli: unknown verb returns non-zero" \
    (_tgt_ports_cli garbage 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# Top-level dispatch: `tgt ports …` reaches _tgt_ports_cli.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_cli new web01 --no-edit >/dev/null
tgt ports add 22/tcp ssh >/dev/null
@test "top-level: 'tgt ports add' adds via dispatcher" \
    (count (_tgt_ports_list dante web01)) -eq 1
_test_teardown
