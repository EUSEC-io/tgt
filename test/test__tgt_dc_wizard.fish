source (status dirname)/helpers.fish

# Drive the wizard via TGT_ASK_QUEUE (each entry → one prompt). The
# queue is popped front-to-back; an empty entry behaves like "user
# pressed Enter" and falls back to the prompt's default.

#
# Full happy path: alias from arg, all six fields filled in.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT_ASK_QUEUE \
    dante.local \
    DANTE.LOCAL \
    dc01.dante.local \
    10.10.10.5 \
    dc01.dante.local \
    10.10.10.5
_tgt_dc_wizard dante dc01 >/dev/null

@test "wizard: DC entry created" \
    (_tgt_dc_exists dante dc01; echo $status) -eq 0
@test "wizard: TGT_DC_DOMAIN exported" "$TGT_DC_DOMAIN" = dante.local
@test "wizard: TGT_DC_REALM exported" "$TGT_DC_REALM" = DANTE.LOCAL
@test "wizard: TGT_DC_HOST exported" "$TGT_DC_HOST" = dc01.dante.local
@test "wizard: TGT_DC_IP exported" "$TGT_DC_IP" = 10.10.10.5
@test "wizard: TGT_DC_ADMIN_HOST exported" "$TGT_DC_ADMIN_HOST" = dc01.dante.local
@test "wizard: TGT_DC_ADMIN_IP exported" "$TGT_DC_ADMIN_IP" = 10.10.10.5
@test "wizard: marker written" \
    (_tgt_dc_get_active dante) = dc01
@test "wizard: TGT_DC derived to host" "$TGT_DC" = dc01.dante.local
_test_teardown

#
# Realm defaults to upper(domain) when user just hits Enter.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT_ASK_QUEUE \
    dante.local \
    "" \
    "" \
    10.10.10.5 \
    "" \
    ""
_tgt_dc_wizard dante dc01 >/dev/null

@test "wizard (default realm): TGT_DC_REALM = upper(domain)" \
    "$TGT_DC_REALM" = DANTE.LOCAL
@test "wizard (default realm): kdc set from IP" \
    "$TGT_DC_IP" = 10.10.10.5
@test "wizard (default realm): TGT_DC_HOST unset" \
    (set -q TGT_DC_HOST; echo $status) -ne 0
_test_teardown

#
# Lowercase user-typed realm is silently uppercased.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT_ASK_QUEUE \
    dante.local \
    dante.local \
    "" \
    10.10.10.5 \
    "" \
    ""
_tgt_dc_wizard dante dc01 >/dev/null

@test "wizard: lowercase realm input → uppercase saved" \
    "$TGT_DC_REALM" = DANTE.LOCAL
_test_teardown

#
# Empty domain → error, no entry created.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT_ASK_QUEUE ""
@test "wizard: empty domain → non-zero" \
    (_tgt_dc_wizard dante dc01 2>/dev/null; echo $status) -ne 0
@test "wizard: no entry created on empty-domain error" \
    (_tgt_dc_exists dante dc01; echo $status) -ne 0
_test_teardown

#
# Both kdc fields blank → error, no entry created.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT_ASK_QUEUE \
    dante.local \
    DANTE.LOCAL \
    "" \
    "" \
    "" \
    ""
@test "wizard: blank kdc-host AND kdc-ip → non-zero" \
    (_tgt_dc_wizard dante dc01 &>/dev/null; echo $status) -ne 0
@test "wizard: no entry created on blank-kdc error" \
    (_tgt_dc_exists dante dc01; echo $status) -ne 0
_test_teardown

#
# Existing alias → error before any prompts run.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 --domain dante.local --kdc-ip 10.10.10.5 >/dev/null
@test "wizard: existing alias → non-zero" \
    (_tgt_dc_wizard dante dc01 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# Invalid alias passed in → error before any prompts run.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
@test "wizard: invalid alias → non-zero" \
    (_tgt_dc_wizard dante "bad alias" 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# Wizard ends with /etc/krb5.conf and /etc/hosts in sync.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT_ASK_QUEUE \
    dante.local \
    DANTE.LOCAL \
    dc01.dante.local \
    10.10.10.5 \
    "" \
    ""
_tgt_dc_wizard dante dc01 >/dev/null

@test "wizard: krb5 realm block opens with DANTE.LOCAL" \
    (cat $TGT_KRB5_FILE | string match -q '*DANTE.LOCAL = {*'; echo $status) -eq 0
@test "wizard: krb5 realm block contains kdc = host" \
    (cat $TGT_KRB5_FILE | string match -q '*kdc = dc01.dante.local*'; echo $status) -eq 0
@test "wizard: krb5 default_realm pointed at the new realm" \
    (cat $TGT_KRB5_FILE | string match -q '*default_realm = DANTE.LOCAL*'; echo $status) -eq 0
@test "wizard: /etc/hosts mapping written" \
    (cat $TGT_HOSTS_FILE | string match -q '*10.10.10.5*dc01.dante.local*tgt:dc:dante:dc01*'; echo $status) -eq 0
_test_teardown
