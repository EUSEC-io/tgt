source (status dirname)/helpers.fish

# Local cleanup: clear DC env vars between cases so saved/loaded
# state doesn't leak. Mirrors what _tgt_clear_target_runtime does
# for targets, but we don't need a runtime helper yet (those land
# with `tgt dc switch`).
function _test_clear_dc_env
    for v in TGT_DC TGT_DC_NAME TGT_DC_DOMAIN TGT_DC_REALM \
             TGT_DC_HOST TGT_DC_IP TGT_DC_ADMIN_HOST TGT_DC_ADMIN_IP
        set -q $v; and set -e $v
    end
end

#
# validate_name: shares the rules that target/scenario aliases use.
#
@test "dc validate_name: simple alphanumeric" \
    (_tgt_dc_validate_name dc01; echo $status) -eq 0
@test "dc validate_name: with dash" \
    (_tgt_dc_validate_name dc-01; echo $status) -eq 0
@test "dc validate_name: with underscore" \
    (_tgt_dc_validate_name dc_01; echo $status) -eq 0
@test "dc validate_name: rejects empty" \
    (_tgt_dc_validate_name ""; echo $status) -ne 0
@test "dc validate_name: rejects path traversal" \
    (_tgt_dc_validate_name "../etc"; echo $status) -ne 0
@test "dc validate_name: rejects spaces" \
    (_tgt_dc_validate_name "dc 01"; echo $status) -ne 0
@test "dc validate_name: rejects shell metacharacters" \
    (_tgt_dc_validate_name 'a;b'; echo $status) -ne 0

#
# file: composes path correctly under <scenario>/dcs/.
#
_test_setup_home
@test "dc_file: composes <scenario_dir>/dcs/<alias>.fish" \
    (_tgt_dc_file dante dc01) = "$TGT_HOME/scenarios/dante/dcs/dc01.fish"
_test_teardown

#
# exists: false when scenario or DC missing; true after save.
#
_test_setup_home
@test "dc_exists: false when scenario missing" \
    (_tgt_dc_exists dante dc01; echo $status) -ne 0
_tgt_scenario_create dante >/dev/null
@test "dc_exists: false when scenario exists but DC missing" \
    (_tgt_dc_exists dante dc01; echo $status) -ne 0
_test_teardown

#
# Save creates the dcs/ subdir on demand (scenario_create doesn't
# pre-make it).
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT_DC_DOMAIN dante.local
set -gx TGT_DC_REALM DANTE.LOCAL
_tgt_dc_save dante dc01
@test "dc_save: dcs/ dir created on demand" \
    (test -d $TGT_HOME/scenarios/dante/dcs; echo $status) -eq 0
@test "dc_save: file created" \
    (test -f (_tgt_dc_file dante dc01); echo $status) -eq 0
@test "dc_exists: true after save" \
    (_tgt_dc_exists dante dc01; echo $status) -eq 0
_test_clear_dc_env
_test_teardown

#
# Save serializes only the raw fields (no derived TGT_DC / TGT_DC_NAME).
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT_DC_DOMAIN dante.local
set -gx TGT_DC_REALM DANTE.LOCAL
set -gx TGT_DC_HOST dc01.dante.local
set -gx TGT_DC_IP 10.10.10.5
set -gx TGT_DC_ADMIN_HOST dc01.dante.local
set -gx TGT_DC_ADMIN_IP 10.10.10.5
# These two should NOT make it into the file — they're derived.
set -gx TGT_DC dc01.dante.local
set -gx TGT_DC_NAME dc01
_tgt_dc_save dante dc01
set -l content (cat (_tgt_dc_file dante dc01))
@test "dc_save: TGT_DC_DOMAIN line present" \
    (string match -rq '_tgt_export TGT_DC_DOMAIN dante.local' -- $content; echo $status) -eq 0
@test "dc_save: TGT_DC_REALM line present" \
    (string match -rq '_tgt_export TGT_DC_REALM DANTE.LOCAL' -- $content; echo $status) -eq 0
@test "dc_save: TGT_DC_HOST line present" \
    (string match -rq '_tgt_export TGT_DC_HOST dc01.dante.local' -- $content; echo $status) -eq 0
@test "dc_save: TGT_DC_IP line present" \
    (string match -rq '_tgt_export TGT_DC_IP 10.10.10.5' -- $content; echo $status) -eq 0
@test "dc_save: TGT_DC_ADMIN_HOST line present" \
    (string match -rq '_tgt_export TGT_DC_ADMIN_HOST dc01.dante.local' -- $content; echo $status) -eq 0
