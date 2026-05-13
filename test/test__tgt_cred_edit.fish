source (status dirname)/helpers.fish

#
# Edit wizard: round-tripping a value with a space MUST NOT
# accumulate escape layers. Reproduces the bug Stefan hit in the
# field — TGT_CRED_DOMAIN went from "INLANE FREIGHT" → "'INLANE
# FREIGHT'" → "\"'INLANE FREIGHT'\"" → eventually a stray quote
# character — because the wizard read $m[3] raw (escaped form),
# kept it as the new value, then re-escaped on save.
#
# Wizard prompt order: username, password, domain, notes.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
tgt cred new admin --username Administrator --password hunter2 --domain 'INLANE FREIGHT' >/dev/null

# First edit cycle: keep every field (all empty answers).
set -gx TGT_ASK_QUEUE "" "" "" ""
_tgt_cred_edit_wizard dante admin >/dev/null

# Pull the raw saved value back to confirm no extra wrapping.
set -l line (_tgt_cred_read_fields dante admin)
set -l fields (string split \t -- $line)
@test "edit (keep all): domain unchanged after one cycle" \
    "$fields[3]" = "INLANE FREIGHT"

# Second edit cycle: keep again. If the bug existed, this round
# would wrap the (already-wrapped) value once more.
set -gx TGT_ASK_QUEUE "" "" "" ""
_tgt_cred_edit_wizard dante admin >/dev/null
set -l line2 (_tgt_cred_read_fields dante admin)
set -l fields2 (string split \t -- $line2)
@test "edit (keep all, 2nd cycle): domain still unchanged" \
    "$fields2[3]" = "INLANE FREIGHT"
_test_teardown

#
# Edit wizard: typing `!` on an optional field with a value-that-
# needs-escaping clears it cleanly (no leftover quote remnants).
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
tgt cred new admin --username Administrator --password hunter2 --domain 'INLANE FREIGHT' >/dev/null

# Prompt order: username, password, domain, notes.
# Keep username + password, clear domain, keep notes.
set -gx TGT_ASK_QUEUE "" "" "!" ""
_tgt_cred_edit_wizard dante admin >/dev/null

set -l line (_tgt_cred_read_fields dante admin)
set -l fields (string split \t -- $line)
@test "edit (clear domain with !): domain is empty" \
    "$fields[3]" = ""
@test "edit (clear domain with !): file has no TGT_CRED_DOMAIN line" \
    (grep -q "TGT_CRED_DOMAIN" (_tgt_cred_file dante admin); echo $status) -ne 0
_test_teardown

#
# Recovery: a file that was already corrupted by the old layered-
# escape bug (domain stored as a literal single quote, on disk as
# `_tgt_export TGT_CRED_DOMAIN "'"`) must still be clearable via
# the edit wizard.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
tgt cred new admin --username Administrator --password hunter2 >/dev/null

# Inject the corrupted form directly into the file, mimicking the
# bad state from Stefan's adunn cred.
set -l file (_tgt_cred_file dante admin)
echo "_tgt_export TGT_CRED_DOMAIN \"'\"" >> $file

# Sanity: read picks up the bad value as a literal single quote.
set -l before (_tgt_cred_read_fields dante admin)
set -l before_fields (string split \t -- $before)
@test "recovery (setup): bad domain reads as single-quote char" \
    "$before_fields[3]" = "'"

# Edit and clear with `!`.
set -gx TGT_ASK_QUEUE "" "" "!" ""
_tgt_cred_edit_wizard dante admin >/dev/null

set -l after (_tgt_cred_read_fields dante admin)
set -l after_fields (string split \t -- $after)
@test "recovery: domain cleared (no stray quote left)" \
    "$after_fields[3]" = ""
_test_teardown

#
# Mirror coverage for `_tgt_dc_edit_wizard`. Wizard prompt order:
# domain, realm, kdc-host, kdc-ip, admin-host, admin-ip.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
# Use a value with a space so escape kicks in (atypical but legal —
# realms / admin-host descriptors etc. could plausibly hold one).
tgt dc new dc01 --domain dante.local --realm 'DANTE LOCAL' \
    --kdc-host dc01.dante.local --kdc-ip 10.10.10.5 >/dev/null

# Keep everything.
set -gx TGT_ASK_QUEUE "" "" "" "" "" ""
_tgt_dc_edit_wizard dante dc01 >/dev/null

set -l line (_tgt_dc_inspect dante dc01)
set -l fields (string split \t -- $line)
@test "dc edit (keep all): realm unchanged across edit cycle" \
    "$fields[3]" = "DANTE LOCAL"

# Round-trip again.
set -gx TGT_ASK_QUEUE "" "" "" "" "" ""
_tgt_dc_edit_wizard dante dc01 >/dev/null
set -l line2 (_tgt_dc_inspect dante dc01)
set -l fields2 (string split \t -- $line2)
@test "dc edit (keep all, 2nd cycle): realm still unchanged" \
    "$fields2[3]" = "DANTE LOCAL"
_test_teardown
