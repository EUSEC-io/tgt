source (status dirname)/helpers.fish

#
# active marker file: get/set/clear lifecycle.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
@test "dc active: get returns non-zero when unset" \
    (_tgt_dc_get_active dante 2>/dev/null; echo $status) -ne 0

_tgt_dc_set_active dante dc01
@test "dc active: get returns the alias after set" \
    (_tgt_dc_get_active dante) = dc01

_tgt_dc_set_active dante dc02
@test "dc active: set overwrites previous marker" \
    (_tgt_dc_get_active dante) = dc02

_tgt_dc_clear_active dante
@test "dc active: clear removes marker" \
    (_tgt_dc_get_active dante 2>/dev/null; echo $status) -ne 0
@test "dc active: clear is idempotent" \
    (_tgt_dc_clear_active dante; echo $status) -eq 0
_test_teardown

#
# Auto-active on `tgt dc new`: env vars exported + marker written.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 \
    --domain dante.local \
    --kdc-host dc01.dante.local --kdc-ip 10.10.10.5 \
    >/dev/null
@test "dc new: TGT_DC_NAME exported" "$TGT_DC_NAME" = dc01
@test "dc new: TGT_DC_DOMAIN exported" "$TGT_DC_DOMAIN" = dante.local
@test "dc new: TGT_DC_REALM exported" "$TGT_DC_REALM" = DANTE.LOCAL
@test "dc new: TGT_DC derived to host" "$TGT_DC" = dc01.dante.local
@test "dc new: TGT_DC_HOST exported" "$TGT_DC_HOST" = dc01.dante.local
@test "dc new: TGT_DC_IP exported" "$TGT_DC_IP" = 10.10.10.5
@test "dc new: marker written" \
    (_tgt_dc_get_active dante) = dc01
@test "dc new: default_realm set in krb5" \
    (cat $TGT_KRB5_FILE | string match -q '*default_realm = DANTE.LOCAL*'; echo $status) -eq 0
_test_teardown

#
# Creating a second DC re-points the active marker (last-added wins).
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 --domain dante.local --kdc-ip 10.10.10.5 >/dev/null
tgt dc new dc02 --domain dante2.local --kdc-ip 10.10.10.6 >/dev/null
@test "dc new (second): marker now points at dc02" \
    (_tgt_dc_get_active dante) = dc02
@test "dc new (second): TGT_DC_NAME flipped to dc02" "$TGT_DC_NAME" = dc02
@test "dc new (second): TGT_DC_REALM flipped to DANTE2.LOCAL" \
    "$TGT_DC_REALM" = DANTE2.LOCAL
@test "dc new (second): default_realm flipped" \
    (cat $TGT_KRB5_FILE | string match -q '*default_realm = DANTE2.LOCAL*'; echo $status) -eq 0
_test_teardown

#
# `tgt dc switch <alias>`: explicit activation.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 --domain dante.local --kdc-ip 10.10.10.5 >/dev/null
tgt dc new dc02 --domain dante2.local --kdc-ip 10.10.10.6 >/dev/null
# dc02 is active (last-added). Switch back to dc01.
tgt dc switch dc01 >/dev/null
@test "dc switch: TGT_DC_NAME → dc01" "$TGT_DC_NAME" = dc01
@test "dc switch: TGT_DC_REALM → DANTE.LOCAL" "$TGT_DC_REALM" = DANTE.LOCAL
@test "dc switch: marker updated" \
    (_tgt_dc_get_active dante) = dc01
@test "dc switch: default_realm updated" \
    (cat $TGT_KRB5_FILE | string match -q '*default_realm = DANTE.LOCAL*'; echo $status) -eq 0
_test_teardown

#
# `tgt dc switch` rejects nonexistent alias.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 --domain dante.local --kdc-ip 10.10.10.5 >/dev/null
@test "dc switch: nonexistent alias → non-zero" \
    (tgt dc switch ghost 2>/dev/null; echo $status) -ne 0
@test "dc switch: TGT_DC_NAME unchanged after failed switch" \
    "$TGT_DC_NAME" = dc01
