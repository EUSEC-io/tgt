source (status dirname)/helpers.fish

#
# Validators: port range and proto whitelist.
#
@test "validate_port: 80 ok" \
    (_tgt_ports_validate_port 80; echo $status) -eq 0
@test "validate_port: 1 ok (low edge)" \
    (_tgt_ports_validate_port 1; echo $status) -eq 0
@test "validate_port: 65535 ok (high edge)" \
    (_tgt_ports_validate_port 65535; echo $status) -eq 0
@test "validate_port: 0 rejected" \
    (_tgt_ports_validate_port 0; echo $status) -ne 0
@test "validate_port: 65536 rejected" \
    (_tgt_ports_validate_port 65536; echo $status) -ne 0
@test "validate_port: empty rejected" \
    (_tgt_ports_validate_port ""; echo $status) -ne 0
@test "validate_port: non-numeric rejected" \
    (_tgt_ports_validate_port abc; echo $status) -ne 0
@test "validate_proto: tcp ok" \
    (_tgt_ports_validate_proto tcp; echo $status) -eq 0
@test "validate_proto: udp ok" \
    (_tgt_ports_validate_proto udp; echo $status) -eq 0
@test "validate_proto: TCP (uppercase) rejected" \
    (_tgt_ports_validate_proto TCP; echo $status) -ne 0
@test "validate_proto: empty rejected" \
    (_tgt_ports_validate_proto ""; echo $status) -ne 0
@test "validate_proto: garbage rejected" \
    (_tgt_ports_validate_proto sctp; echo $status) -ne 0

#
# file: composes the right path.
#
_test_setup_home
@test "ports_file: sits next to <target>.fish" \
    (_tgt_ports_file dante web01) = "$TGT_HOME/scenarios/dante/targets/web01.ports"
_test_teardown

#
# list: empty / no file → no output, exit 0.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_save dante web01
@test "ports_list: empty (no file) → exit 0, no output" \
    (_tgt_ports_list dante web01 | count) -eq 0
@test "ports_list: empty (no file) → exit 0" \
    (_tgt_ports_list dante web01 >/dev/null; echo $status) -eq 0
_test_teardown

#
# add: creates file, formats record correctly, sorts by port (numeric).
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_save dante web01
_tgt_ports_add dante web01 445 tcp microsoft-ds "SMB"
_tgt_ports_add dante web01 80 tcp http "main webapp"
_tgt_ports_add dante web01 3389 tcp ms-wbt-server ""
set -l lines (_tgt_ports_list dante web01)
@test "ports_add: 3 records present" (count $lines) -eq 3
@test "ports_add: sorted numerically (80 first)" \
    (string match -rq '^80\ttcp' -- $lines[1]; echo $status) -eq 0
@test "ports_add: 445 second" \
    (string match -rq '^445\ttcp' -- $lines[2]; echo $status) -eq 0
@test "ports_add: 3389 last" \
    (string match -rq '^3389\ttcp' -- $lines[3]; echo $status) -eq 0
@test "ports_add: service field present" \
    (string match -q '*microsoft-ds*' -- $lines[2]; echo $status) -eq 0
@test "ports_add: comment field present" \
    (string match -q '*SMB*' -- $lines[2]; echo $status) -eq 0
_test_teardown

#
# add: tab-separated fields exactly (4 columns even when comment empty).
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_save dante web01
_tgt_ports_add dante web01 22 tcp ssh
set -l line (_tgt_ports_list dante web01)
set -l fields (string split \t -- $line)
@test "ports_add: 4 tab-separated fields (incl. trailing empty)" \
    (count $fields) -eq 4
@test "ports_add: field[1] is port" "$fields[1]" = 22
@test "ports_add: field[2] is proto" "$fields[2]" = tcp
@test "ports_add: field[3] is service" "$fields[3]" = ssh
@test "ports_add: field[4] is empty comment" "$fields[4]" = ""
_test_teardown

#
# add: same port+proto upserts (replaces service/comment, no duplicate).
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_save dante web01
_tgt_ports_add dante web01 80 tcp http "first"
_tgt_ports_add dante web01 80 tcp nginx "updated"
set -l lines (_tgt_ports_list dante web01)
@test "ports_add: upsert keeps single record" (count $lines) -eq 1
@test "ports_add: upsert replaced service" \
    (string match -q '*nginx*' -- $lines[1]; echo $status) -eq 0
@test "ports_add: upsert replaced comment" \
    (string match -q '*updated*' -- $lines[1]; echo $status) -eq 0
