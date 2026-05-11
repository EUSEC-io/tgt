source (status dirname)/helpers.fish

function _test_clear_cred_env
    for v in TGT_USERNAME TGT_PASSWORD TGT_CRED_NAME TGT_CRED_USERNAME \
             TGT_CRED_PASSWORD TGT_CRED_DOMAIN TGT_CRED_NOTES
        set -q $v; and set -e $v
    end
end

#
# Validators.
#
@test "cred validate_name: simple alphanumeric" \
    (_tgt_cred_validate_name admin; echo $status) -eq 0
@test "cred validate_name: with dash" \
    (_tgt_cred_validate_name svc-sql; echo $status) -eq 0
@test "cred validate_name: with underscore" \
    (_tgt_cred_validate_name j_doe; echo $status) -eq 0
@test "cred validate_name: rejects empty" \
    (_tgt_cred_validate_name ""; echo $status) -ne 0
@test "cred validate_name: rejects path traversal" \
    (_tgt_cred_validate_name "../etc"; echo $status) -ne 0
@test "cred validate_name: rejects spaces" \
    (_tgt_cred_validate_name "admin user"; echo $status) -ne 0
@test "cred validate_name: rejects shell metacharacters" \
    (_tgt_cred_validate_name 'a;b'; echo $status) -ne 0

#
# file: composes the right path.
#
_test_setup_home
@test "cred_file: composes <scenario_dir>/creds/<alias>.fish" \
    (_tgt_cred_file dante admin) = "$TGT_HOME/scenarios/dante/creds/admin.fish"
_test_teardown

#
# exists: false until save creates the file.
#
_test_setup_home
@test "cred_exists: false when scenario missing" \
    (_tgt_cred_exists dante admin; echo $status) -ne 0
_tgt_scenario_create dante >/dev/null
@test "cred_exists: false when scenario exists but cred missing" \
    (_tgt_cred_exists dante admin; echo $status) -ne 0
_test_teardown

#
# Save creates the creds/ dir on demand and persists the raw fields.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT_CRED_USERNAME Administrator
set -gx TGT_CRED_PASSWORD hunter2
set -gx TGT_CRED_DOMAIN dante.local
set -gx TGT_CRED_NOTES "default admin"
# These should NOT be serialized — they're derived at load time.
set -gx TGT_USERNAME alice
set -gx TGT_PASSWORD foo
set -gx TGT_CRED_NAME stray
_tgt_cred_save dante admin

@test "cred_save: creds/ dir created on demand" \
    (test -d $TGT_HOME/scenarios/dante/creds; echo $status) -eq 0
@test "cred_save: file created" \
    (test -f (_tgt_cred_file dante admin); echo $status) -eq 0

set -l content (cat (_tgt_cred_file dante admin))
@test "cred_save: TGT_CRED_USERNAME line present" \
    (string match -rq '_tgt_export TGT_CRED_USERNAME Administrator' -- $content; echo $status) -eq 0
@test "cred_save: TGT_CRED_PASSWORD line present" \
    (string match -rq '_tgt_export TGT_CRED_PASSWORD hunter2' -- $content; echo $status) -eq 0
@test "cred_save: TGT_CRED_DOMAIN line present" \
    (string match -rq '_tgt_export TGT_CRED_DOMAIN dante.local' -- $content; echo $status) -eq 0
@test "cred_save: TGT_CRED_NOTES line present" \
    (string match -rq 'TGT_CRED_NOTES' -- $content; echo $status) -eq 0
@test "cred_save: TGT_USERNAME NOT serialized (derived at load)" \
    (string match -rq '_tgt_export TGT_USERNAME ' -- $content; echo $status) -ne 0
@test "cred_save: TGT_CRED_NAME NOT serialized (derived from alias)" \
    (string match -rq '_tgt_export TGT_CRED_NAME ' -- $content; echo $status) -ne 0
_test_clear_cred_env
_test_teardown

#
# Save skips unset vars (only username given is enough).
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT_CRED_USERNAME alice
_tgt_cred_save dante alice
set -l content (cat (_tgt_cred_file dante alice))
@test "cred_save: only writes the set fields" \
    (count $content) -eq 1
@test "cred_save: that one line is USERNAME" \
    (string match -rq '_tgt_export TGT_CRED_USERNAME alice' -- $content; echo $status) -eq 0
_test_clear_cred_env
_test_teardown

