#!/usr/bin/env fish
# Demo: tgt rename retags /etc/hosts entries automatically. Manual
# entries (added without tgt) are left alone.
source (status dirname)/_baseline.fish

echo "127.0.0.1 localhost" > $TGT_HOSTS_FILE

_tgt_scenario_cli new dante >/dev/null
set -gx TGT 10.10.10.5
_tgt_target_cli new web01 --no-edit >/dev/null
_tgt_hosts_add dante web01 10.10.10.5 web01.dante.local intranet.dante.local

_p "cat /etc/hosts"
cat $TGT_HOSTS_FILE
sleep 4

_p "tgt rename web01 web02"
_tgt_target_cli rename web01 web02
sleep 3

_p "cat /etc/hosts    # tag rewritten; manual line untouched"
cat $TGT_HOSTS_FILE
sleep 1

_demo_cleanup
