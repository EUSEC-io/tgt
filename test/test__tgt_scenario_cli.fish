source (status dirname)/helpers.fish

#
# new: creates the scenario and switches to it
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
@test "scenario new: scenario exists in registry" \
    (_tgt_scenario_exists dante; echo $status) -eq 0
@test "scenario new: TGT_SCENARIO is set to the new scenario" "$TGT_SCENARIO" = dante
_test_teardown

#
# new: rejects bad name
#
_test_setup_home
@test "scenario new: rejects invalid name" \
    (_tgt_scenario_cli new "bad name" 2>/dev/null; echo $status) -ne 0
@test "scenario new: TGT_SCENARIO unset after invalid create" \
    (set -q TGT_SCENARIO; echo $status) -ne 0
_test_teardown

#
# new: rejects duplicate
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
@test "scenario new: rejects existing scenario" \
    (_tgt_scenario_cli new dante 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# list: empty / populated, marks active
#
_test_setup_home
@test "scenario list: empty" (_tgt_scenario_cli list) = "(no scenarios)"
_tgt_scenario_cli new dante >/dev/null
_tgt_scenario_cli new acme >/dev/null
set -gx TGT_SCENARIO dante
# Strip ANSI escape codes so regex assertions don't trip on them.
set -l raw (_tgt_scenario_cli list)
set -l output (string replace -ar '\e\[[0-9;]*m' '' -- $raw | string replace -ar '\e\(B' '')
# Output: 1 header line + 2 scenarios.
@test "scenario list: 3 lines (header + 2 scenarios)" \
    (count $output) -eq 3
@test "scenario list: header row present" \
    (string match -rq '^\s*scenario\s+targets\s+creds\s+DCs' -- $output; echo $status) -eq 0
@test "scenario list: marks dante active with leading *" \
    (string match -rq '^\* dante' -- $output; echo $status) -eq 0
@test "scenario list: shows acme without active marker" \
    (string match -rq '^  acme' -- $output; echo $status) -eq 0
_test_teardown

#
# list: shows aggregate state per scenario (target count, creds
# count, dc count). Both creds and DCs are scenario-level entities.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 10.10.10.10
_tgt_target_cli new dc01 --no-edit >/dev/null
_tgt_target_save dante dc01
set -gx TGT 10.10.10.20
_tgt_target_cli new web01 --no-edit >/dev/null
_tgt_target_save dante web01
set -e TGT
# One DC entry + one cred entry in dante so both columns show >0.
tgt dc new realdc --domain dante.local --kdc-ip 10.10.10.10 >/dev/null
tgt cred new admin --username Administrator --password hunter2 >/dev/null

_tgt_scenario_cli new acme >/dev/null   # empty scenario, no targets

set -gx TGT_SCENARIO dante
set -l raw2 (_tgt_scenario_cli list)
set -l output (string replace -ar '\e\[[0-9;]*m' '' -- $raw2 | string replace -ar '\e\(B' '')

@test "scenario list: dante row shows target count 2" \
    (string match -rq 'dante\s+2\s+' -- $output; echo $status) -eq 0
@test "scenario list: dante row shows creds=1, DCs=1" \
    (string match -rq 'dante\s+2\s+1\s+1' -- $output; echo $status) -eq 0
@test "scenario list: acme row shows target count 0, creds=0, DCs=0" \
    (string match -rq 'acme\s+0\s+0\s+0' -- $output; echo $status) -eq 0
_test_teardown

#
# switch: changes the active scenario
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_scenario_cli new acme >/dev/null
_tgt_scenario_cli switch dante >/dev/null
@test "scenario switch: TGT_SCENARIO updated" "$TGT_SCENARIO" = dante
_test_teardown

#
# switch: refuses unknown scenario
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
@test "scenario switch: rejects nonexistent" \
    (_tgt_scenario_cli switch nope 2>/dev/null; echo $status) -ne 0
@test "scenario switch: TGT_SCENARIO unchanged after failed switch" \
    "$TGT_SCENARIO" = dante
_test_teardown

#
# unload: clears all TGT_* runtime (scenario / target / cred / DC).
# Nothing on disk should be touched — re-loading should restore.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 10.10.10.5
set -gx TGT_PORT 445
set -gx TGT_HOSTS web01.dante.local
_tgt_target_cli new web01 --no-edit >/dev/null
tgt dc new dc01 --domain dante.local --kdc-ip 10.10.10.10 >/dev/null
tgt cred new admin --username Administrator --password hunter2 >/dev/null

# Sanity: everything is loaded.
@test "unload (pre): TGT_SCENARIO set" "$TGT_SCENARIO" = dante
@test "unload (pre): TGT_ACTIVE set" "$TGT_ACTIVE" = web01
@test "unload (pre): TGT_DC_NAME set" "$TGT_DC_NAME" = dc01
@test "unload (pre): TGT_CRED_NAME set" "$TGT_CRED_NAME" = admin

_tgt_scenario_cli unload >/dev/null

@test "unload: TGT_SCENARIO cleared" \
    (set -q TGT_SCENARIO; echo $status) -ne 0
@test "unload: TGT_ACTIVE cleared" \
    (set -q TGT_ACTIVE; echo $status) -ne 0
@test "unload: TGT cleared" \
    (set -q TGT; echo $status) -ne 0
@test "unload: TGT_PORT cleared" \
    (set -q TGT_PORT; echo $status) -ne 0
@test "unload: TGT_HOSTS cleared" \
    (set -q TGT_HOSTS; echo $status) -ne 0
@test "unload: TGT_CRED_NAME cleared" \
    (set -q TGT_CRED_NAME; echo $status) -ne 0
@test "unload: TGT_USERNAME cleared" \
    (set -q TGT_USERNAME; echo $status) -ne 0
@test "unload: TGT_PASSWORD cleared" \
    (set -q TGT_PASSWORD; echo $status) -ne 0
@test "unload: TGT_DC_NAME cleared" \
    (set -q TGT_DC_NAME; echo $status) -ne 0
@test "unload: scenario still exists on disk" \
    (_tgt_scenario_exists dante; echo $status) -eq 0
@test "unload: target still exists on disk" \
    (_tgt_target_exists dante web01; echo $status) -eq 0

# Re-entering restores everything from disk (cred + DC active markers).
_tgt_scenario_cli switch dante >/dev/null
@test "unload + switch back: TGT_SCENARIO restored" "$TGT_SCENARIO" = dante
@test "unload + switch back: TGT_CRED_NAME restored (active marker honored)" \
    "$TGT_CRED_NAME" = admin
@test "unload + switch back: TGT_DC_NAME restored (active marker honored)" \
    "$TGT_DC_NAME" = dc01
_test_teardown

#
# unload: idempotent / safe when nothing was loaded.
#
_test_setup_home
@test "unload (clean state): exits 0" \
    (_tgt_scenario_cli unload >/dev/null 2>&1; echo $status) -eq 0
@test "unload (clean state): TGT_SCENARIO still unset" \
    (set -q TGT_SCENARIO; echo $status) -ne 0
_test_teardown

#
# show: defaults to active scenario
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -l output (_tgt_scenario_cli show)
@test "scenario show: prints scenario name when TGT_SCENARIO set" \
    (string match -rq 'scenario:\s+dante' -- $output; echo $status) -eq 0
@test "scenario show: marks active=yes for the active one" \
    (string match -rq 'active:\s+yes' -- $output; echo $status) -eq 0
_test_teardown

#
# show: explicit name, marks non-active
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_scenario_cli new acme >/dev/null
set -gx TGT_SCENARIO dante
set -l output (_tgt_scenario_cli show acme)
@test "scenario show <name>: prints the named scenario" \
    (string match -rq 'scenario:\s+acme' -- $output; echo $status) -eq 0
@test "scenario show <name>: marks active=no for non-active" \
    (string match -rq 'active:\s+no' -- $output; echo $status) -eq 0
_test_teardown

#
# show: errors when no active and no arg
#
_test_setup_home
@test "scenario show: errors when no active and no arg" \
    (_tgt_scenario_cli show 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# rm: removes registry, hosts entries, and clears active if it was this one
#
_test_setup_home
set -gx TGT_HOSTS_FILE (mktemp)
printf "127.0.0.1\tlocalhost\n10.10.10.5 host.dante # tgt:dante:web01\n10.20.30.5 host.acme # tgt:acme:api\n" > $TGT_HOSTS_FILE
# Create scenarios via the low-level helper so the apply-on-new
# behavior doesn't scrub our pre-populated /etc/hosts fixture.
_tgt_scenario_create dante
_tgt_scenario_create acme
set -gx TGT_SCENARIO dante
_tgt_scenario_cli rm dante >/dev/null
@test "scenario rm: registry entry gone" \
    (_tgt_scenario_exists dante; echo $status) -ne 0
@test "scenario rm: hosts entry for dante gone" \
    (cat $TGT_HOSTS_FILE | string match -q "*tgt:dante:*"; echo $status) -ne 0
@test "scenario rm: hosts entry for acme preserved" \
    (cat $TGT_HOSTS_FILE | string match -q "*tgt:acme:*"; echo $status) -eq 0
@test "scenario rm: user line preserved" \
    (cat $TGT_HOSTS_FILE | string match -q "*localhost*"; echo $status) -eq 0
@test "scenario rm: TGT_SCENARIO cleared because dante was active" \
    (set -q TGT_SCENARIO; echo $status) -ne 0
_test_teardown

#
# rm: leaves TGT_SCENARIO alone if a different scenario is active
#
_test_setup_home
set -gx TGT_HOSTS_FILE (mktemp)
_tgt_scenario_cli new dante >/dev/null
_tgt_scenario_cli new acme >/dev/null
set -gx TGT_SCENARIO acme
_tgt_scenario_cli rm dante >/dev/null
@test "scenario rm: TGT_SCENARIO unchanged when removing non-active" \
    "$TGT_SCENARIO" = acme
_test_teardown

#
# rm: errors on missing scenario
#
_test_setup_home
@test "scenario rm: errors on nonexistent" \
    (_tgt_scenario_cli rm nope 2>/dev/null; echo $status) -ne 0
_test_teardown

#
# Unknown subcommand → error
#
@test "scenario: unknown subcommand returns nonzero" \
    (_tgt_scenario_cli garbage 2>/dev/null; echo $status) -ne 0

#
# Help: --help, -h, no-arg all return 0 and print something.
# (TGT_TEST_MODE forces the help path regardless of TTY, otherwise
# the no-arg case would open the interactive gum menu when this
# test file is run from a real terminal.)
#
set -gx TGT_TEST_MODE 1
@test "scenario --help: succeeds" \
    (_tgt_scenario_cli --help >/dev/null; echo $status) -eq 0
@test "scenario -h: succeeds" \
    (_tgt_scenario_cli -h >/dev/null; echo $status) -eq 0
@test "scenario (no args): prints help, succeeds" \
    (_tgt_scenario_cli >/dev/null; echo $status) -eq 0
set -e TGT_TEST_MODE

#
# _tgt_hosts_revoke_scenario directly: matches all targets in scenario
#
_test_setup_hosts multi_scenario.txt
_tgt_hosts_revoke_scenario dante
@test "_tgt_hosts_revoke_scenario: dante:web01 gone" \
    (cat $TGT_HOSTS_FILE | string match -rq "tgt:dante:web01\$"; echo $status) -ne 0
@test "_tgt_hosts_revoke_scenario: dante:dc01 gone" \
    (cat $TGT_HOSTS_FILE | string match -rq "tgt:dante:dc01\$"; echo $status) -ne 0
@test "_tgt_hosts_revoke_scenario: acme:api-gateway preserved" \
    (cat $TGT_HOSTS_FILE | string match -q "*tgt:customer-acme:api-gateway*"; echo $status) -eq 0
@test "_tgt_hosts_revoke_scenario: acme:webapp preserved" \
    (cat $TGT_HOSTS_FILE | string match -q "*tgt:customer-acme:webapp*"; echo $status) -eq 0
_test_teardown
