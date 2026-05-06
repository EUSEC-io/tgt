source (status dirname)/helpers.fish

#
# strip_tgt_blocks: leaves manual entries untouched, removes only
# tgt-tagged blocks (comment + realm body).
#
set -l input "[libdefaults]
    default_realm = SOMETHING

[realms]
    MANUAL.LOCAL = {
        kdc = manual.local
    }
    # tgt:dc:dante:dc01
    DANTE.LOCAL = {
        kdc = dc01.dante.local
        admin_server = dc01.dante.local
    }
    OTHER.MANUAL = {
        kdc = other.manual
    }
"
set -l stripped (printf '%s' $input | _tgt_krb5_strip_tgt_blocks | string collect)
@test "strip_tgt_blocks: tgt comment line removed" \
    (string match -q '*tgt:dc:dante:dc01*' -- $stripped; echo $status) -ne 0
@test "strip_tgt_blocks: tgt realm name removed" \
    (string match -q '*DANTE.LOCAL*' -- $stripped; echo $status) -ne 0
@test "strip_tgt_blocks: manual realm preserved" \
    (string match -q '*MANUAL.LOCAL*manual.local*' -- $stripped; echo $status) -eq 0
@test "strip_tgt_blocks: another manual realm preserved" \
    (string match -q '*OTHER.MANUAL*other.manual*' -- $stripped; echo $status) -eq 0
@test "strip_tgt_blocks: [libdefaults] preserved" \
    (string match -q '*default_realm = SOMETHING*' -- $stripped; echo $status) -eq 0

#
# render_dc: full set of fields → block with comment, realm, kdc, admin.
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
set -e TGT_DC_DOMAIN TGT_DC_REALM TGT_DC_HOST TGT_DC_IP TGT_DC_ADMIN_HOST TGT_DC_ADMIN_IP

set -l block (_tgt_krb5_render_realm dante DANTE.LOCAL dc01 | string collect)
@test "render_realm: comment marker carries the alias" \
    (string match -q '*# tgt:dc:dante:dc01*' -- $block; echo $status) -eq 0
@test "render_realm: realm = open brace" \
    (string match -q '*DANTE.LOCAL = {*' -- $block; echo $status) -eq 0
@test "render_realm: kdc uses HOST (preferred over IP)" \
    (string match -q '*kdc = dc01.dante.local*' -- $block; echo $status) -eq 0
@test "render_realm: admin_server line present" \
    (string match -q '*admin_server = dc01.dante.local*' -- $block; echo $status) -eq 0
@test "render_realm: closing brace present" \
    (string match -q '*}*' -- $block; echo $status) -eq 0
_test_teardown

#
# render_realm: ip-only entry → kdc = IP.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT_DC_DOMAIN dante.local
set -gx TGT_DC_REALM DANTE.LOCAL
set -gx TGT_DC_IP 10.10.10.5
_tgt_dc_save dante ip-only
set -e TGT_DC_DOMAIN TGT_DC_REALM TGT_DC_IP

set -l block (_tgt_krb5_render_realm dante DANTE.LOCAL ip-only | string collect)
@test "render_realm (ip-only): kdc = IP" \
    (string match -q '*kdc = 10.10.10.5*' -- $block; echo $status) -eq 0
@test "render_realm (ip-only): no admin_server line" \
    (string match -q '*admin_server*' -- $block; echo $status) -ne 0
_test_teardown

