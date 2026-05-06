source (status dirname)/helpers.fish

#
# 2-arg rename: explicit old + new.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 \
    --domain dante.local \
    --kdc-host dc01.dante.local --kdc-ip 10.10.10.5 \
    >/dev/null
_tgt_dc_cli rename dc01 dc-primary >/dev/null

@test "dc rename: new file exists" \
    (_tgt_dc_exists dante dc-primary; echo $status) -eq 0
@test "dc rename: old file gone" \
    (_tgt_dc_exists dante dc01; echo $status) -ne 0
@test "dc rename: marker repointed to new alias (renamed was active)" \
    (_tgt_dc_get_active dante) = dc-primary
@test "dc rename: TGT_DC_NAME updated in shell" \
    "$TGT_DC_NAME" = dc-primary
@test "dc rename: krb5 comment carries new alias" \
    (cat $TGT_KRB5_FILE | string match -q '*tgt:dc:dante:dc-primary*'; echo $status) -eq 0
@test "dc rename: krb5 old alias gone from comment" \
    (cat $TGT_KRB5_FILE | string match -q '*tgt:dc:dante:dc01*'; echo $status) -ne 0
@test "dc rename: hosts tag carries new alias" \
    (cat $TGT_HOSTS_FILE | string match -q '*tgt:dc:dante:dc-primary*'; echo $status) -eq 0
@test "dc rename: hosts old tag gone" \
    (cat $TGT_HOSTS_FILE | string match -q '*tgt:dc:dante:dc01*'; echo $status) -ne 0
_test_teardown

#
# 1-arg rename: renames the active DC.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 --domain dante.local --kdc-ip 10.10.10.5 >/dev/null
# dc01 is active. Rename with one arg.
_tgt_dc_cli rename dc-foo >/dev/null
@test "dc rename (1-arg): renamed active dc01 → dc-foo" \
    (_tgt_dc_exists dante dc-foo; echo $status) -eq 0
@test "dc rename (1-arg): TGT_DC_NAME updated to dc-foo" \
    "$TGT_DC_NAME" = dc-foo
_test_teardown

#
# Renaming a NON-active DC: marker for the active one stays put,
# runtime env stays put.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 --domain dante.local --kdc-ip 10.10.10.5 >/dev/null
tgt dc new dc02 --domain dante2.local --kdc-ip 10.10.10.6 >/dev/null
# dc02 is now active (last-added wins).
_tgt_dc_cli rename dc01 dc-renamed >/dev/null

@test "dc rename (non-active): renamed file moved" \
    (_tgt_dc_exists dante dc-renamed; echo $status) -eq 0
@test "dc rename (non-active): active marker still dc02" \
    (_tgt_dc_get_active dante) = dc02
@test "dc rename (non-active): TGT_DC_NAME unchanged" \
    "$TGT_DC_NAME" = dc02
_test_teardown

#
# Validation: invalid new name, missing old, existing new, same name.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 --domain dante.local --kdc-ip 10.10.10.5 >/dev/null
tgt dc new dc02 --domain dante.local --kdc-ip 10.10.10.6 >/dev/null

@test "dc rename: rejects invalid new name" \
    (_tgt_dc_cli rename dc01 "bad name" 2>/dev/null; echo $status) -ne 0
@test "dc rename: rejects nonexistent old" \
    (_tgt_dc_cli rename ghost foo 2>/dev/null; echo $status) -ne 0
@test "dc rename: rejects new == existing" \
    (_tgt_dc_cli rename dc01 dc02 2>/dev/null; echo $status) -ne 0
@test "dc rename: rejects same name" \
    (_tgt_dc_cli rename dc01 dc01 2>/dev/null; echo $status) -ne 0
@test "dc rename (no args): non-zero with usage" \
    (_tgt_dc_cli rename 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# Same-realm merge: two DCs share a realm; renaming one keeps the
# merged block intact (apply re-emits with new alias in the
# combined comment).
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 --domain dante.local --kdc-host DC01.dante.local >/dev/null
tgt dc new dc02 --domain dante.local --kdc-host DC02.dante.local >/dev/null
_tgt_dc_cli rename dc01 dc-primary >/dev/null
set -l content (cat $TGT_KRB5_FILE | string collect)

@test "dc rename (merged realm): comment lists renamed alias" \
    (string match -q '*tgt:dc:dante:dc-primary+dc02*' -- $content; echo $status) -eq 0
@test "dc rename (merged realm): old alias gone from comment" \
    (string match -q '*dc01+*' -- $content; echo $status) -ne 0
@test "dc rename (merged realm): both kdcs still present" \
    (string match -q '*kdc = DC01.dante.local*' -- $content; echo $status) -eq 0
@test "dc rename (merged realm): dc02 kdc still present" \
    (string match -q '*kdc = DC02.dante.local*' -- $content; echo $status) -eq 0
_test_teardown

#
# CLI: `tgt dc rename` reachable through the top-level dispatcher.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 --domain dante.local --kdc-ip 10.10.10.5 >/dev/null
tgt dc rename dc01 dc-renamed >/dev/null
@test "tgt dc rename: dispatched correctly" \
    (_tgt_dc_exists dante dc-renamed; echo $status) -eq 0
_test_teardown
