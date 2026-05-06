source (status dirname)/helpers.fish

#
# tgt dc: errors when no active scenario.
#
_test_setup_home
@test "dc_cli: errors when no scenario active" \
    (_tgt_dc_cli list 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# tgt dc list: empty scenario → friendly note.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -l out (_tgt_dc_cli list 2>&1 | string collect)
@test "dc_cli list: empty → 'no DCs recorded' note" \
    (string match -q '*no DCs recorded*' -- $out; echo $status) -eq 0
_test_teardown

#
# tgt dc list: shows one row per DC with raw fields.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT_DC_DOMAIN dante.local
set -gx TGT_DC_REALM DANTE.LOCAL
set -gx TGT_DC_HOST dc01.dante.local
set -gx TGT_DC_IP 10.10.10.5
_tgt_dc_save dante dc01

set -e TGT_DC_HOST
set -gx TGT_DC_IP 10.10.10.6
_tgt_dc_save dante dc02

set -l out (_tgt_dc_cli list 2>&1 | string collect)
@test "dc_cli list: dc01 row present" \
    (string match -q '*dc01*dante.local*DANTE.LOCAL*' -- $out; echo $status) -eq 0
@test "dc_cli list: dc02 row present (ip-only)" \
    (string match -q '*dc02*10.10.10.6*' -- $out; echo $status) -eq 0
@test "dc_cli list: dc01 shows host (preferred over IP)" \
    (string match -q '*dc01.dante.local*' -- $out; echo $status) -eq 0
_test_teardown

#
# tgt dc show <alias>: detailed multi-line view.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT_DC_DOMAIN dante.local
set -gx TGT_DC_REALM DANTE.LOCAL
set -gx TGT_DC_HOST dc01.dante.local
set -gx TGT_DC_IP 10.10.10.5
set -gx TGT_DC_ADMIN_HOST dc01.dante.local
set -gx TGT_DC_ADMIN_IP 10.10.10.5
_tgt_dc_save dante dc01
set -e TGT_DC_DOMAIN TGT_DC_REALM TGT_DC_HOST TGT_DC_IP TGT_DC_ADMIN_HOST TGT_DC_ADMIN_IP

set -l out (_tgt_dc_cli show dc01 2>&1 | string collect)
@test "dc_cli show: alias line present" \
    (string match -q '*alias:*dc01*' -- $out; echo $status) -eq 0
@test "dc_cli show: domain line present" \
    (string match -q '*domain:*dante.local*' -- $out; echo $status) -eq 0
@test "dc_cli show: realm line present" \
    (string match -q '*realm:*DANTE.LOCAL*' -- $out; echo $status) -eq 0
@test "dc_cli show: kdc line shows host → ip mapping" \
    (string match -q '*kdc:*dc01.dante.local*→*10.10.10.5*' -- $out; echo $status) -eq 0
@test "dc_cli show: admin_server line shows host → ip mapping" \
    (string match -q '*admin_server:*dc01.dante.local*→*10.10.10.5*' -- $out; echo $status) -eq 0
@test "dc_cli show: doesn't pollute shell with TGT_DC_* exports" \
    (set -q TGT_DC_DOMAIN; echo $status) -ne 0
_test_teardown

#
# tgt dc show: minimal entry (no host/ip pair) shows "(not set)".
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT_DC_DOMAIN dante.local
set -gx TGT_DC_REALM DANTE.LOCAL
_tgt_dc_save dante minimal
set -e TGT_DC_DOMAIN TGT_DC_REALM

set -l out (_tgt_dc_cli show minimal 2>&1 | string collect)
@test "dc_cli show (minimal): kdc shows '(not set)'" \
    (string match -q '*kdc:*not set*' -- $out; echo $status) -eq 0
@test "dc_cli show (minimal): admin_server shows '(not set)'" \
    (string match -q '*admin_server:*not set*' -- $out; echo $status) -eq 0
_test_teardown

#
# tgt dc show: host-only entry shows just the host (no arrow).
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT_DC_DOMAIN dante.local
set -gx TGT_DC_REALM DANTE.LOCAL
set -gx TGT_DC_HOST dc01.dante.local
_tgt_dc_save dante host-only
set -e TGT_DC_DOMAIN TGT_DC_REALM TGT_DC_HOST

set -l out (_tgt_dc_cli show host-only 2>&1 | string collect)
@test "dc_cli show (host-only): no arrow" \
    (string match -q '*kdc:*→*' -- $out; echo $status) -ne 0
@test "dc_cli show (host-only): host present" \
    (string match -q '*kdc:*dc01.dante.local*' -- $out; echo $status) -eq 0
_test_teardown

#
# tgt dc show: nonexistent alias → non-zero.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
@test "dc_cli show: nonexistent alias → non-zero" \
    (_tgt_dc_cli show ghost 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# tgt dc show: no arg, no DCs → non-zero with hint.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
@test "dc_cli show: no DCs in scenario → non-zero" \
    (_tgt_dc_cli show 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# tgt dc rm: removes the named DC, keeps siblings.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT_DC_DOMAIN dante.local
set -gx TGT_DC_REALM DANTE.LOCAL
_tgt_dc_save dante dc01
_tgt_dc_save dante dc02
_tgt_dc_cli rm dc01 >/dev/null
@test "dc_cli rm: dc01 gone" \
    (_tgt_dc_exists dante dc01; echo $status) -ne 0
@test "dc_cli rm: dc02 preserved" \
    (_tgt_dc_exists dante dc02; echo $status) -eq 0
_test_teardown

#
# tgt dc rm: nonexistent alias → non-zero.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
@test "dc_cli rm: nonexistent → non-zero" \
    (_tgt_dc_cli rm ghost 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# tgt dc: unknown subcommand → non-zero.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
@test "dc_cli: unknown verb returns non-zero" \
    (_tgt_dc_cli garbage 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# tgt dc new: full set of fields, all stored.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_dc_cli new dc01 \
    --domain dante.local \
    --realm DANTE.LOCAL \
    --kdc-host dc01.dante.local --kdc-ip 10.10.10.5 \
    --admin-host dc01.dante.local --admin-ip 10.10.10.5 \
    >/dev/null
@test "dc_cli new: file created" \
    (_tgt_dc_exists dante dc01; echo $status) -eq 0
_tgt_dc_load dante dc01
@test "dc_cli new: TGT_DC_DOMAIN saved" "$TGT_DC_DOMAIN" = dante.local
@test "dc_cli new: TGT_DC_REALM saved" "$TGT_DC_REALM" = DANTE.LOCAL
@test "dc_cli new: TGT_DC_HOST saved" "$TGT_DC_HOST" = dc01.dante.local
@test "dc_cli new: TGT_DC_IP saved" "$TGT_DC_IP" = 10.10.10.5
@test "dc_cli new: TGT_DC_ADMIN_HOST saved" "$TGT_DC_ADMIN_HOST" = dc01.dante.local
@test "dc_cli new: TGT_DC_ADMIN_IP saved" "$TGT_DC_ADMIN_IP" = 10.10.10.5
_test_teardown

#
# tgt dc new: minimal — domain + kdc-ip only; realm auto-derived.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_dc_cli new minimal --domain dante.local --kdc-ip 10.10.10.5 >/dev/null
_tgt_dc_load dante minimal
@test "dc_cli new (minimal): realm auto = upper(domain)" \
    "$TGT_DC_REALM" = DANTE.LOCAL
@test "dc_cli new (minimal): TGT_DC falls back to IP" \
    "$TGT_DC" = 10.10.10.5
@test "dc_cli new (minimal): TGT_DC_HOST unset" \
    (set -q TGT_DC_HOST; echo $status) -ne 0
_test_teardown

#
# tgt dc new: lowercase realm is silently uppercased.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_dc_cli new mixed --domain dante.local --realm dante.local --kdc-ip 1.1.1.1 >/dev/null
_tgt_dc_load dante mixed
@test "dc_cli new: lowercase --realm gets uppercased on save" \
    "$TGT_DC_REALM" = DANTE.LOCAL
_test_teardown

#
# tgt dc new: explicit realm override (matching the user's example
# of a non-canonical realm name).
#
_test_setup_home
_tgt_scenario_cli new leandros >/dev/null
_tgt_dc_cli new dc01 \
    --domain leandros.eusec \
    --realm DC01.LEANDROS.EUSEC \
    --kdc-host dc01.leandros.eusec --admin-ip 1.1.1.1 \
    >/dev/null
_tgt_dc_load leandros dc01
@test "dc_cli new: explicit realm override preserved" \
    "$TGT_DC_REALM" = DC01.LEANDROS.EUSEC
@test "dc_cli new: domain stays lowercase" \
    "$TGT_DC_DOMAIN" = leandros.eusec
_test_teardown

#
# tgt dc new: rejects bad alias.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
@test "dc_cli new: rejects empty alias (no positional)" \
    (_tgt_dc_cli new --domain x.y --kdc-ip 1.1.1.1 2>/dev/null; echo $status) -ne 0
@test "dc_cli new: rejects 'bad alias' with space" \
    (_tgt_dc_cli new "bad alias" --domain x.y --kdc-ip 1.1.1.1 2>/dev/null; echo $status) -ne 0
@test "dc_cli new: rejects '../etc' path traversal" \
    (_tgt_dc_cli new ../etc --domain x.y --kdc-ip 1.1.1.1 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# tgt dc new: rejects missing domain.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
@test "dc_cli new: rejects missing --domain" \
    (_tgt_dc_cli new dc01 --kdc-ip 1.1.1.1 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# tgt dc new: rejects when neither --kdc-host nor --kdc-ip given.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
@test "dc_cli new: rejects when no kdc data given" \
    (_tgt_dc_cli new dc01 --domain dante.local 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# tgt dc new: rejects duplicate alias.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_dc_cli new dc01 --domain dante.local --kdc-ip 1.1.1.1 >/dev/null
@test "dc_cli new: duplicate alias rejected" \
    (_tgt_dc_cli new dc01 --domain dante.local --kdc-ip 1.1.1.1 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# `tgt dc` (no verb) drops into the switch picker, NOT a list dump.
# Empty-DC case shows a friendly note instead.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -l out (_tgt_dc_cli 2>&1 | string collect)
@test "dc_cli (no args, empty): friendly note" \
    (string match -q '*no DCs recorded*' -- $out; echo $status) -eq 0

# With DCs: bare `_tgt_dc_cli` should activate whichever the picker
# returns. Use TGT_PICKER_TEST_RESULT to bypass the interactive bit.
tgt dc new dc01 --domain dante.local --kdc-ip 1.1.1.1 >/dev/null
tgt dc new dc02 --domain dante.local --kdc-ip 1.1.1.2 >/dev/null
# dc02 is active (last-added). Picker returns dc01 → switch activates it.
set -gx TGT_PICKER_TEST_RESULT dc01
_tgt_dc_cli >/dev/null
@test "dc_cli (no args, with DCs): picker activates the chosen one" \
    "$TGT_DC_NAME" = dc01
set -e TGT_PICKER_TEST_RESULT
_test_teardown

#
# Top-level dispatch: `tgt dc list` reaches _tgt_dc_cli.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT_DC_DOMAIN dante.local
set -gx TGT_DC_REALM DANTE.LOCAL
_tgt_dc_save dante dc01
set -e TGT_DC_DOMAIN TGT_DC_REALM
@test "top-level: 'tgt dc list' dispatched correctly" \
    (tgt dc list 2>&1 | string match -q '*dc01*'; echo $status) -eq 0
_test_teardown