#
# render_realm: no kdc data → non-zero, no output.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT_DC_DOMAIN dante.local
set -gx TGT_DC_REALM DANTE.LOCAL
_tgt_dc_save dante bare
set -e TGT_DC_DOMAIN TGT_DC_REALM
@test "render_realm: bare entry → non-zero" \
    (_tgt_krb5_render_realm dante DANTE.LOCAL bare 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# render_realm: TWO DCs with the SAME realm collapse into one
# block with multiple `kdc =` lines (the canonical kerberos form).
# Identical kdc values are deduped.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT_DC_DOMAIN dante.local
set -gx TGT_DC_REALM DANTE.LOCAL
set -gx TGT_DC_HOST dc01.dante.local
_tgt_dc_save dante dc01
set -e TGT_DC_HOST
set -gx TGT_DC_HOST dc02.dante.local
_tgt_dc_save dante dc02
set -e TGT_DC_DOMAIN TGT_DC_REALM TGT_DC_HOST

set -l block (_tgt_krb5_render_realm dante DANTE.LOCAL dc01 dc02 | string collect)
@test "render_realm (merged): comment carries both aliases joined with +" \
    (string match -q '*# tgt:dc:dante:dc01+dc02*' -- $block; echo $status) -eq 0
@test "render_realm (merged): one realm = { line" \
    (count (string match -ar '(?m)^\s+DANTE.LOCAL = \{' -- $block)) -eq 1
@test "render_realm (merged): kdc dc01 line present" \
    (string match -q '*kdc = dc01.dante.local*' -- $block; echo $status) -eq 0
@test "render_realm (merged): kdc dc02 line present" \
    (string match -q '*kdc = dc02.dante.local*' -- $block; echo $status) -eq 0
_test_teardown

#
# render_realm: same kdc value across two DCs is deduped.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT_DC_DOMAIN dante.local
set -gx TGT_DC_REALM DANTE.LOCAL
set -gx TGT_DC_HOST shared.dante.local
_tgt_dc_save dante dc01
_tgt_dc_save dante dc02
set -e TGT_DC_DOMAIN TGT_DC_REALM TGT_DC_HOST

set -l block (_tgt_krb5_render_realm dante DANTE.LOCAL dc01 dc02 | string collect)
@test "render_realm (dedup): one kdc line, not two" \
    (count (string match -ar '(?m)^\s+kdc = ' -- $block)) -eq 1
@test "render_realm (dedup): comment still references both aliases" \
    (string match -q '*# tgt:dc:dante:dc01+dc02*' -- $block; echo $status) -eq 0
_test_teardown

#
# apply_scenario: writes one realm block per DC, under [realms].
#
_test_setup_home
_test_setup_krb5 empty.conf
_tgt_scenario_create dante >/dev/null

set -gx TGT_DC_DOMAIN dante.local
set -gx TGT_DC_REALM DANTE.LOCAL
set -gx TGT_DC_HOST dc01.dante.local
set -gx TGT_DC_IP 10.10.10.5
_tgt_dc_save dante dc01
set -e TGT_DC_HOST TGT_DC_IP
set -gx TGT_DC_REALM DANTE2.LOCAL
set -gx TGT_DC_IP 10.10.10.6
_tgt_dc_save dante dc02
set -e TGT_DC_DOMAIN TGT_DC_REALM TGT_DC_IP

_tgt_krb5_apply_scenario dante
set -l content (cat $TGT_KRB5_FILE | string collect)

@test "apply_scenario: dc01 tgt comment present" \
    (string match -q '*# tgt:dc:dante:dc01*' -- $content; echo $status) -eq 0
@test "apply_scenario: dc01 realm block opens" \
    (string match -q '*DANTE.LOCAL = {*' -- $content; echo $status) -eq 0
@test "apply_scenario: dc01 kdc line present" \
    (string match -q '*kdc = dc01.dante.local*' -- $content; echo $status) -eq 0
@test "apply_scenario: dc02 tgt comment present" \
    (string match -q '*# tgt:dc:dante:dc02*' -- $content; echo $status) -eq 0
@test "apply_scenario: dc02 realm uses IP (no host given)" \
    (string match -q '*DANTE2.LOCAL = {*' -- $content; echo $status) -eq 0
_test_teardown

#
# apply_scenario: TWO DCs sharing one realm collapse into ONE
# block with TWO `kdc =` lines (canonical kerberos form). This is
# the scenario that was emitting duplicate-realm blocks before the
# merge fix landed.
#
_test_setup_home
_test_setup_krb5 empty.conf
_tgt_scenario_create dante >/dev/null

set -gx TGT_DC_DOMAIN dante.local
set -gx TGT_DC_REALM DANTE.LOCAL
set -gx TGT_DC_HOST dc01.dante.local
_tgt_dc_save dante dc01
set -e TGT_DC_HOST
set -gx TGT_DC_HOST dc02.dante.local
_tgt_dc_save dante dc02
set -e TGT_DC_DOMAIN TGT_DC_REALM TGT_DC_HOST

_tgt_krb5_apply_scenario dante
set -l content (cat $TGT_KRB5_FILE | string collect)

@test "apply_scenario (same realm): merged comment lists both aliases" \
    (string match -q '*# tgt:dc:dante:dc01+dc02*' -- $content; echo $status) -eq 0
@test "apply_scenario (same realm): only ONE realm block emitted" \
    (count (string match -ar '(?m)^\s+DANTE.LOCAL = \{' -- $content)) -eq 1
@test "apply_scenario (same realm): kdc dc01 line present" \
    (string match -q '*kdc = dc01.dante.local*' -- $content; echo $status) -eq 0
@test "apply_scenario (same realm): kdc dc02 line present" \
    (string match -q '*kdc = dc02.dante.local*' -- $content; echo $status) -eq 0
@test "apply_scenario (same realm): no duplicate-realm orphan" \
    (count (string match -ar '# tgt:dc:dante:dc01\n' -- (cat $TGT_KRB5_FILE | string collect))) -eq 0
_test_teardown

#
# Removing one of two same-realm DCs collapses the merged block down
# to a single-alias block that still references the surviving DC's
# kdc — no orphaned-kdc cleanup needed because apply rebuilds from
# the remaining dcs/ files.
#
_test_setup_home
_test_setup_krb5 empty.conf
_tgt_scenario_create dante >/dev/null
set -gx TGT_DC_DOMAIN dante.local
set -gx TGT_DC_REALM DANTE.LOCAL
set -gx TGT_DC_HOST dc01.dante.local
_tgt_dc_save dante dc01
set -e TGT_DC_HOST
set -gx TGT_DC_HOST dc02.dante.local
_tgt_dc_save dante dc02
set -e TGT_DC_DOMAIN TGT_DC_REALM TGT_DC_HOST
_tgt_krb5_apply_scenario dante

# Now drop dc01 — the surviving block should reference only dc02.
_tgt_dc_destroy dante dc01
_tgt_krb5_apply_scenario dante
set -l content (cat $TGT_KRB5_FILE | string collect)

@test "after rm one of two same-realm DCs: comment is just dc02" \
    (string match -q '*# tgt:dc:dante:dc02*' -- $content; echo $status) -eq 0
@test "after rm one of two same-realm DCs: dc01 alias gone from comment" \
    (string match -q '*dc01*' -- $content; echo $status) -ne 0
@test "after rm one of two same-realm DCs: dc02 kdc still present" \
    (string match -q '*kdc = dc02.dante.local*' -- $content; echo $status) -eq 0
@test "after rm one of two same-realm DCs: dc01 kdc dropped" \
    (string match -q '*kdc = dc01.dante.local*' -- $content; echo $status) -ne 0
_test_teardown

#
# Two DCs with the SAME realm AND SAME kdc value: dedupes to one
# kdc line. Removing one DC leaves the surviving DC's identical kdc
# value untouched.
#
_test_setup_home
_test_setup_krb5 empty.conf
_tgt_scenario_create dante >/dev/null
set -gx TGT_DC_DOMAIN dante.local
set -gx TGT_DC_REALM DANTE.LOCAL
set -gx TGT_DC_HOST shared.dante.local
_tgt_dc_save dante dc01
_tgt_dc_save dante dc02
set -e TGT_DC_DOMAIN TGT_DC_REALM TGT_DC_HOST

_tgt_krb5_apply_scenario dante
@test "same realm + same kdc: only one kdc line emitted" \
    (count (string match -ar '(?m)^\s+kdc = ' -- (cat $TGT_KRB5_FILE | string collect))) -eq 1

_tgt_dc_destroy dante dc01
_tgt_krb5_apply_scenario dante
@test "after rm dc01: shared kdc still present (dc02 still references it)" \
    (cat $TGT_KRB5_FILE | string match -q '*kdc = shared.dante.local*'; echo $status) -eq 0
@test "after rm dc01: comment carries surviving alias only" \
    (cat $TGT_KRB5_FILE | string match -q '*# tgt:dc:dante:dc02*'; echo $status) -eq 0
_test_teardown

#
# apply_scenario: removing all DCs from a scenario strips the blocks
# from krb5.conf.
#
_test_setup_home
_test_setup_krb5 empty.conf
_tgt_scenario_create dante >/dev/null
set -gx TGT_DC_DOMAIN dante.local
set -gx TGT_DC_REALM DANTE.LOCAL
set -gx TGT_DC_IP 10.10.10.5
_tgt_dc_save dante dc01
set -e TGT_DC_DOMAIN TGT_DC_REALM TGT_DC_IP

_tgt_krb5_apply_scenario dante
@test "apply_scenario: realm present after first apply" \
    (cat $TGT_KRB5_FILE | string match -q '*DANTE.LOCAL = {*'; echo $status) -eq 0

_tgt_dc_destroy dante dc01
_tgt_krb5_apply_scenario dante
@test "apply_scenario: tgt-tagged block stripped after dc removed" \
    (cat $TGT_KRB5_FILE | string match -q '*tgt:dc:dante:dc01*'; echo $status) -ne 0
@test "apply_scenario: realm name gone" \
    (cat $TGT_KRB5_FILE | string match -q '*DANTE.LOCAL = {*'; echo $status) -ne 0
_test_teardown

#
# apply_scenario: manual user-written realm blocks are preserved.
#
_test_setup_home
set -gx TGT_TEST_MODE 1
set -gx TGT_KRB5_FILE (mktemp)
echo '[libdefaults]
    default_realm = MANUAL.LOCAL

[realms]
    MANUAL.LOCAL = {
        kdc = manual.kdc
    }
' > $TGT_KRB5_FILE

_tgt_scenario_create dante >/dev/null
set -gx TGT_DC_DOMAIN dante.local
set -gx TGT_DC_REALM DANTE.LOCAL
set -gx TGT_DC_IP 10.10.10.5
_tgt_dc_save dante dc01
set -e TGT_DC_DOMAIN TGT_DC_REALM TGT_DC_IP

_tgt_krb5_apply_scenario dante
set -l content (cat $TGT_KRB5_FILE | string collect)
@test "apply_scenario: manual realm preserved alongside tgt block" \
    (string match -q '*MANUAL.LOCAL = {*kdc = manual.kdc*' -- $content; echo $status) -eq 0
@test "apply_scenario: tgt block also added" \
    (string match -q '*tgt:dc:dante:dc01*' -- $content; echo $status) -eq 0
_test_teardown

#
# apply_scenario: hot-swap on scenario new + switch — old scenario's
# blocks are stripped when a new one becomes active.
#
_test_setup_home
_test_setup_krb5 empty.conf
_tgt_scenario_cli new dante >/dev/null
_tgt_dc_cli new dc01 --domain dante.local --kdc-ip 10.10.10.5 >/dev/null

@test "scenario new (with later dc): dante's realm in krb5" \
    (cat $TGT_KRB5_FILE | string match -q '*DANTE.LOCAL = {*'; echo $status) -eq 0

_tgt_scenario_cli new acme >/dev/null
@test "scenario new acme: dante's tgt block stripped" \
    (cat $TGT_KRB5_FILE | string match -q '*tgt:dc:dante:dc01*'; echo $status) -ne 0
@test "scenario new acme: realm name gone" \
    (cat $TGT_KRB5_FILE | string match -q '*DANTE.LOCAL = {*'; echo $status) -ne 0

_tgt_scenario_cli switch dante >/dev/null
@test "scenario switch back to dante: realm reappears" \
    (cat $TGT_KRB5_FILE | string match -q '*DANTE.LOCAL = {*'; echo $status) -eq 0
_test_teardown

#
# apply_scenario: dispatch via `tgt dc new` writes krb5.
#
_test_setup_home
_test_setup_krb5 empty.conf
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 --domain dante.local --kdc-host dc01.dante.local --kdc-ip 10.10.10.5 >/dev/null
@test "tgt dc new: krb5 block written" \
    (cat $TGT_KRB5_FILE | string match -q '*kdc = dc01.dante.local*'; echo $status) -eq 0

tgt dc rm dc01 >/dev/null
@test "tgt dc rm: krb5 block stripped" \
    (cat $TGT_KRB5_FILE | string match -q '*tgt:dc:*'; echo $status) -ne 0
_test_teardown

#
# scenario rm strips that scenario's tgt blocks even when removing
# a non-active scenario.
#
_test_setup_home
_test_setup_krb5 empty.conf
_tgt_scenario_cli new dante >/dev/null
tgt dc new ddc --domain dante.local --kdc-ip 10.10.10.5 >/dev/null
_tgt_scenario_cli new acme >/dev/null
tgt dc new adc --domain acme.local --kdc-ip 10.20.20.5 >/dev/null
# acme is active. Remove dante (not active).
_tgt_scenario_cli rm dante >/dev/null

set -l content (cat $TGT_KRB5_FILE | string collect)
@test "scenario rm (non-active): dante's tgt block stripped" \
    (string match -q '*tgt:dc:dante:ddc*' -- $content; echo $status) -ne 0
@test "scenario rm (non-active): acme's tgt block preserved" \
    (string match -q '*tgt:dc:acme:adc*' -- $content; echo $status) -eq 0
_test_teardown
