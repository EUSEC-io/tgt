source (status dirname)/helpers.fish

# Helper for tests: count user-managed (untagged) entry lines, ignoring
# comments and tgt-tagged lines.
function _test_user_lines
    cat $TGT_HOSTS_FILE | string match -rv "^\s*#" | string match -rv "# tgt:" | string match -rv "^\s*\$" | count
end

#
# _tgt_hosts_get: returns nothing for an empty file
#
_test_setup_hosts empty.txt
set -l got (_tgt_hosts_get default default)
@test "_tgt_hosts_get: empty file → no output" (count $got) -eq 0
_test_teardown

#
# _tgt_hosts_get: returns nothing when no matching tag
#
_test_setup_hosts user_managed.txt
set -l got (_tgt_hosts_get default default)
@test "_tgt_hosts_get: no tag match → no output" (count $got) -eq 0
_test_teardown

#
# _tgt_hosts_get: returns hostnames for a matching line
#
_test_setup_hosts single_target.txt
set -l got (_tgt_hosts_get default default)
@test "_tgt_hosts_get: returns hostnames as separate items" (count $got) -eq 2
@test "_tgt_hosts_get: first hostname matches" "$got[1]" = "forest.htb"
@test "_tgt_hosts_get: second hostname matches" "$got[2]" = "dc01.htb.local"
_test_teardown

#
# _tgt_hosts_add: creates a new line when none exists
#
_test_setup_hosts user_managed.txt
set -l user_before (_test_user_lines)
_tgt_hosts_add default default 10.10.10.5 forest.htb
set -l got (_tgt_hosts_get default default)
set -l user_after (_test_user_lines)
@test "_tgt_hosts_add: creates new tagged line" (count $got) -eq 1
@test "_tgt_hosts_add: hostname appears" "$got[1]" = "forest.htb"
@test "_tgt_hosts_add: user lines untouched" $user_before -eq $user_after
_test_teardown

#
# _tgt_hosts_add: appends to existing line, dedupes
#
_test_setup_hosts single_target.txt
_tgt_hosts_add default default 10.10.11.5 newhost.htb forest.htb
set -l got (_tgt_hosts_get default default)
@test "_tgt_hosts_add: line has 3 hostnames after appending one" (count $got) -eq 3
@test "_tgt_hosts_add: existing forest.htb still present" \
    (contains forest.htb $got; echo $status) -eq 0
@test "_tgt_hosts_add: existing dc01.htb.local still present" \
    (contains dc01.htb.local $got; echo $status) -eq 0
@test "_tgt_hosts_add: new newhost.htb present" \
    (contains newhost.htb $got; echo $status) -eq 0
_test_teardown

#
# _tgt_hosts_add: leaves untagged user lines alone
#
_test_setup_hosts mixed.txt
set -l user_before (_test_user_lines)
_tgt_hosts_add htb-forest forest 10.10.11.5 morehost.htb
set -l user_after (_test_user_lines)
@test "_tgt_hosts_add: user lines preserved when modifying tagged line" \
    $user_before -eq $user_after
_test_teardown

#
# _tgt_hosts_remove: removes specified hostnames, keeps the rest
#
_test_setup_hosts single_target.txt
_tgt_hosts_remove default default forest.htb
set -l got (_tgt_hosts_get default default)
@test "_tgt_hosts_remove: line still has remaining hostname" (count $got) -eq 1
@test "_tgt_hosts_remove: removed forest.htb is gone" \
    (contains forest.htb $got; echo $status) -ne 0
@test "_tgt_hosts_remove: kept dc01.htb.local" \
    (contains dc01.htb.local $got; echo $status) -eq 0
_test_teardown

#
# _tgt_hosts_remove: drops the line when no hostnames remain
#
_test_setup_hosts single_target.txt
_tgt_hosts_remove default default forest.htb dc01.htb.local
set -l got (_tgt_hosts_get default default)
set -l raw (cat $TGT_HOSTS_FILE)
set -l has_tag (string match -rq "tgt:default:default" -- $raw; echo $status)
@test "_tgt_hosts_remove: line gone after removing all hostnames" (count $got) -eq 0
@test "_tgt_hosts_remove: tag no longer present in file" $has_tag -ne 0
_test_teardown

#
# _tgt_hosts_revoke: drops the entire tagged line
#
_test_setup_hosts single_target.txt
set -l user_before (_test_user_lines)
_tgt_hosts_revoke default default
set -l got (_tgt_hosts_get default default)
set -l user_after (_test_user_lines)
@test "_tgt_hosts_revoke: target's line is gone" (count $got) -eq 0
@test "_tgt_hosts_revoke: user/system lines untouched" $user_before -eq $user_after
_test_teardown

#
# _tgt_hosts_revoke: only the named (scenario, target) line drops; siblings stay
#
_test_setup_hosts multi_target.txt
_tgt_hosts_revoke dante web01
set -l web01 (_tgt_hosts_get dante web01)
set -l dc01 (_tgt_hosts_get dante dc01)
set -l jumpbox (_tgt_hosts_get dante jumpbox)
@test "_tgt_hosts_revoke: targeted line gone" (count $web01) -eq 0
@test "_tgt_hosts_revoke: sibling dc01 preserved" (count $dc01) -ge 1
@test "_tgt_hosts_revoke: sibling jumpbox preserved" (count $jumpbox) -ge 1
_test_teardown

#
# Cross-scenario isolation: revoking one scenario's target doesn't touch another
#
_test_setup_hosts multi_scenario.txt
_tgt_hosts_revoke dante web01
set -l acme_api (_tgt_hosts_get customer-acme api-gateway)
set -l acme_web (_tgt_hosts_get customer-acme webapp)
@test "scenarios isolated: acme:api-gateway intact after dante:web01 revoke" \
    (count $acme_api) -ge 1
@test "scenarios isolated: acme:webapp intact after dante:web01 revoke" \
    (count $acme_web) -ge 1
_test_teardown

#
# Sudoless: write happens without ownership escalation under TGT_TEST_MODE
#
_test_setup_hosts user_managed.txt
set -l owner_before (stat -c '%U' $TGT_HOSTS_FILE)
_tgt_hosts_add default default 10.10.10.5 forest.htb
set -l owner_after (stat -c '%U' $TGT_HOSTS_FILE)
@test "_tgt_hosts_*: runs sudoless in test mode" "$owner_before" = "$owner_after"
_test_teardown

#
# Tag formatter
#
@test "_tgt_hosts_tag: formats correctly" \
    (_tgt_hosts_tag dante web01) = "# tgt:dante:web01"
