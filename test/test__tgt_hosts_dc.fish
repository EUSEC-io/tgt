source (status dirname)/helpers.fish

#
# DC with both kdc-host AND kdc-ip → one /etc/hosts line written
# under the new tgt:dc:<scen>:<alias> tag.
#
_test_setup_home
_test_setup_hosts empty.txt
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 \
    --domain dante.local \
    --kdc-host dc01.dante.local --kdc-ip 10.10.10.5 \
    >/dev/null
set -l content (cat $TGT_HOSTS_FILE | string collect)
@test "dc apply: kdc line present" \
    (string match -q '*10.10.10.5*dc01.dante.local*tgt:dc:dante:dc01*' -- $content; echo $status) -eq 0
_test_teardown

#
# DC with only kdc-ip (no host) → no hosts line (we have no hostname
# to map). The realm block in krb5 has kdc = IP directly.
#
_test_setup_home
_test_setup_hosts empty.txt
_tgt_scenario_cli new dante >/dev/null
tgt dc new ip-only --domain dante.local --kdc-ip 10.10.10.5 >/dev/null
set -l content (cat $TGT_HOSTS_FILE | string collect)
@test "dc apply (ip-only): no hosts line written" \
    (string match -q '*tgt:dc:dante:ip-only*' -- $content; echo $status) -ne 0
_test_teardown

#
# DC with only kdc-host (no IP) → no hosts line either (we have no
# IP to map to). User would need to add the entry themselves.
#
_test_setup_home
_test_setup_hosts empty.txt
_tgt_scenario_cli new dante >/dev/null
tgt dc new host-only --domain dante.local --kdc-host dc01.dante.local >/dev/null
set -l content (cat $TGT_HOSTS_FILE | string collect)
@test "dc apply (host-only): no hosts line written" \
    (string match -q '*tgt:dc:dante:host-only*' -- $content; echo $status) -ne 0
_test_teardown

#
# admin_server with host+ip differing from kdc → SECOND hosts line.
#
_test_setup_home
_test_setup_hosts empty.txt
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 \
    --domain dante.local \
    --kdc-host dc01.dante.local --kdc-ip 10.10.10.5 \
    --admin-host admin.dante.local --admin-ip 10.10.10.6 \
    >/dev/null
set -l content (cat $TGT_HOSTS_FILE | string collect)
@test "dc apply: kdc line present" \
    (string match -q '*10.10.10.5*dc01.dante.local*' -- $content; echo $status) -eq 0
@test "dc apply: distinct admin_server line present" \
    (string match -q '*10.10.10.6*admin.dante.local*' -- $content; echo $status) -eq 0
@test "dc apply: both lines tagged for the same dc" \
    (string match -ar 'tgt:dc:dante:dc01' -- $content | count) -eq 2
_test_teardown

#
# admin_server identical to kdc → no duplicate line.
#
_test_setup_home
_test_setup_hosts empty.txt
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 \
    --domain dante.local \
    --kdc-host dc01.dante.local --kdc-ip 10.10.10.5 \
    --admin-host dc01.dante.local --admin-ip 10.10.10.5 \
    >/dev/null
set -l content (cat $TGT_HOSTS_FILE | string collect)
@test "dc apply: only one hosts line (admin == kdc)" \
    (string match -ar 'tgt:dc:dante:dc01' -- $content | count) -eq 1
_test_teardown

#
# Removing a DC strips its hosts lines; siblings preserved.
#
_test_setup_home
_test_setup_hosts empty.txt
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 --domain dante.local --kdc-host dc01.dante.local --kdc-ip 10.10.10.5 >/dev/null
tgt dc new dc02 --domain dante.local --kdc-host dc02.dante.local --kdc-ip 10.10.10.6 >/dev/null
tgt dc rm dc01 >/dev/null
set -l content (cat $TGT_HOSTS_FILE | string collect)
@test "dc rm: dc01 hosts line gone" \
    (string match -q '*tgt:dc:dante:dc01*' -- $content; echo $status) -ne 0
@test "dc rm: dc02 hosts line preserved" \
    (string match -q '*10.10.10.6*dc02.dante.local*tgt:dc:dante:dc02*' -- $content; echo $status) -eq 0
_test_teardown

#
# Manual /etc/hosts entries are preserved across DC apply.
#
_test_setup_home
set -gx TGT_TEST_MODE 1
set -gx TGT_HOSTS_FILE (mktemp)
echo "127.0.0.1 localhost
192.168.1.1 my-router" > $TGT_HOSTS_FILE
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 --domain dante.local --kdc-host dc01.dante.local --kdc-ip 10.10.10.5 >/dev/null
set -l content (cat $TGT_HOSTS_FILE | string collect)
@test "dc apply: localhost line preserved" \
    (string match -q '*127.0.0.1*localhost*' -- $content; echo $status) -eq 0
