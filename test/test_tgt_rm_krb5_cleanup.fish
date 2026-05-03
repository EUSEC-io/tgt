source (status dirname)/helpers.fish

#
# `tgt rm <alias>` cleans the realm from krb5.conf when no other
# target uses that AD domain.
#
_test_setup_home
_test_setup_hosts empty.txt
_test_setup_krb5 one_realm.conf
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 10.10.10.10
set -gx TGT_AD_DOMAIN htb.local
set -gx TGT_DC DC01.HTB.LOCAL
_tgt_target_cli new dc01 --no-edit >/dev/null
_tgt_target_save dante dc01
set -e TGT TGT_AD_DOMAIN TGT_DC

_tgt_target_cli rm dc01 >/dev/null

@test "rm target (sole user): HTB.LOCAL realm block removed" \
    (string match -rq 'kdc = DC01.HTB.LOCAL' -- (cat $TGT_KRB5_FILE); echo $status) -ne 0
_test_teardown

#
# `tgt rm <alias>` does NOT clean the realm if another target in the
# same scenario still uses that AD domain.
#
_test_setup_home
_test_setup_hosts empty.txt
_test_setup_krb5 one_realm.conf
_tgt_scenario_cli new dante >/dev/null

set -gx TGT 10.10.10.10
set -gx TGT_AD_DOMAIN htb.local
_tgt_target_cli new dc01 --no-edit >/dev/null
_tgt_target_save dante dc01

set -gx TGT 10.10.10.20
set -gx TGT_AD_DOMAIN htb.local
_tgt_target_cli new dc02 --no-edit >/dev/null
_tgt_target_save dante dc02

set -e TGT TGT_AD_DOMAIN

_tgt_target_cli rm dc01 >/dev/null

@test "rm target (other still uses realm): kdc line preserved" \
    (string match -rq 'kdc = DC01.HTB.LOCAL' -- (cat $TGT_KRB5_FILE); echo $status) -eq 0
_test_teardown

#
# `tgt scenario rm` cleans all realms used by the scenario's targets,
# unless another scenario still uses them.
#
_test_setup_home
_test_setup_hosts empty.txt
_test_setup_krb5 one_realm.conf
_tgt_scenario_cli new dante >/dev/null

set -gx TGT 10.10.10.10
set -gx TGT_AD_DOMAIN htb.local
_tgt_target_cli new dc01 --no-edit >/dev/null
_tgt_target_save dante dc01
set -e TGT TGT_AD_DOMAIN

_tgt_scenario_cli rm dante >/dev/null

@test "scenario rm: realm block cleaned (no other scenario uses it)" \
    (string match -rq 'kdc = DC01.HTB.LOCAL' -- (cat $TGT_KRB5_FILE); echo $status) -ne 0
_test_teardown

#
# `tgt scenario rm` keeps the realm if another scenario still uses it.
#
_test_setup_home
_test_setup_hosts empty.txt
_test_setup_krb5 one_realm.conf

_tgt_scenario_cli new dante >/dev/null
set -gx TGT 10.10.10.10
set -gx TGT_AD_DOMAIN htb.local
_tgt_target_cli new dc01 --no-edit >/dev/null
_tgt_target_save dante dc01

_tgt_scenario_cli new acme >/dev/null
set -gx TGT 10.10.20.10
set -gx TGT_AD_DOMAIN htb.local
_tgt_target_cli new winsrv --no-edit >/dev/null
_tgt_target_save acme winsrv

set -e TGT TGT_AD_DOMAIN

_tgt_scenario_cli rm dante >/dev/null

@test "scenario rm (cross-scenario realm): realm block preserved" \
    (string match -rq 'kdc = DC01.HTB.LOCAL' -- (cat $TGT_KRB5_FILE); echo $status) -eq 0
_test_teardown

#
# Helper-level: _tgt_target_ad_realm reads the realm from disk.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 1.1.1.1
set -gx TGT_AD_DOMAIN dante.local
_tgt_target_save dante dc01
set -e TGT TGT_AD_DOMAIN

@test "ad_realm: returns uppercase realm" \
    (_tgt_target_ad_realm dante dc01) = "DANTE.LOCAL"
_test_teardown

#
# Helper-level: _tgt_realm_in_use scans all scenarios.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 1.1.1.1
set -gx TGT_AD_DOMAIN htb.local
_tgt_target_save dante dc01
set -e TGT TGT_AD_DOMAIN

@test "realm_in_use: HTB.LOCAL → in use" \
    (_tgt_realm_in_use HTB.LOCAL; echo $status) -eq 0
@test "realm_in_use: GHOST.LOCAL → not in use" \
    (_tgt_realm_in_use GHOST.LOCAL; echo $status) -ne 0
_test_teardown
