source (status dirname)/helpers.fish

#
# _tgt_scenario_archived: marker file presence.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null

@test "archived (no marker): returns 1" \
    (_tgt_scenario_archived dante; echo $status) -ne 0

touch (_tgt_scenario_dir dante)/.archived
@test "archived (with marker): returns 0" \
    (_tgt_scenario_archived dante; echo $status) -eq 0
_test_teardown

#
# tgt scenario archive: creates the marker.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_scenario_cli archive dante >/dev/null

@test "archive: marker file exists" \
    -f (_tgt_scenario_dir dante)/.archived
@test "archive: _tgt_scenario_archived returns 0" \
    (_tgt_scenario_archived dante; echo $status) -eq 0
_test_teardown

#
# tgt scenario archive (no arg): archives the active scenario.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null   # auto-active
_tgt_scenario_cli archive >/dev/null
@test "archive (no arg): archives active scenario" \
    (_tgt_scenario_archived dante; echo $status) -eq 0
_test_teardown

#
# tgt scenario archive: rejects nonexistent.
#
_test_setup_home
set -l rc (_tgt_scenario_cli archive ghost 2>/dev/null; echo $status)
@test "archive (nonexistent): non-zero" $rc -ne 0
_test_teardown

#
# tgt scenario archive: idempotent on already-archived.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_scenario_cli archive dante >/dev/null
set -l rc2 (_tgt_scenario_cli archive dante 2>/dev/null; echo $status)
@test "archive (already archived): exits 0 (idempotent)" $rc2 -eq 0
_test_teardown

#
# tgt scenario unarchive: removes the marker.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_scenario_cli archive dante >/dev/null
_tgt_scenario_cli unarchive dante >/dev/null

@test "unarchive: marker removed" \
    ! -f (_tgt_scenario_dir dante)/.archived
@test "unarchive: _tgt_scenario_archived returns 1" \
    (_tgt_scenario_archived dante; echo $status) -ne 0
_test_teardown

#
# tgt scenario unarchive (not archived): no-op, exit 0.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -l rc3 (_tgt_scenario_cli unarchive dante 2>/dev/null; echo $status)
@test "unarchive (not archived): exits 0" $rc3 -eq 0
_test_teardown

#
# tgt scenario list (default): hides archived scenarios.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_scenario_cli new acme >/dev/null
_tgt_scenario_cli archive acme >/dev/null
set -gx TGT_SCENARIO dante
set -l raw (_tgt_scenario_cli list)
set -l output (string replace -ar '\e\[[0-9;]*m' '' -- $raw | string replace -ar '\e\(B' '')

@test "list (default): includes dante (active)" \
    (string match -rq '^\* dante' -- $output; echo $status) -eq 0
@test "list (default): excludes acme (archived)" \
    (string match -rq 'acme' -- $output; echo $status) -ne 0
@test "list (default): footer notes hidden archived" \
    (string match -rq '1 archived hidden' -- $output; echo $status) -eq 0
_test_teardown

#
# tgt scenario list --all: shows both, marks archived rows.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_scenario_cli new acme >/dev/null
_tgt_scenario_cli archive acme >/dev/null
set -gx TGT_SCENARIO dante
set -l raw2 (_tgt_scenario_cli list --all)
set -l out2 (string replace -ar '\e\[[0-9;]*m' '' -- $raw2 | string replace -ar '\e\(B' '')

@test "list --all: includes dante" \
    (string match -rq 'dante' -- $out2; echo $status) -eq 0
@test "list --all: includes acme" \
    (string match -rq 'acme' -- $out2; echo $status) -eq 0
@test "list --all: marks acme [archived]" \
    (string match -rq 'acme.*\[archived\]' -- $out2; echo $status) -eq 0
_test_teardown

#
# tgt scenario list --archived: shows only archived.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_scenario_cli new acme >/dev/null
_tgt_scenario_cli archive acme >/dev/null
set -l raw3 (_tgt_scenario_cli list --archived)
set -l out3 (string replace -ar '\e\[[0-9;]*m' '' -- $raw3 | string replace -ar '\e\(B' '')

@test "list --archived: shows acme" \
    (string match -rq 'acme' -- $out3; echo $status) -eq 0
@test "list --archived: hides dante (active)" \
    (string match -rq '\bdante\b' -- $out3; echo $status) -ne 0
_test_teardown

#
# tgt scenario list --all + --archived: mutually exclusive.
#
_test_setup_home
set -l rc4 (_tgt_scenario_cli list --all --archived 2>/dev/null; echo $status)
@test "list --all --archived: rejected" $rc4 -ne 0
_test_teardown

#
# tgt scenario switch <name>: works on archived (named explicitly).
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_scenario_cli new acme >/dev/null
_tgt_scenario_cli archive acme >/dev/null
_tgt_scenario_cli switch acme >/dev/null
@test "switch <archived>: TGT_SCENARIO updated" "$TGT_SCENARIO" = acme
_test_teardown

#
# Empty active list with archived present: helpful message.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_scenario_cli archive dante >/dev/null
set -l raw_e (_tgt_scenario_cli list)
@test "list (only archived exist): mentions archived count" \
    (string match -rq '1 archived' -- $raw_e; echo $status) -eq 0
_test_teardown
