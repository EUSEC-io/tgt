source (status dirname)/helpers.fish

#
# Edit wizard with all-Enter answers (use the prefilled defaults)
# leaves the entry exactly as it was.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 \
    --domain dante.local \
    --kdc-host dc01.dante.local --kdc-ip 10.10.10.5 \
    --admin-host dc01.dante.local --admin-ip 10.10.10.5 \
    >/dev/null

# All-empty answers keep every field at its current value. Six
# prompts in order: domain, realm, kdc-host, kdc-ip, admin-host,
# admin-ip.
set -gx TGT_ASK_QUEUE "" "" "" "" "" ""
_tgt_dc_edit_wizard dante dc01 >/dev/null

@test "edit (all-defaults): TGT_DC_DOMAIN unchanged" \
    "$TGT_DC_DOMAIN" = dante.local
@test "edit (all-defaults): TGT_DC_REALM unchanged" \
    "$TGT_DC_REALM" = DANTE.LOCAL
@test "edit (all-defaults): TGT_DC_HOST unchanged" \
    "$TGT_DC_HOST" = dc01.dante.local
@test "edit (all-defaults): TGT_DC_IP unchanged" \
    "$TGT_DC_IP" = 10.10.10.5
@test "edit (all-defaults): TGT_DC_ADMIN_HOST unchanged" \
    "$TGT_DC_ADMIN_HOST" = dc01.dante.local
@test "edit (all-defaults): TGT_DC_ADMIN_IP unchanged" \
    "$TGT_DC_ADMIN_IP" = 10.10.10.5
_test_teardown

#
# Edit + clear via `!` sentinel: user types `!` for kdc-host to
# drop it. kdc-ip stays via empty (keep). Resulting state: krb5
# falls back to IP, /etc/hosts entry dropped.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 \
    --domain dante.local \
    --kdc-host dc01.dante.local --kdc-ip 10.10.10.5 \
    >/dev/null

# Queue order: domain, realm, kdc-host, kdc-ip, admin-host, admin-ip.
# `!` clears, "" keeps the default.
set -gx TGT_ASK_QUEUE "" "" "!" "" "" ""
_tgt_dc_edit_wizard dante dc01 >/dev/null

@test "edit (clear kdc-host with '!'): TGT_DC_HOST cleared" \
    (set -q TGT_DC_HOST; echo $status) -ne 0
@test "edit (clear kdc-host with '!'): TGT_DC_IP retained" \
    "$TGT_DC_IP" = 10.10.10.5
@test "edit (clear kdc-host with '!'): krb5 kdc switched from host to IP" \
    (cat $TGT_KRB5_FILE | string match -q '*kdc = 10.10.10.5*'; echo $status) -eq 0
@test "edit (clear kdc-host with '!'): /etc/hosts entry dropped" \
    (cat $TGT_HOSTS_FILE | string match -q '*tgt:dc:dante:dc01*'; echo $status) -ne 0
_test_teardown

#
# Gum's input pre-fill puts the cursor at the end of the default
# value, so typing `!` without first deleting yields "<default>!".
# That form is also recognized as a clear-intent.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 --domain dante.local --kdc-host dc01.dante.local --kdc-ip 10.10.10.5 >/dev/null

set -gx TGT_ASK_QUEUE "" "" "" "10.10.10.5!" "" ""
_tgt_dc_edit_wizard dante dc01 >/dev/null

@test "edit (gum-prefill clear: '<default>!'): IP cleared" \
    (set -q TGT_DC_IP; echo $status) -ne 0
@test "edit (gum-prefill clear: '<default>!'): host retained" \
    "$TGT_DC_HOST" = dc01.dante.local
_test_teardown

#
# Clearing the IP via `!` and keeping the host: IP stays cleared.
# The resolver doesn't re-fill it (skip-on-explicit-clear).
#
_test_setup_home
echo "10.10.10.5 dc01.dante.local" > $TGT_HOSTS_FILE
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 --domain dante.local --kdc-host dc01.dante.local --kdc-ip 10.10.10.5 >/dev/null

# Queue: domain "" (keep), realm "" (keep), kdc-host "" (keep),
# kdc-ip "!" (clear), admin-host "" (keep), admin-ip "" (keep).
set -gx TGT_ASK_QUEUE "" "" "" "!" "" ""
_tgt_dc_edit_wizard dante dc01 >/dev/null

@test "edit (clear kdc-ip with '!'): TGT_DC_IP cleared" \
    (set -q TGT_DC_IP; echo $status) -ne 0
@test "edit (clear kdc-ip with '!'): TGT_DC_HOST retained" \
    "$TGT_DC_HOST" = dc01.dante.local