#
# Save+load round-trip: derived vars come out right.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT_CRED_USERNAME Administrator
set -gx TGT_CRED_PASSWORD hunter2
set -gx TGT_CRED_DOMAIN dante.local
_tgt_cred_save dante admin
_test_clear_cred_env

_tgt_cred_load dante admin
@test "cred_load: TGT_CRED_USERNAME restored" \
    "$TGT_CRED_USERNAME" = Administrator
@test "cred_load: TGT_CRED_PASSWORD restored" \
    "$TGT_CRED_PASSWORD" = hunter2
@test "cred_load: TGT_CRED_DOMAIN restored" \
    "$TGT_CRED_DOMAIN" = dante.local
@test "cred_load: TGT_USERNAME derived" \
    "$TGT_USERNAME" = Administrator
@test "cred_load: TGT_PASSWORD derived" \
    "$TGT_PASSWORD" = hunter2
@test "cred_load: TGT_CRED_NAME derived from alias" \
    "$TGT_CRED_NAME" = admin
_test_clear_cred_env
_test_teardown

#
# Save+load preserves passwords with special chars.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT_CRED_USERNAME alice
set -gx TGT_CRED_PASSWORD 'P@ssw0rd! with $pecial &'
_tgt_cred_save dante alice
_test_clear_cred_env
_tgt_cred_load dante alice
@test "cred save+load: password with special chars preserved" \
    "$TGT_CRED_PASSWORD" = 'P@ssw0rd! with $pecial &'
@test "cred save+load: derived TGT_PASSWORD matches" \
    "$TGT_PASSWORD" = 'P@ssw0rd! with $pecial &'
_test_clear_cred_env
_test_teardown

#
# Save+load handles NTLM-hash form in the password field (same field,
# user just pastes the hash).
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT_CRED_USERNAME admin
set -gx TGT_CRED_PASSWORD 'aad3b435b51404eeaad3b435b51404ee:31d6cfe0d16ae931b73c59d7e0c089c0'
_tgt_cred_save dante admin-hash
_test_clear_cred_env
_tgt_cred_load dante admin-hash
@test "cred save+load: NTLM hash preserved verbatim" \
    "$TGT_CRED_PASSWORD" = 'aad3b435b51404eeaad3b435b51404ee:31d6cfe0d16ae931b73c59d7e0c089c0'
_test_clear_cred_env
_test_teardown

