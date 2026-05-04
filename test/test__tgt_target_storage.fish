source (status dirname)/helpers.fish

#
# validate_name: same rules as scenarios — quick sanity.
#
@test "target validate_name: simple name" \
    (_tgt_target_validate_name web01; echo $status) -eq 0
@test "target validate_name: with dash" \
    (_tgt_target_validate_name api-gateway; echo $status) -eq 0
@test "target validate_name: rejects empty" \
    (_tgt_target_validate_name ""; echo $status) -ne 0
@test "target validate_name: rejects path traversal" \
    (_tgt_target_validate_name "../etc"; echo $status) -ne 0
@test "target validate_name: rejects shell metacharacters" \
    (_tgt_target_validate_name 'a;b'; echo $status) -ne 0

#
# file: composes path correctly.
#
_test_setup_home
@test "target_file: composes <scenario_dir>/targets/<target>.fish" \
    (_tgt_target_file dante web01) = "$TGT_HOME/scenarios/dante/targets/web01.fish"
_test_teardown

#
# exists: false for missing scenario or missing target.
#
_test_setup_home
@test "target_exists: false when scenario missing" \
    (_tgt_target_exists dante web01; echo $status) -ne 0
_tgt_scenario_create dante >/dev/null
@test "target_exists: false when scenario exists but target missing" \
    (_tgt_target_exists dante web01; echo $status) -ne 0
_test_teardown

#
# save → exists → destroy round-trip.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT 172.16.10.20
_tgt_target_save dante web01
@test "target_save: file created" -f (_tgt_target_file dante web01)
@test "target_exists: true after save" \
    (_tgt_target_exists dante web01; echo $status) -eq 0
_tgt_target_destroy dante web01
@test "target_destroy: file gone" \
    (_tgt_target_exists dante web01; echo $status) -ne 0
_test_teardown

#
# Save persists all set $TGT* vars.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT 172.16.10.20
set -gx TGT_USERNAME admin
set -gx TGT_PASSWORD hunter2
set -gx TGT_AD_DOMAIN dante.local
set -gx TGT_DC DC01.dante.local
set -gx TGT_HOSTS web01.dante.local intranet.dante.local
_tgt_target_save dante web01
set -l content (cat (_tgt_target_file dante web01))
@test "save: TGT line present" \
    (string match -rq '_tgt_export TGT 172.16.10.20' -- $content; echo $status) -eq 0
@test "save: TGT_USERNAME line present" \
    (string match -rq '_tgt_export TGT_USERNAME admin' -- $content; echo $status) -eq 0
@test "save: TGT_PASSWORD line present" \
    (string match -rq '_tgt_export TGT_PASSWORD hunter2' -- $content; echo $status) -eq 0
@test "save: TGT_AD_DOMAIN line present" \
    (string match -rq '_tgt_export TGT_AD_DOMAIN dante.local' -- $content; echo $status) -eq 0
@test "save: TGT_DC line present" \
    (string match -rq '_tgt_export TGT_DC DC01.dante.local' -- $content; echo $status) -eq 0
@test "save: TGT_HOSTS list serialized as multiple values" \
    (string match -rq '_tgt_export TGT_HOSTS .*web01.dante.local.*intranet.dante.local' -- $content; echo $status) -eq 0
_test_teardown

#
# Save skips unset vars.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT 10.10.10.5
# TGT_USERNAME, TGT_PASSWORD, etc. are all unset
_tgt_target_save dante web01
set -l content (cat (_tgt_target_file dante web01))
@test "save: only sets exports for set vars" \
    (count $content) -eq 1
@test "save: that one line is TGT" \
    (string match -rq '_tgt_export TGT 10.10.10.5' -- $content; echo $status) -eq 0
_test_teardown

#
# Save preserves values with spaces (via string escape).
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT_PASSWORD 'pass word with spaces'
_tgt_target_save dante web01
# Clear and load
set -e TGT_PASSWORD
_tgt_target_load dante web01
@test "save+load: password with spaces preserved" \
    "$TGT_PASSWORD" = 'pass word with spaces'
_test_teardown

#
# Save + load round-trip restores all fields.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT 172.16.10.20
set -gx TGT_USERNAME admin
set -gx TGT_HOSTS web01.dante.local intranet.dante.local
_tgt_target_save dante web01
# Clear env
set -e TGT TGT_USERNAME TGT_HOSTS
_tgt_target_load dante web01
@test "load: TGT restored" "$TGT" = "172.16.10.20"
@test "load: TGT_USERNAME restored" "$TGT_USERNAME" = "admin"
@test "load: TGT_HOSTS restored as list" (count $TGT_HOSTS) -eq 2
@test "load: TGT_HOSTS[1] correct" "$TGT_HOSTS[1]" = "web01.dante.local"
@test "load: TGT_HOSTS[2] correct" "$TGT_HOSTS[2]" = "intranet.dante.local"
_test_teardown

#
# load: errors if target missing.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
@test "load: errors when target missing" \
    (_tgt_target_load dante nonexistent 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# list: empty / populated / scenario-scoped.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
_tgt_scenario_create acme >/dev/null
@test "target_list: empty when scenario has no targets" \
    (count (_tgt_target_list dante)) -eq 0
set -gx TGT 1.2.3.4
_tgt_target_save dante web01
_tgt_target_save dante dc01
_tgt_target_save acme api
set -l dante_targets (_tgt_target_list dante)
set -l acme_targets (_tgt_target_list acme)
@test "target_list: dante has 2 targets" (count $dante_targets) -eq 2
@test "target_list: dante includes web01" \
    (contains web01 $dante_targets; echo $status) -eq 0
@test "target_list: dante includes dc01" \
    (contains dc01 $dante_targets; echo $status) -eq 0
@test "target_list: acme has 1 target (scenario isolation)" \
    (count $acme_targets) -eq 1
@test "target_list: acme includes api" \
    (contains api $acme_targets; echo $status) -eq 0
_test_teardown

#
# destroy: removes only the named target, leaves siblings.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT 1.2.3.4
_tgt_target_save dante web01
_tgt_target_save dante dc01
_tgt_target_destroy dante web01
@test "target_destroy: web01 gone" \
    (_tgt_target_exists dante web01; echo $status) -ne 0
@test "target_destroy: dc01 preserved" \
    (_tgt_target_exists dante dc01; echo $status) -eq 0
_test_teardown

#
# destroy: idempotent.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
_tgt_target_destroy dante never_existed
@test "target_destroy: returns 0 when target was missing" $status -eq 0
_test_teardown