_test_teardown

#
# `tgt dc unset`: clears env vars and marker.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 --domain dante.local --kdc-ip 10.10.10.5 >/dev/null
tgt dc unset >/dev/null
@test "dc unset: TGT_DC_NAME cleared" \
    (set -q TGT_DC_NAME; echo $status) -ne 0
@test "dc unset: TGT_DC cleared" \
    (set -q TGT_DC; echo $status) -ne 0
@test "dc unset: TGT_DC_REALM cleared" \
    (set -q TGT_DC_REALM; echo $status) -ne 0
@test "dc unset: marker removed" \
    (_tgt_dc_get_active dante 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# `tgt dc unset` is safe when nothing is active.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
@test "dc unset (clean state): exits 0" \
    (tgt dc unset >/dev/null; echo $status) -eq 0
_test_teardown

#
# `tgt dc rm` of the active DC clears env + marker.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 --domain dante.local --kdc-ip 10.10.10.5 >/dev/null
tgt dc rm dc01 >/dev/null
@test "dc rm (active): TGT_DC_NAME cleared" \
    (set -q TGT_DC_NAME; echo $status) -ne 0
@test "dc rm (active): marker cleared" \
    (_tgt_dc_get_active dante 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# `tgt dc rm` of a non-active DC leaves active runtime alone.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 --domain dante.local --kdc-ip 10.10.10.5 >/dev/null
tgt dc new dc02 --domain dante2.local --kdc-ip 10.10.10.6 >/dev/null
# dc02 is active; remove dc01.
tgt dc rm dc01 >/dev/null
@test "dc rm (non-active): TGT_DC_NAME unchanged" "$TGT_DC_NAME" = dc02
@test "dc rm (non-active): marker unchanged" \
    (_tgt_dc_get_active dante) = dc02
_test_teardown

#
# Scenario switch restores the per-scenario active DC.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
tgt dc new ddc --domain dante.local --kdc-host ddc.dante.local --kdc-ip 10.10.10.5 >/dev/null
_tgt_scenario_cli new acme >/dev/null
tgt dc new adc --domain acme.local --kdc-host adc.acme.local --kdc-ip 10.20.20.5 >/dev/null

# Switching back to dante should restore the dante:ddc state.
_tgt_scenario_cli switch dante >/dev/null
@test "scenario switch restores dante's active DC" \
    "$TGT_DC_NAME" = ddc
@test "scenario switch restores dante's TGT_DC_REALM" \
    "$TGT_DC_REALM" = DANTE.LOCAL
@test "scenario switch updates default_realm" \
    (cat $TGT_KRB5_FILE | string match -q '*default_realm = DANTE.LOCAL*'; echo $status) -eq 0

_tgt_scenario_cli switch acme >/dev/null
@test "scenario switch (acme): TGT_DC_NAME → adc" "$TGT_DC_NAME" = adc
@test "scenario switch (acme): TGT_DC_REALM → ACME.LOCAL" \
    "$TGT_DC_REALM" = ACME.LOCAL
_test_teardown

#
# Scenario without an active DC marker — switching in clears any
# stale TGT_DC_* runtime from the previous scenario.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
tgt dc new ddc --domain dante.local --kdc-ip 10.10.10.5 >/dev/null
# acme has no DCs at all.
_tgt_scenario_cli new acme >/dev/null
@test "scenario switch (acme, no DCs): TGT_DC_NAME cleared" \
    (set -q TGT_DC_NAME; echo $status) -ne 0
@test "scenario switch (acme, no DCs): TGT_DC_REALM cleared" \
    (set -q TGT_DC_REALM; echo $status) -ne 0
_test_teardown

#
# Stale marker (pointing at a removed DC) is auto-cleared on restore.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
_tgt_dc_set_active dante ghost
@test "restore_active: missing-target marker is cleared" \
    (_tgt_dc_restore_active dante; _tgt_dc_get_active dante 2>/dev/null; echo $status) -ne 0
_test_teardown
