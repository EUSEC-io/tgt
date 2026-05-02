source (status dirname)/helpers.fish

#
# _tgt_scenario_validate_name: accepts allowed forms.
#
@test "validate_name: simple alphanumeric" \
    (_tgt_scenario_validate_name dante; echo $status) -eq 0
@test "validate_name: with hyphen" \
    (_tgt_scenario_validate_name customer-acme; echo $status) -eq 0
@test "validate_name: with underscore" \
    (_tgt_scenario_validate_name htb_forest; echo $status) -eq 0
@test "validate_name: digits ok" \
    (_tgt_scenario_validate_name proLab2; echo $status) -eq 0

#
# _tgt_scenario_validate_name: rejects bad forms.
#
@test "validate_name: rejects empty" \
    (_tgt_scenario_validate_name ""; echo $status) -ne 0
@test "validate_name: rejects spaces" \
    (_tgt_scenario_validate_name "with space"; echo $status) -ne 0
@test "validate_name: rejects path traversal" \
    (_tgt_scenario_validate_name "../etc"; echo $status) -ne 0
@test "validate_name: rejects dot" \
    (_tgt_scenario_validate_name "scen.ario"; echo $status) -ne 0
@test "validate_name: rejects leading hyphen" \
    (_tgt_scenario_validate_name "-evil"; echo $status) -ne 0
@test "validate_name: rejects shell metacharacters" \
    (_tgt_scenario_validate_name 'a;b'; echo $status) -ne 0

#
# _tgt_scenario_dir: composes path correctly.
#
_test_setup_home
@test "scenario_dir: composes <home>/scenarios/<name>" \
    (_tgt_scenario_dir dante) = "$TGT_HOME/scenarios/dante"
_test_teardown

#
# _tgt_scenario_exists: false when missing, true after create.
#
_test_setup_home
@test "scenario_exists: false when missing" \
    (_tgt_scenario_exists dante; echo $status) -ne 0
_tgt_scenario_create dante >/dev/null
@test "scenario_exists: true after create" \
    (_tgt_scenario_exists dante; echo $status) -eq 0
_test_teardown

#
# _tgt_scenario_create: creates directory + targets/ subdir.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
@test "scenario_create: scenario dir exists" \
    -d (_tgt_scenario_dir dante)
@test "scenario_create: targets/ subdir exists" \
    -d (_tgt_scenario_dir dante)/targets
_test_teardown

#
# _tgt_scenario_create: idempotent (re-creating is a no-op).
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
_tgt_scenario_create dante >/dev/null
@test "scenario_create: idempotent (second call exits 0)" $status -eq 0
@test "scenario_create: scenario still exists after re-create" \
    (_tgt_scenario_exists dante; echo $status) -eq 0
_test_teardown

#
# _tgt_scenario_create: rejects invalid names.
#
_test_setup_home
@test "scenario_create: rejects invalid name" \
    (_tgt_scenario_create "bad name" 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# _tgt_scenario_destroy: removes the scenario's tree.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
_tgt_scenario_destroy dante
@test "scenario_destroy: scenario gone" \
    (_tgt_scenario_exists dante; echo $status) -ne 0
_test_teardown

#
# _tgt_scenario_destroy: idempotent (no error on missing).
#
_test_setup_home
_tgt_scenario_destroy never_existed
@test "scenario_destroy: returns 0 when scenario was missing" $status -eq 0
_test_teardown

#
# _tgt_scenario_destroy: only the named scenario goes away.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
_tgt_scenario_create acme >/dev/null
_tgt_scenario_destroy dante
@test "scenario_destroy: dante gone" \
    (_tgt_scenario_exists dante; echo $status) -ne 0
@test "scenario_destroy: acme survives" \
    (_tgt_scenario_exists acme; echo $status) -eq 0
_test_teardown

#
# _tgt_scenario_list: empty / populated.
#
_test_setup_home
@test "scenario_list: empty when no scenarios" \
    (count (_tgt_scenario_list)) -eq 0
_tgt_scenario_create dante >/dev/null
_tgt_scenario_create acme >/dev/null
_tgt_scenario_create htb_forest >/dev/null
set -l scenarios (_tgt_scenario_list)
@test "scenario_list: returns 3 entries after creating 3" \
    (count $scenarios) -eq 3
@test "scenario_list: includes dante" \
    (contains dante $scenarios; echo $status) -eq 0
@test "scenario_list: includes acme" \
    (contains acme $scenarios; echo $status) -eq 0
@test "scenario_list: includes htb_forest" \
    (contains htb_forest $scenarios; echo $status) -eq 0
_test_teardown

#
# Sudoless: scenario operations don't escalate privileges.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -l owner (stat -c '%U' (_tgt_scenario_dir dante))
@test "scenario_create: owned by current user (no sudo)" \
    "$owner" = "$USER"
_test_teardown