@test "ports_add: upsert dropped old service" \
    (string match -q '*http*' -- $lines[1]; echo $status) -ne 0
_test_teardown

#
# add: same port, different proto, both kept (TCP and UDP coexist).
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_save dante web01
_tgt_ports_add dante web01 53 tcp dns ""
_tgt_ports_add dante web01 53 udp dns ""
set -l lines (_tgt_ports_list dante web01)
@test "ports_add: tcp + udp on same port both kept" \
    (count $lines) -eq 2
@test "ports_add: tcp variant present" \
    (string match -q '*53*tcp*' -- $lines[1]; echo $status) -eq 0
@test "ports_add: udp variant present" \
    (string match -q '*53*udp*' -- $lines[2]; echo $status) -eq 0
_test_teardown

#
# add: rejects bad input.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_save dante web01
@test "ports_add: rejects port 0" \
    (_tgt_ports_add dante web01 0 tcp ""; echo $status) -ne 0
@test "ports_add: rejects port 99999" \
    (_tgt_ports_add dante web01 99999 tcp ""; echo $status) -ne 0
@test "ports_add: rejects bogus proto" \
    (_tgt_ports_add dante web01 80 sctp ""; echo $status) -ne 0
@test "ports_add: rejects unknown target" \
    (_tgt_ports_add dante missing 80 tcp ""; echo $status) -ne 0
_test_teardown

#
# remove: drops matching record, leaves siblings.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_save dante web01
_tgt_ports_add dante web01 22 tcp ssh ""
_tgt_ports_add dante web01 80 tcp http ""
_tgt_ports_add dante web01 443 tcp https ""
_tgt_ports_remove dante web01 80 tcp
set -l lines (_tgt_ports_list dante web01)
@test "ports_remove: 2 records left" (count $lines) -eq 2
@test "ports_remove: 22 kept" \
    (string match -q '22*tcp*ssh*' -- $lines[1]; echo $status) -eq 0
@test "ports_remove: 443 kept" \
    (string match -q '443*tcp*https*' -- $lines[2]; echo $status) -eq 0
@test "ports_remove: 80 gone" \
    (string match -q '*80*tcp*http*' -- (_tgt_ports_list dante web01); echo $status) -ne 0
_test_teardown

#
# remove: idempotent (no-op when record absent).
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_save dante web01
_tgt_ports_add dante web01 22 tcp ssh ""
@test "ports_remove: missing record returns 0" \
    (_tgt_ports_remove dante web01 9999 tcp; echo $status) -eq 0
_test_teardown

#
# remove: removes the file when it ends up empty.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_save dante web01
_tgt_ports_add dante web01 22 tcp ssh ""
_tgt_ports_remove dante web01 22 tcp
@test "ports_remove: file removed when last record dropped" \
    (test -f (_tgt_ports_file dante web01); echo $status) -ne 0
_test_teardown

#
# clear: wipes the file.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_save dante web01
_tgt_ports_add dante web01 22 tcp ssh ""
_tgt_ports_add dante web01 80 tcp http ""
_tgt_ports_clear dante web01
@test "ports_clear: file removed" \
    (test -f (_tgt_ports_file dante web01); echo $status) -ne 0
@test "ports_clear: list returns nothing" \
    (_tgt_ports_list dante web01 | count) -eq 0
_test_teardown

#
# clear: idempotent on missing file.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_save dante web01
@test "ports_clear: no file → exit 0" \
    (_tgt_ports_clear dante web01; echo $status) -eq 0
_test_teardown

#
# comment: replaces existing comment, preserves service.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_save dante web01
_tgt_ports_add dante web01 445 tcp microsoft-ds "old"
_tgt_ports_comment dante web01 445 tcp "fresh comment"
set -l line (_tgt_ports_list dante web01)
set -l fields (string split \t -- $line)
@test "ports_comment: service preserved" "$fields[3]" = microsoft-ds
@test "ports_comment: comment replaced" "$fields[4]" = "fresh comment"
_test_teardown

#
# comment: errors when record absent.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_save dante web01
@test "ports_comment: missing record returns non-zero" \
    (_tgt_ports_comment dante web01 999 tcp "x"; echo $status) -ne 0
_test_teardown

#
# Comments containing special chars (spaces, quotes) round-trip.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_save dante web01
_tgt_ports_add dante web01 80 tcp http "hit /admin with 'quotes' & spaces"
set -l line (_tgt_ports_list dante web01)
set -l fields (string split \t -- $line)
@test "ports_add: comment with quotes/spaces preserved" \
    "$fields[4]" = "hit /admin with 'quotes' & spaces"
_test_teardown
