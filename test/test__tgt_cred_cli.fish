source (status dirname)/helpers.fish

#
# tgt cred: errors when no active scenario.
#
_test_setup_home
@test "cred_cli: errors when no scenario active" \
    (_tgt_cred_cli list 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# tgt cred list: empty scenario → friendly note.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -l out (_tgt_cred_cli list 2>&1 | string collect)
@test "cred_cli list: empty → 'no credentials recorded' note" \
    (string match -q '*no credentials recorded*' -- $out; echo $status) -eq 0
_test_teardown

#
# tgt cred new <alias> --username --password --domain --notes:
# flag-driven create.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_cred_cli new admin \
    --username Administrator \
    --password hunter2 \
    --domain dante.local \
    --notes "default admin" \
    >/dev/null

@test "cred_cli new: file created" \
    (_tgt_cred_exists dante admin; echo $status) -eq 0
@test "cred_cli new: TGT_USERNAME exported (active)" \
    "$TGT_USERNAME" = Administrator
@test "cred_cli new: TGT_PASSWORD exported (active)" \
    "$TGT_PASSWORD" = hunter2
@test "cred_cli new: TGT_CRED_NAME exported" \
    "$TGT_CRED_NAME" = admin
@test "cred_cli new: TGT_CRED_DOMAIN exported" \
    "$TGT_CRED_DOMAIN" = dante.local
@test "cred_cli new: TGT_CRED_NOTES exported" \
    "$TGT_CRED_NOTES" = "default admin"
@test "cred_cli new: marker written" \
    (_tgt_cred_get_active dante) = admin
_test_teardown

#
# tgt cred new: --username is required.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
@test "cred_cli new: missing --username → non-zero" \
    (_tgt_cred_cli new admin --password hunter2 2>/dev/null; echo $status) -ne 0
@test "cred_cli new: invalid alias → non-zero" \
    (_tgt_cred_cli new "bad alias" --username admin 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# tgt cred new: duplicate alias rejected.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_cred_cli new admin --username Administrator >/dev/null
@test "cred_cli new: duplicate alias rejected" \
    (_tgt_cred_cli new admin --username Other 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# tgt cred new: NTLM hash form goes straight into password field.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_cred_cli new admin-hash \
    --username Administrator \
    --password 'aad3b435b51404eeaad3b435b51404ee:31d6cfe0d16ae931b73c59d7e0c089c0' \
    >/dev/null
@test "cred_cli new (hash): TGT_PASSWORD has hash" \
    "$TGT_PASSWORD" = 'aad3b435b51404eeaad3b435b51404ee:31d6cfe0d16ae931b73c59d7e0c089c0'
_test_teardown

#
# tgt cred list: lists active scenario's creds in a table.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_cred_cli new admin --username Administrator --password hunter2 --domain dante.local >/dev/null
_tgt_cred_cli new svc-sql --username sql_svc --notes "discovered via kerberoasting" >/dev/null
set -l out (_tgt_cred_cli list 2>&1 | string collect)
@test "cred_cli list: shows admin" \
    (string match -q '*admin*' -- $out; echo $status) -eq 0
@test "cred_cli list: shows svc-sql" \
    (string match -q '*svc-sql*' -- $out; echo $status) -eq 0
@test "cred_cli list: shows the password-loaded marker for admin" \
    (string match -q '*pw:Y*' -- $out; echo $status) -eq 0
_test_teardown

#
# tgt cred show <alias>: detailed view.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_cred_cli new admin \
    --username Administrator \
    --password hunter2 \
    --domain dante.local \
    --notes "default admin" \
    >/dev/null
set -l out (_tgt_cred_cli show admin 2>&1 | string collect)
@test "cred_cli show: alias displayed" \
    (string match -q '*alias:*admin*' -- $out; echo $status) -eq 0
@test "cred_cli show: username displayed" \
    (string match -q '*username:*Administrator*' -- $out; echo $status) -eq 0
@test "cred_cli show: password is displayed (you asked for it)" \
    (string match -q '*password:*hunter2*' -- $out; echo $status) -eq 0
@test "cred_cli show: domain displayed" \
    (string match -q '*domain:*dante.local*' -- $out; echo $status) -eq 0
@test "cred_cli show: notes displayed" \
    (string match -q '*notes:*default admin*' -- $out; echo $status) -eq 0
_test_teardown

#
# tgt cred list: password column reads `pw:Y/N` by default — the
# actual value is never echoed unless --show-passwords is passed.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_cred_cli new admin --username Administrator --password hunter2 >/dev/null
_tgt_cred_cli new bob   --username Bob           --password bobpass >/dev/null

set -l plain (_tgt_cred_cli list 2>&1 | string collect)
@test "cred_cli list: password column reads pw:Y by default (admin)" \
    (string match -q '*pw:Y*' -- $plain; echo $status) -eq 0
@test "cred_cli list: hunter2 NOT echoed by default" \
    (string match -q '*hunter2*' -- $plain; echo $status) -ne 0
@test "cred_cli list: bobpass NOT echoed by default" \
    (string match -q '*bobpass*' -- $plain; echo $status) -ne 0

set -l revealed (_tgt_cred_cli list --show-passwords 2>&1 | string collect)
@test "cred_cli list --show-passwords: hunter2 visible" \
    (string match -q '*hunter2*' -- $revealed; echo $status) -eq 0
@test "cred_cli list --show-passwords: bobpass visible" \
    (string match -q '*bobpass*' -- $revealed; echo $status) -eq 0
@test "cred_cli list --show-passwords: pw:Y column replaced with value" \
    (string match -q '*pw:Y*' -- $revealed; echo $status) -ne 0
_test_teardown

#
# Alias defaults to --username when no positional alias is passed,
# but only when the username is itself a valid alias.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_cred_cli new --username svc.sql --password p >/dev/null
@test "cred_cli new (no alias, valid username): alias = username" \
    (_tgt_cred_exists dante svc.sql; echo $status) -eq 0
@test "cred_cli new (no alias, valid username): TGT_CRED_NAME set" \
    "$TGT_CRED_NAME" = svc.sql
_test_teardown

#
# Alias defaults are skipped when the username isn't alias-safe
# (e.g. `DOMAIN\user`, `张三`). User has to specify an alias explicitly.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
@test "cred_cli new (no alias, weird username): errors" \
    (_tgt_cred_cli new --username 'DANTE\\admin' --password p 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# `.` is allowed inside an alias (e.g. j.doe, svc.sql) but not at
# the start.
#
@test "cred_validate_name: allows dot inside" \
    (_tgt_cred_validate_name j.doe; echo $status) -eq 0
@test "cred_validate_name: allows dot inside (multi)" \
    (_tgt_cred_validate_name svc.sql.prod; echo $status) -eq 0
@test "cred_validate_name: rejects leading dot" \
    (_tgt_cred_validate_name .hidden; echo $status) -ne 0
@test "cred_validate_name: rejects bare ." \
    (_tgt_cred_validate_name . ; echo $status) -ne 0
@test "cred_validate_name: rejects bare .." \
    (_tgt_cred_validate_name .. ; echo $status) -ne 0

#
# tgt cred switch: activates an existing cred.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_cred_cli new admin --username Administrator --password hunter2 >/dev/null
_tgt_cred_cli new bob --username Bob --password bobpass >/dev/null
# bob is now active (last-added). Switch back to admin.
_tgt_cred_cli switch admin >/dev/null
@test "cred_cli switch: TGT_USERNAME → Administrator" \
    "$TGT_USERNAME" = Administrator
@test "cred_cli switch: TGT_CRED_NAME → admin" \
    "$TGT_CRED_NAME" = admin
@test "cred_cli switch: marker repointed" \
    (_tgt_cred_get_active dante) = admin
@test "cred_cli switch: nonexistent rejected" \
    (_tgt_cred_cli switch ghost 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# tgt cred unset: clears env + marker.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_cred_cli new admin --username Administrator --password hunter2 >/dev/null
_tgt_cred_cli unset >/dev/null
@test "cred_cli unset: TGT_USERNAME cleared" \
    (set -q TGT_USERNAME; echo $status) -ne 0
@test "cred_cli unset: TGT_PASSWORD cleared" \
    (set -q TGT_PASSWORD; echo $status) -ne 0
@test "cred_cli unset: TGT_CRED_NAME cleared" \
    (set -q TGT_CRED_NAME; echo $status) -ne 0
@test "cred_cli unset: marker removed" \
    (_tgt_cred_get_active dante 2>/dev/null; echo $status) -ne 0
@test "cred_cli unset (clean state): exits 0" \
    (_tgt_cred_cli unset >/dev/null; echo $status) -eq 0
_test_teardown

#
# tgt cred rm: removes the named cred, clears env + marker if active.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_cred_cli new admin --username Administrator >/dev/null
_tgt_cred_cli new bob --username Bob >/dev/null
# bob is active.
_tgt_cred_cli rm admin >/dev/null
@test "cred_cli rm (non-active): admin gone" \
    (_tgt_cred_exists dante admin; echo $status) -ne 0
@test "cred_cli rm (non-active): bob still active" \
    "$TGT_CRED_NAME" = bob

_tgt_cred_cli rm bob >/dev/null
@test "cred_cli rm (active): bob gone" \
    (_tgt_cred_exists dante bob; echo $status) -ne 0
@test "cred_cli rm (active): TGT_USERNAME cleared" \
    (set -q TGT_USERNAME; echo $status) -ne 0
@test "cred_cli rm (active): marker cleared" \
    (_tgt_cred_get_active dante 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# tgt cred rename: 2-arg explicit + 1-arg renames active.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_cred_cli new admin --username Administrator >/dev/null
_tgt_cred_cli rename admin admin-pri >/dev/null
@test "cred_cli rename (2-arg): new file exists" \
    (_tgt_cred_exists dante admin-pri; echo $status) -eq 0
@test "cred_cli rename (2-arg): old gone" \
    (_tgt_cred_exists dante admin; echo $status) -ne 0
@test "cred_cli rename (2-arg): marker repointed" \
    (_tgt_cred_get_active dante) = admin-pri
@test "cred_cli rename (2-arg): TGT_CRED_NAME updated in shell" \
    "$TGT_CRED_NAME" = admin-pri

# 1-arg form: renames the active one.
_tgt_cred_cli rename admin-final >/dev/null
@test "cred_cli rename (1-arg): renames active" \
    (_tgt_cred_exists dante admin-final; echo $status) -eq 0

@test "cred_cli rename: nonexistent old → non-zero" \
    (_tgt_cred_cli rename ghost foo 2>/dev/null; echo $status) -ne 0
@test "cred_cli rename: same name → non-zero" \
    (_tgt_cred_cli rename admin-final admin-final 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# tgt cred: unknown subcommand returns non-zero.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
@test "cred_cli: unknown verb returns non-zero" \
    (_tgt_cred_cli garbage 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# `tgt cred` (no args) drops into the switch picker (mirrors
# `tgt dc`). With no creds → friendly note.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -l out (_tgt_cred_cli 2>&1 | string collect)
@test "cred_cli (no args, empty): friendly note" \
    (string match -q '*no credentials recorded*' -- $out; echo $status) -eq 0

_tgt_cred_cli new admin --username Administrator >/dev/null
_tgt_cred_cli new bob --username Bob >/dev/null
# bob is active. Pick admin via TEST_RESULT bypass.
set -gx TGT_PICKER_TEST_RESULT admin
_tgt_cred_cli >/dev/null
@test "cred_cli (no args, with creds): picker activated chosen" \
    "$TGT_CRED_NAME" = admin
set -e TGT_PICKER_TEST_RESULT
_test_teardown

#
# Top-level dispatch: `tgt cred …` reaches _tgt_cred_cli.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
tgt cred new admin --username Administrator --password hunter2 >/dev/null
@test "top-level: 'tgt cred new' dispatched correctly" \
    (_tgt_cred_exists dante admin; echo $status) -eq 0
_test_teardown

#
# Scenario switch restores per-scenario active cred.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
tgt cred new admin --username Administrator --password hunter2 >/dev/null
_tgt_scenario_cli new acme >/dev/null
tgt cred new alice --username alice --password alicepass >/dev/null
# alice is active in acme now.

_tgt_scenario_cli switch dante >/dev/null
@test "scenario switch restores dante's active cred" \
    "$TGT_CRED_NAME" = admin
@test "scenario switch: TGT_USERNAME flips to dante's" \
    "$TGT_USERNAME" = Administrator

_tgt_scenario_cli switch acme >/dev/null
@test "scenario switch (acme): TGT_CRED_NAME → alice" \
    "$TGT_CRED_NAME" = alice
@test "scenario switch (acme): TGT_USERNAME flips" \
    "$TGT_USERNAME" = alice
_test_teardown

#
# Scenario without active-cred marker: switching in clears any
# stale TGT_USERNAME / TGT_PASSWORD from the previous scenario.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
tgt cred new admin --username Administrator --password hunter2 >/dev/null
_tgt_scenario_cli new acme >/dev/null
@test "scenario switch (acme, no creds): TGT_USERNAME cleared" \
    (set -q TGT_USERNAME; echo $status) -ne 0
@test "scenario switch (acme, no creds): TGT_CRED_NAME cleared" \
    (set -q TGT_CRED_NAME; echo $status) -ne 0
_test_teardown
