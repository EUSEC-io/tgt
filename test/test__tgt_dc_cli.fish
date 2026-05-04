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
