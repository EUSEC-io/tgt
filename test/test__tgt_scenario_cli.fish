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
set -l output (_tgt_scenario_cli list)
@test "scenario list: returns 2 lines after creating 2 scenarios" \
    (count $output) -eq 2
@test "scenario list: marks dante active with leading *" \
    (string match -rq '^\* dante' -- $output; echo $status) -eq 0
@test "scenario list: shows acme without active marker" \
    (string match -rq '^  acme' -- $output; echo $status) -eq 0
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
_tgt_scenario_cli new dante >/dev/null
_tgt_scenario_cli new acme >/dev/null
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