@test "dc_save: TGT_DC_ADMIN_IP line present" \
    (string match -rq '_tgt_export TGT_DC_ADMIN_IP 10.10.10.5' -- $content; echo $status) -eq 0
@test "dc_save: derived TGT_DC NOT serialized" \
    (string match -rq '_tgt_export TGT_DC ' -- $content; echo $status) -ne 0
@test "dc_save: derived TGT_DC_NAME NOT serialized" \
    (string match -rq '_tgt_export TGT_DC_NAME ' -- $content; echo $status) -ne 0
_test_clear_dc_env
_test_teardown

#
# Save skips unset vars (only domain + realm given).
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT_DC_DOMAIN dante.local
set -gx TGT_DC_REALM DANTE.LOCAL
_tgt_dc_save dante minimal
set -l content (cat (_tgt_dc_file dante minimal))
@test "dc_save: only writes the set fields" \
    (count $content) -eq 2
_test_clear_dc_env
_test_teardown

#
# Save+load round-trip: all 6 raw fields restored, TGT_DC + TGT_DC_NAME
# derived correctly.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT_DC_DOMAIN dante.local
set -gx TGT_DC_REALM DANTE.LOCAL
set -gx TGT_DC_HOST dc01.dante.local
set -gx TGT_DC_IP 10.10.10.5
set -gx TGT_DC_ADMIN_HOST dc01.dante.local
set -gx TGT_DC_ADMIN_IP 10.10.10.5
_tgt_dc_save dante dc01
_test_clear_dc_env
_tgt_dc_load dante dc01
@test "dc_load: TGT_DC_DOMAIN restored" \
    "$TGT_DC_DOMAIN" = dante.local
@test "dc_load: TGT_DC_REALM restored" \
    "$TGT_DC_REALM" = DANTE.LOCAL
@test "dc_load: TGT_DC_HOST restored" \
    "$TGT_DC_HOST" = dc01.dante.local
@test "dc_load: TGT_DC_IP restored" \
    "$TGT_DC_IP" = 10.10.10.5
@test "dc_load: TGT_DC_ADMIN_HOST restored" \
    "$TGT_DC_ADMIN_HOST" = dc01.dante.local
@test "dc_load: TGT_DC_ADMIN_IP restored" \
    "$TGT_DC_ADMIN_IP" = 10.10.10.5
@test "dc_load: TGT_DC derived to host (preferred over IP)" \
    "$TGT_DC" = dc01.dante.local
@test "dc_load: TGT_DC_NAME derived from alias" \
    "$TGT_DC_NAME" = dc01
_test_clear_dc_env
_test_teardown

#
# load: TGT_DC falls back to IP when no host given.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT_DC_DOMAIN dante.local
set -gx TGT_DC_REALM DANTE.LOCAL
set -gx TGT_DC_IP 10.10.10.5
_tgt_dc_save dante ip-only
_test_clear_dc_env
_tgt_dc_load dante ip-only
@test "dc_load (ip-only): TGT_DC = IP" \
    "$TGT_DC" = 10.10.10.5
@test "dc_load (ip-only): TGT_DC_HOST unset" \
    (set -q TGT_DC_HOST; echo $status) -ne 0
_test_clear_dc_env
_test_teardown

#
# load: TGT_DC unset entirely when neither host nor IP given.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT_DC_DOMAIN dante.local
set -gx TGT_DC_REALM DANTE.LOCAL
_tgt_dc_save dante bare
_test_clear_dc_env
_tgt_dc_load dante bare
@test "dc_load (bare): TGT_DC stays unset" \
    (set -q TGT_DC; echo $status) -ne 0
@test "dc_load (bare): TGT_DC_NAME still set" \
    "$TGT_DC_NAME" = bare
_test_clear_dc_env
_test_teardown