_test_teardown

#
# Editing the active DC reflects new values in env after save.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 --domain dante.local --kdc-ip 10.10.10.5 >/dev/null
# Change the IP to .6 — leave domain/realm at defaults, drop kdc-host
# stays empty, drop admin fields.
set -gx TGT_ASK_QUEUE \
    "" \
    "" \
    "" \
    10.10.10.6 \
    "" \
    ""
_tgt_dc_edit_wizard dante dc01 >/dev/null

@test "edit (active DC, change IP): TGT_DC_IP updated" \
    "$TGT_DC_IP" = 10.10.10.6
@test "edit (active DC, change IP): TGT_DC reflects new IP" \
    "$TGT_DC" = 10.10.10.6
@test "edit (active DC): krb5 picked up new kdc" \
    (cat $TGT_KRB5_FILE | string match -q '*kdc = 10.10.10.6*'; echo $status) -eq 0
_test_teardown

#
# Editing a non-active DC saves to disk but doesn't touch the
# currently-active runtime env.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 --domain dante.local --kdc-ip 10.10.10.5 >/dev/null
tgt dc new dc02 --domain dante2.local --kdc-ip 10.10.10.6 >/dev/null
# dc02 is now active. Edit dc01 — runtime should still reflect dc02.
set -gx TGT_ASK_QUEUE \
    "" \
    "" \
    "" \
    10.10.10.99 \
    "" \
    ""
_tgt_dc_edit_wizard dante dc01 >/dev/null

@test "edit (non-active DC): runtime env points at the active dc02" \
    "$TGT_DC_NAME" = dc02
@test "edit (non-active DC): TGT_DC_IP from active (dc02), not edited (dc01)" \
    "$TGT_DC_IP" = 10.10.10.6

# Reload dc01 to confirm the edit persisted to disk.
_tgt_dc_clear_runtime
_tgt_dc_load dante dc01
@test "edit (non-active DC): edited value persisted on disk" \
    "$TGT_DC_IP" = 10.10.10.99
_test_teardown

#
# Editing the realm flips default_realm in krb5 when DC is active.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 --domain dante.local --kdc-ip 10.10.10.5 >/dev/null
@test "edit setup: default_realm starts at DANTE.LOCAL" \
    (cat $TGT_KRB5_FILE | string match -q '*default_realm = DANTE.LOCAL*'; echo $status) -eq 0

set -gx TGT_ASK_QUEUE \
    "" \
    OTHER.REALM \
    "" \
    10.10.10.5 \
    "" \
    ""
_tgt_dc_edit_wizard dante dc01 >/dev/null

@test "edit (active DC, change realm): TGT_DC_REALM updated" \
    "$TGT_DC_REALM" = OTHER.REALM
@test "edit (active DC, change realm): default_realm in krb5 updated" \
    (cat $TGT_KRB5_FILE | string match -q '*default_realm = OTHER.REALM*'; echo $status) -eq 0
@test "edit (active DC, change realm): old realm name gone from default" \
    (cat $TGT_KRB5_FILE | string match -q '*default_realm = DANTE.LOCAL*'; echo $status) -ne 0
_test_teardown

#
# UX note: empty answers in the wizard mean "keep current" (the
# prompt's default). Clearing a field via the wizard isn't supported
# — to drop a field, remove and recreate the entry. The validation
# below applies only when both kdc-host and kdc-ip start empty (e.g.
# a malformed entry edited in test mode), which is essentially never.
#

#
# Edit on a missing entry errors fast (no prompts).
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
@test "edit: missing alias → non-zero" \
    (_tgt_dc_edit_wizard dante ghost 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# CLI: `tgt dc edit <alias>` dispatches to the wizard.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 --domain dante.local --kdc-ip 10.10.10.5 >/dev/null
set -gx TGT_ASK_QUEUE \
    "" \
    "" \
    "" \
    10.10.10.42 \
    "" \
    ""
tgt dc edit dc01 >/dev/null
@test "tgt dc edit: dispatches and updates TGT_DC_IP" \
    "$TGT_DC_IP" = 10.10.10.42
_test_teardown

#
# CLI: `tgt dc edit` with no alias errors when no DCs exist.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
@test "tgt dc edit (no DCs): non-zero" \
    (tgt dc edit 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# CLI: `tgt dc edit` with nonexistent alias errors before prompting.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 --domain dante.local --kdc-ip 10.10.10.5 >/dev/null
@test "tgt dc edit: nonexistent alias → non-zero" \
    (tgt dc edit ghost 2>/dev/null; echo $status) -ne 0
_test_teardown