#
# load: errors on missing file.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
@test "cred_load: errors when cred missing" \
    (_tgt_cred_load dante ghost 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# list: empty / many; scenario-isolated.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
_tgt_scenario_create acme >/dev/null
@test "cred_list: empty when scenario has no creds" \
    (count (_tgt_cred_list dante)) -eq 0

set -gx TGT_CRED_USERNAME admin
_tgt_cred_save dante admin
set -gx TGT_CRED_USERNAME bob
_tgt_cred_save dante bob
set -gx TGT_CRED_USERNAME charlie
_tgt_cred_save acme charlie

set -l dante_creds (_tgt_cred_list dante)
set -l acme_creds  (_tgt_cred_list acme)
@test "cred_list: dante has 2 creds" (count $dante_creds) -eq 2
@test "cred_list: dante includes admin" \
    (contains admin $dante_creds; echo $status) -eq 0
@test "cred_list: dante includes bob" \
    (contains bob $dante_creds; echo $status) -eq 0
@test "cred_list: acme has 1 cred (scenario isolation)" \
    (count $acme_creds) -eq 1
@test "cred_list: acme includes charlie" \
    (contains charlie $acme_creds; echo $status) -eq 0
_test_clear_cred_env
_test_teardown

#
# destroy: removes the named cred, leaves siblings.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT_CRED_USERNAME a
_tgt_cred_save dante a
_tgt_cred_save dante b
_tgt_cred_destroy dante a
@test "cred_destroy: a gone" \
    (_tgt_cred_exists dante a; echo $status) -ne 0
@test "cred_destroy: b preserved" \
    (_tgt_cred_exists dante b; echo $status) -eq 0
@test "cred_destroy: idempotent" \
    (_tgt_cred_destroy dante never_existed; echo $status) -eq 0
_test_clear_cred_env
_test_teardown

#
# inspect: tab-separated line; no shell pollution.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT_CRED_USERNAME Administrator
set -gx TGT_CRED_PASSWORD hunter2
set -gx TGT_CRED_DOMAIN dante.local
set -gx TGT_CRED_NOTES "default admin from secretsdump"
_tgt_cred_save dante admin
_test_clear_cred_env

set -l line (_tgt_cred_inspect dante admin)
set -l fields (string split \t -- $line)

@test "cred_inspect: alias field 1"      "$fields[1]" = admin
@test "cred_inspect: username field 2"   "$fields[2]" = Administrator
@test "cred_inspect: has_password = Y"   "$fields[3]" = Y
@test "cred_inspect: domain field 4"     "$fields[4]" = dante.local
@test "cred_inspect: notes (truncated)"  (string length -- $fields[5]) -le 30
@test "cred_inspect: no shell pollution" \
    (set -q TGT_CRED_USERNAME; echo $status) -ne 0
_test_teardown

#
# inspect: minimal entry (username only) shows em-dashes for empty fields.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT_CRED_USERNAME alice
_tgt_cred_save dante alice
_test_clear_cred_env

set -l line (_tgt_cred_inspect dante alice)
set -l fields (string split \t -- $line)
@test "cred_inspect (minimal): has_password = N" "$fields[3]" = N
@test "cred_inspect (minimal): domain em-dash"   "$fields[4]" = "—"
@test "cred_inspect (minimal): notes em-dash"    "$fields[5]" = "—"
_test_teardown

#
# Active marker: get/set/clear lifecycle.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
@test "cred active: get returns non-zero when unset" \
    (_tgt_cred_get_active dante 2>/dev/null; echo $status) -ne 0
_tgt_cred_set_active dante admin
@test "cred active: get returns alias after set" \
    (_tgt_cred_get_active dante) = admin
_tgt_cred_set_active dante bob
@test "cred active: set overwrites previous marker" \
    (_tgt_cred_get_active dante) = bob
_tgt_cred_clear_active dante
@test "cred active: clear removes marker" \
    (_tgt_cred_get_active dante 2>/dev/null; echo $status) -ne 0
@test "cred active: clear idempotent" \
    (_tgt_cred_clear_active dante; echo $status) -eq 0
_test_teardown

#
# clear_runtime: erases all runtime vars (raw + derived). Wrapped
# in _test_setup_home so TGT_TEST_MODE is set — `_tgt_unexport`
# uses `set -e` only in test mode (and `set -Ue` otherwise, which
# wouldn't touch the global vars we just set).
#
_test_setup_home
set -gx TGT_USERNAME u
set -gx TGT_PASSWORD p
set -gx TGT_CRED_NAME admin
set -gx TGT_CRED_USERNAME u
set -gx TGT_CRED_PASSWORD p
set -gx TGT_CRED_DOMAIN d
set -gx TGT_CRED_NOTES n
_tgt_cred_clear_runtime
@test "cred clear_runtime: TGT_USERNAME erased" \
    (set -q TGT_USERNAME; echo $status) -ne 0
@test "cred clear_runtime: TGT_PASSWORD erased" \
    (set -q TGT_PASSWORD; echo $status) -ne 0
@test "cred clear_runtime: TGT_CRED_NAME erased" \
    (set -q TGT_CRED_NAME; echo $status) -ne 0
@test "cred clear_runtime: TGT_CRED_DOMAIN erased" \
    (set -q TGT_CRED_DOMAIN; echo $status) -ne 0
@test "cred clear_runtime: TGT_CRED_NOTES erased" \
    (set -q TGT_CRED_NOTES; echo $status) -ne 0
_test_teardown

#
# restore_active: handles missing marker, stale marker, and the
# happy path of loading the named entry.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
@test "cred restore_active: no marker → exit 0, runtime stays unset" \
    (_tgt_cred_restore_active dante; set -q TGT_USERNAME; echo $status) -ne 0

_tgt_cred_set_active dante ghost
@test "cred restore_active: stale marker (missing entry) → cleared" \
    (_tgt_cred_restore_active dante; _tgt_cred_get_active dante 2>/dev/null; echo $status) -ne 0

set -gx TGT_CRED_USERNAME alice
set -gx TGT_CRED_PASSWORD secret
_tgt_cred_save dante alice
set -e TGT_CRED_USERNAME TGT_CRED_PASSWORD
_tgt_cred_set_active dante alice
_tgt_cred_restore_active dante
@test "cred restore_active (happy path): TGT_USERNAME loaded" \
    "$TGT_USERNAME" = alice
@test "cred restore_active (happy path): TGT_CRED_NAME loaded" \
    "$TGT_CRED_NAME" = alice
_tgt_cred_clear_runtime
_test_teardown