#
# load: errors on missing file.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
@test "dc_load: errors when DC missing" \
    (_tgt_dc_load dante ghost 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# Save+load preserves values with spaces (via string escape) — comments
# could land in admin_host placeholders if user goes off-piste.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT_DC_DOMAIN 'spaced domain.local'
set -gx TGT_DC_REALM 'SPACED DOMAIN.LOCAL'
_tgt_dc_save dante spaces
_test_clear_dc_env
_tgt_dc_load dante spaces
@test "dc_save+load: domain with spaces preserved" \
    "$TGT_DC_DOMAIN" = 'spaced domain.local'
@test "dc_save+load: realm with spaces preserved" \
    "$TGT_DC_REALM" = 'SPACED DOMAIN.LOCAL'
_test_clear_dc_env
_test_teardown

#
# list: empty / one / many, scenario-isolated.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
_tgt_scenario_create acme >/dev/null
@test "dc_list: empty when scenario has no DCs" \
    (count (_tgt_dc_list dante)) -eq 0

set -gx TGT_DC_DOMAIN dante.local
set -gx TGT_DC_REALM DANTE.LOCAL
_tgt_dc_save dante dc01
_tgt_dc_save dante dc02

set -gx TGT_DC_DOMAIN acme.local
set -gx TGT_DC_REALM ACME.LOCAL
_tgt_dc_save acme dca

set -l dante_dcs (_tgt_dc_list dante)
set -l acme_dcs (_tgt_dc_list acme)

@test "dc_list: dante has 2 DCs" (count $dante_dcs) -eq 2
@test "dc_list: dante includes dc01" \
    (contains dc01 $dante_dcs; echo $status) -eq 0
@test "dc_list: dante includes dc02" \
    (contains dc02 $dante_dcs; echo $status) -eq 0
@test "dc_list: acme has 1 DC (scenario isolation)" \
    (count $acme_dcs) -eq 1
@test "dc_list: acme includes dca" \
    (contains dca $acme_dcs; echo $status) -eq 0
_test_clear_dc_env
_test_teardown

#
# destroy: removes the named DC, leaves siblings.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT_DC_DOMAIN dante.local
set -gx TGT_DC_REALM DANTE.LOCAL
_tgt_dc_save dante dc01
_tgt_dc_save dante dc02
_tgt_dc_destroy dante dc01
@test "dc_destroy: dc01 gone" \
    (_tgt_dc_exists dante dc01; echo $status) -ne 0
@test "dc_destroy: dc02 preserved" \
    (_tgt_dc_exists dante dc02; echo $status) -eq 0
@test "dc_destroy: idempotent (returns 0 when missing)" \
    (_tgt_dc_destroy dante never_existed; echo $status) -eq 0
_test_clear_dc_env
_test_teardown

#
# inspect: tab-separated state line without polluting the shell.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT_DC_DOMAIN dante.local
set -gx TGT_DC_REALM DANTE.LOCAL
set -gx TGT_DC_HOST dc01.dante.local
set -gx TGT_DC_IP 10.10.10.5
set -gx TGT_DC_ADMIN_IP 10.10.10.5
_tgt_dc_save dante dc01
_test_clear_dc_env

set -l line (_tgt_dc_inspect dante dc01)
set -l fields (string split \t -- $line)
@test "dc_inspect: alias is field 1" "$fields[1]" = dc01
@test "dc_inspect: domain is field 2" "$fields[2]" = dante.local
@test "dc_inspect: realm is field 3"  "$fields[3]" = DANTE.LOCAL
@test "dc_inspect: kdc resolves to host (preferred)" \
    "$fields[4]" = dc01.dante.local
@test "dc_inspect: admin falls back to IP when only IP given" \
    "$fields[5]" = 10.10.10.5
@test "dc_inspect: doesn't pollute shell with TGT_DC_* exports" \
    (set -q TGT_DC_DOMAIN; echo $status) -ne 0
_test_teardown

#
# inspect: minimal entry → em-dashes for missing fields.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT_DC_DOMAIN dante.local
set -gx TGT_DC_REALM DANTE.LOCAL
_tgt_dc_save dante minimal
_test_clear_dc_env

set -l line (_tgt_dc_inspect dante minimal)
set -l fields (string split \t -- $line)
@test "dc_inspect (minimal): kdc is em-dash when neither host nor IP set" \
    "$fields[4]" = "—"
@test "dc_inspect (minimal): admin is em-dash" \
    "$fields[5]" = "—"
_test_teardown

#
# inspect: missing file → non-zero.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
@test "dc_inspect: missing file → non-zero" \
    (_tgt_dc_inspect dante ghost 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# Save rejects bad scenarios / aliases.
#
_test_setup_home
@test "dc_save: errors when scenario missing" \
    (_tgt_dc_save dante dc01 2>/dev/null; echo $status) -ne 0
_tgt_scenario_create dante >/dev/null
@test "dc_save: errors on invalid alias" \
    (_tgt_dc_save dante "bad alias" 2>/dev/null; echo $status) -ne 0
_test_teardown