@test "dc apply: my-router line preserved" \
    (string match -q '*192.168.1.1*my-router*' -- $content; echo $status) -eq 0
@test "dc apply: dc01 line added" \
    (string match -q '*10.10.10.5*dc01.dante.local*' -- $content; echo $status) -eq 0
_test_teardown

#
# Hot-swap on scenario switch: dc lines from the previous scenario
# vanish, the new scenario's lines appear.
#
_test_setup_home
_test_setup_hosts empty.txt
_tgt_scenario_cli new dante >/dev/null
tgt dc new ddc --domain dante.local --kdc-host ddc.dante.local --kdc-ip 10.10.10.5 >/dev/null

_tgt_scenario_cli new acme >/dev/null
set -l content (cat $TGT_HOSTS_FILE | string collect)
@test "scenario switch (new acme): dante's dc line stripped" \
    (string match -q '*tgt:dc:dante:ddc*' -- $content; echo $status) -ne 0

tgt dc new adc --domain acme.local --kdc-host adc.acme.local --kdc-ip 10.20.20.5 >/dev/null
_tgt_scenario_cli switch dante >/dev/null
set -l content (cat $TGT_HOSTS_FILE | string collect)
@test "switch back to dante: dante's dc line restored" \
    (string match -q '*10.10.10.5*ddc.dante.local*tgt:dc:dante:ddc*' -- $content; echo $status) -eq 0
@test "switch back to dante: acme's dc line stripped" \
    (string match -q '*tgt:dc:acme:adc*' -- $content; echo $status) -ne 0
_test_teardown

#
# Hostnames are lowercased on the way into /etc/hosts even when the
# user types them mixed-case (DNS doesn't care; this prevents
# duplicate-by-case rows). krb5.conf keeps the original case.
#
_test_setup_home
_test_setup_hosts empty.txt
_tgt_scenario_cli new dante >/dev/null
tgt dc new dc01 \
    --domain dante.local \
    --kdc-host DC01.Dante.LOCAL --kdc-ip 10.10.10.5 \
    >/dev/null

set -l hosts_content (cat $TGT_HOSTS_FILE | string collect)
set -l krb5_content  (cat $TGT_KRB5_FILE  | string collect)

@test "lowercase hosts: /etc/hosts has lowercase hostname" \
    (string match -q '*10.10.10.5 dc01.dante.local*' -- $hosts_content; echo $status) -eq 0
@test "lowercase hosts: /etc/hosts does NOT have mixed case" \
    (string match -q '*DC01.Dante.LOCAL*' -- $hosts_content; echo $status) -ne 0
@test "lowercase hosts: krb5 keeps original case for kdc" \
    (string match -q '*kdc = DC01.Dante.LOCAL*' -- $krb5_content; echo $status) -eq 0
_test_teardown

#
# Same lowercasing rule for target hostnames added via tgt --add-host.
#
_test_setup_home
_test_setup_hosts empty.txt
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 10.10.10.10
tgt new web01 --no-edit >/dev/null
tgt --add-host Web01.DANTE.LOCAL >/dev/null
@test "lowercase hosts: target hostname lowercased in /etc/hosts" \
    (cat $TGT_HOSTS_FILE | string match -q '*10.10.10.10 web01.dante.local*'; echo $status) -eq 0
_test_teardown

#
# Mixed scenario: target hosts AND dc hosts coexist under their own
# tags.
#
_test_setup_home
_test_setup_hosts empty.txt
_tgt_scenario_cli new dante >/dev/null
set -gx TGT 10.10.10.10
tgt new web01 --no-edit >/dev/null
tgt --add-host web01.dante.local >/dev/null
tgt dc new dc01 --domain dante.local --kdc-host dc01.dante.local --kdc-ip 10.10.10.5 >/dev/null
set -l content (cat $TGT_HOSTS_FILE | string collect)
@test "mixed: target line tagged tgt:scen:target" \
    (string match -q '*10.10.10.10 web01.dante.local # tgt:dante:web01*' -- $content; echo $status) -eq 0
@test "mixed: dc line tagged tgt:dc:scen:alias" \
    (string match -q '*10.10.10.5 dc01.dante.local # tgt:dc:dante:dc01*' -- $content; echo $status) -eq 0
_test_teardown
