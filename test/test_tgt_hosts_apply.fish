source (status dirname)/helpers.fish

# Helper: count tagged entries for a given scenario
function _hosts_count_for
    set -l scen $argv[1]
    set -l file $argv[2]
    string match -re "# tgt:$scen:" -- (cat $file) | count
end

#
# After scenario switch from A to B: A's hosts revoked, B's added.
#
_test_setup_home
_test_setup_hosts empty.txt

# Build dante with two targets that have hostnames
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 10.10.10.5; set -gx TGT_HOSTS web01.dante.local intranet.dante.local
_tgt_target_cli new web01 --no-edit >/dev/null
_tgt_target_save dante web01
set -e TGT TGT_HOSTS

set -gx TGT 10.10.10.10; set -gx TGT_HOSTS dc01.dante.local
_tgt_target_cli new dc01 --no-edit >/dev/null
_tgt_target_save dante dc01
set -e TGT TGT_HOSTS

# Build acme with one target
_tgt_scenario_cli new acme >/dev/null   # scenario new triggers an apply: dante lines revoked
set -gx TGT 10.10.20.10; set -gx TGT_HOSTS api.acme.local
_tgt_target_cli new api --no-edit >/dev/null
_tgt_target_save acme api
set -e TGT TGT_HOSTS

# Right now we're on acme (the new). dante's hosts should be revoked.
@test "after scenario new acme: dante hosts revoked" \
    (_hosts_count_for dante $TGT_HOSTS_FILE) -eq 0
@test "after scenario new acme: acme has no hosts yet (no targets at new time)" \
    (_hosts_count_for acme $TGT_HOSTS_FILE) -eq 0

# Now switch to dante — dante's saved hosts should be re-added
_tgt_scenario_cli switch dante >/dev/null
@test "switch to dante: web01 entry in /etc/hosts" \
    (string match -rq 'web01.dante.local' -- (cat $TGT_HOSTS_FILE); echo $status) -eq 0
@test "switch to dante: dc01 entry in /etc/hosts" \
    (string match -rq 'dc01.dante.local' -- (cat $TGT_HOSTS_FILE); echo $status) -eq 0
@test "switch to dante: acme's api hostname is GONE" \
    (string match -rq 'api.acme.local' -- (cat $TGT_HOSTS_FILE); echo $status) -ne 0

# Switch to acme — its lone host returns, dante's are revoked
_tgt_scenario_cli switch acme >/dev/null
@test "switch back to acme: api.acme.local present" \
    (string match -rq 'api.acme.local' -- (cat $TGT_HOSTS_FILE); echo $status) -eq 0
@test "switch back to acme: web01.dante.local revoked" \
    (string match -rq 'web01.dante.local' -- (cat $TGT_HOSTS_FILE); echo $status) -ne 0
_test_teardown

#
# Manual /etc/hosts entries (not tagged by tgt) are preserved across
# scenario swaps.
#
_test_setup_home
_test_setup_hosts empty.txt
echo "127.0.0.1 my-laptop.local" >> $TGT_HOSTS_FILE

_tgt_scenario_cli new dante >/dev/null
set -gx TGT 10.10.10.5; set -gx TGT_HOSTS web01.dante.local
_tgt_target_cli new web01 --no-edit >/dev/null
_tgt_target_save dante web01
set -e TGT TGT_HOSTS

_tgt_scenario_cli new acme >/dev/null   # apply fires
@test "manual /etc/hosts line preserved across scenario apply" \
    (string match -rq 'my-laptop.local' -- (cat $TGT_HOSTS_FILE); echo $status) -eq 0
_test_teardown

#
# Stale entries from a previous (now-archived / unrelated) scenario
# get scrubbed when a different scenario is activated. This is the
# bug-fix test: previously, an existing tagged line for any
# scenario survived an unrelated activation.
#
_test_setup_home
_test_setup_hosts empty.txt
# Pre-existing stale line (e.g. from a previous shell session that
# was never cleaned up):
echo "10.0.0.99 stale.htb-old:legacy # tgt:htb-old:legacy" >> $TGT_HOSTS_FILE

_tgt_scenario_cli new dante >/dev/null
set -gx TGT 10.10.10.5; set -gx TGT_HOSTS web01.dante.local
_tgt_target_cli new web01 --no-edit >/dev/null
_tgt_target_save dante web01
set -e TGT TGT_HOSTS

_tgt_scenario_cli switch dante >/dev/null
@test "stale entry from unrelated scenario gets scrubbed" \
    (string match -rq 'tgt:htb-old:legacy' -- (cat $TGT_HOSTS_FILE); echo $status) -ne 0
@test "active scenario's entry is present (not duplicated)" \
    (_hosts_count_for dante $TGT_HOSTS_FILE) -eq 1
_test_teardown

#
# Re-applying the same scenario doesn't duplicate entries.
#
_test_setup_home
_test_setup_hosts empty.txt

_tgt_scenario_cli new dante >/dev/null
set -gx TGT 10.10.10.5; set -gx TGT_HOSTS web01.dante.local
_tgt_target_cli new web01 --no-edit >/dev/null
_tgt_target_save dante web01
set -e TGT TGT_HOSTS

_tgt_hosts_apply_scenario dante
_tgt_hosts_apply_scenario dante
_tgt_hosts_apply_scenario dante
@test "apply called repeatedly: still exactly one dante entry" \
    (_hosts_count_for dante $TGT_HOSTS_FILE) -eq 1
_test_teardown

#
# No tgt-tagged lines + empty scenario name → no write.
#
_test_setup_home
_test_setup_hosts empty.txt
set -l before (md5sum $TGT_HOSTS_FILE | string split " ")[1]
_tgt_hosts_apply_scenario ""
set -l after (md5sum $TGT_HOSTS_FILE | string split " ")[1]
@test "apply with empty scenario + no tgt lines: file untouched" \
    "$before" = "$after"
_test_teardown
