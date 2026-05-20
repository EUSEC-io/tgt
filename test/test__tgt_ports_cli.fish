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

#
# tgt ports unset: clears $TGT_PORT, keeps records.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_cli new web01 --no-edit >/dev/null
_tgt_ports_cli add 445/tcp microsoft-ds >/dev/null
set -gx TGT_PORT 445
_tgt_ports_cli unset >/dev/null
@test "ports_cli unset: TGT_PORT cleared" \
    (set -q TGT_PORT; echo $status) -ne 0
@test "ports_cli unset: records preserved" \
    (count (_tgt_ports_list dante web01)) -eq 1
_test_teardown

#
# tgt ports unset: no-op when TGT_PORT not set (still exit 0).
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_cli new web01 --no-edit >/dev/null
@test "ports_cli unset: no-TGT_PORT case exits 0" \
    (_tgt_ports_cli unset >/dev/null; echo $status) -eq 0
_test_teardown

#
# `--target` flag — operate on a non-active target.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_target_cli new web --no-edit >/dev/null
set -gx TGT 10.0.0.10
_tgt_target_save dante web
_tgt_target_cli new db --no-edit >/dev/null
set -gx TGT 10.0.0.20
_tgt_target_save dante db
_tgt_clear_target_runtime
_tgt_target_cli switch web >/dev/null  # web is the active target

# Add to db (non-active) via --target.
_tgt_ports_cli add --target db 3306 mysql >/dev/null
@test "ports_cli add --target: db file created" \
    (test -f (_tgt_ports_file dante db); echo $status) -eq 0
@test "ports_cli add --target: web file NOT created" \
    (test -f (_tgt_ports_file dante web); echo $status) -ne 0

# Long form --target=alias should also parse.
_tgt_ports_cli add --target=db 5432 postgres >/dev/null
@test "ports_cli add --target=alias: long-form parses" \
    (_tgt_ports_list dante db | string match -q '*postgres*'; echo $status) -eq 0

# Short alias `-t`.
_tgt_ports_cli add -t db 8080 http >/dev/null
@test "ports_cli add -t alias: short form parses" \
    (_tgt_ports_list dante db | string match -q '*8080*'; echo $status) -eq 0

# rm with --target.
_tgt_ports_cli rm --target db 3306 >/dev/null
@test "ports_cli rm --target: record removed from non-active" \
    (_tgt_ports_list dante db | string match -q '*3306*'; echo $status) -ne 0

# comment with --target.
_tgt_ports_cli comment --target db 5432 "main DB" >/dev/null
@test "ports_cli comment --target: comment stored on non-active" \
    (_tgt_ports_list dante db | string match -q '*main DB*'; echo $status) -eq 0

# clear with --target.
_tgt_ports_cli clear --target db >/dev/null
@test "ports_cli clear --target: non-active file removed" \
    (test -f (_tgt_ports_file dante db); echo $status) -ne 0

# Active target unchanged after non-active operations.
@test "ports_cli --target: TGT_ACTIVE unchanged" \
    "$TGT_ACTIVE" = web
_test_teardown

#
# --target with non-existent alias → error.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_target_cli new web --no-edit >/dev/null
set -gx TGT 10.0.0.10
_tgt_target_save dante web
_tgt_clear_target_runtime
_tgt_target_cli switch web >/dev/null

set -l rc (_tgt_ports_cli add --target nope 22 ssh 2>/dev/null; echo $status)
@test "ports_cli add --target nonexistent: returns non-zero" \
    "$rc" -ne 0
_test_teardown

#
# No active target AND no --target → error (used to be a hard
# function-entry guard; now resolves per subcommand).
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_target_cli new web --no-edit >/dev/null
set -gx TGT 10.0.0.10
_tgt_target_save dante web
_tgt_clear_target_runtime
set -q TGT_ACTIVE; and _tgt_unexport TGT_ACTIVE

set -l rc (_tgt_ports_cli add 22 ssh 2>/dev/null; echo $status)
@test "ports_cli add (no active, no --target): non-zero" \
    "$rc" -ne 0
# Same call WITH --target should succeed.
_tgt_ports_cli add --target web 22 ssh >/dev/null
@test "ports_cli add (no active, with --target): file written" \
    (_tgt_ports_list dante web | string match -q '*22*'; echo $status) -eq 0
_test_teardown

#
# `tgt ports service` — rename the service on an existing record.
# Comment is preserved (mirrors the comment verb in reverse).
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_target_cli new web --no-edit >/dev/null
set -gx TGT 10.0.0.10
_tgt_target_save dante web
_tgt_clear_target_runtime
_tgt_target_cli switch web >/dev/null

_tgt_ports_cli add 22 ssh "OpenSSH 8.4" >/dev/null
_tgt_ports_cli service 22 ssh-banner-lied >/dev/null

set -l line (_tgt_ports_list dante web | string match -e 22)
set -l fields (string split \t -- $line)
@test "ports_cli service: service field updated" \
    "$fields[3]" = ssh-banner-lied
@test "ports_cli service: comment preserved" \
    "$fields[4]" = "OpenSSH 8.4"

# Empty service is allowed (clears the field).
_tgt_ports_cli service 22 "" >/dev/null
set -l line2 (_tgt_ports_list dante web | string match -e 22)
set -l fields2 (string split \t -- $line2)
@test "ports_cli service '': service cleared" \
    "$fields2[3]" = ""
@test "ports_cli service '': comment still preserved" \
    "$fields2[4]" = "OpenSSH 8.4"

# Wrong port/proto → non-zero (no record to rename).
set -l rc (_tgt_ports_cli service 9999 nope 2>/dev/null; echo $status)
@test "ports_cli service: nonexistent record returns non-zero" \
    "$rc" -ne 0

# --target on service verb.
_tgt_target_cli new db --no-edit >/dev/null
set -gx TGT 10.0.0.20
_tgt_target_save dante db
_tgt_clear_target_runtime
_tgt_target_cli switch web >/dev/null
_tgt_ports_cli add --target db 3306 mysql "MariaDB 10.6" >/dev/null
_tgt_ports_cli service --target db 3306 postgres >/dev/null
set -l line3 (_tgt_ports_list dante db | string match -e 3306)
set -l fields3 (string split \t -- $line3)
@test "ports_cli service --target: rewrites non-active target" \
    "$fields3[3]" = postgres
@test "ports_cli service --target: comment preserved" \
    "$fields3[4]" = "MariaDB 10.6"
