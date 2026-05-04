source (status dirname)/helpers.fish

#
# revoke deselects the target (TGT_ACTIVE unset) but keeps the
# scenario, so the prompt collapses from [scenario:target] to [scenario].
#
_test_setup_home
_test_setup_hosts empty.txt
_test_setup_krb5 empty.conf
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 10.10.10.5
_tgt_target_cli new web01 >/dev/null
tgt --revoke >/dev/null

@test "revoke: TGT unset" \
    (set -q TGT; echo $status) -ne 0
@test "revoke: TGT_ACTIVE unset (target deselected)" \
    (set -q TGT_ACTIVE; echo $status) -ne 0
@test "revoke: TGT_SCENARIO kept (still in scenario)" \
    "$TGT_SCENARIO" = dante
_test_teardown

#
# After revoke, tgt_prompt shows [scenario] only — no :target part,
# no color escapes for "host loaded" or "creds loaded".
#
_test_setup_home
_test_setup_hosts empty.txt
_test_setup_krb5 empty.conf
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 10.10.10.5
set -gx TGT_PASSWORD secret
_tgt_target_cli new web01 >/dev/null
tgt --revoke >/dev/null
set -l raw (tgt_prompt | string collect)

@test "revoke: prompt contains [dante]" \
    (string match -rq '\[dante\]' -- $raw; echo $status) -eq 0
@test "revoke: prompt has no :target segment" \
    (string match -rq ':' -- $raw; echo $status) -ne 0
@test "revoke: prompt no longer red (creds gone)" \
    (string match -rq '\e\[31m' -- $raw; echo $status) -ne 0
_test_teardown

#
# revoke is safe when nothing is set: no errors, idempotent.
#
_test_setup_home
_test_setup_hosts empty.txt
_test_setup_krb5 empty.conf
set -l rc (tgt --revoke >/dev/null 2>&1; echo $status)

@test "revoke (clean state): exits 0" $rc -eq 0
_test_teardown

#
# The persisted target file on disk is preserved — revoke is a runtime
# clear, not a delete. tgt switch reloads the saved state.
#
_test_setup_home
_test_setup_hosts empty.txt
_test_setup_krb5 empty.conf
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 10.10.10.5
set -gx TGT_USERNAME admin
_tgt_target_cli new web01 >/dev/null
tgt --revoke >/dev/null
_tgt_target_cli switch web01 >/dev/null

@test "revoke + switch back: TGT restored from disk" \
    "$TGT" = 10.10.10.5
@test "revoke + switch back: TGT_USERNAME restored from disk" \
    "$TGT_USERNAME" = admin
@test "revoke + switch back: TGT_ACTIVE restored to web01" \
    "$TGT_ACTIVE" = web01
_test_teardown

#
# revoke clears TGT_PORT (transient runtime selection from `tgt ports`).
#
_test_setup_home
_test_setup_hosts empty.txt
_test_setup_krb5 empty.conf
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 10.10.10.5
_tgt_target_cli new web01 >/dev/null
set -gx TGT_PORT 445
tgt --revoke >/dev/null
@test "revoke: TGT_PORT unset" \
    (set -q TGT_PORT; echo $status) -ne 0
_test_teardown
