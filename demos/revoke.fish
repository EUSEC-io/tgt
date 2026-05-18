#!/usr/bin/env fish
# Demo: tgt --revoke clears the active target's runtime state but
# keeps the scenario active. Useful between boxes inside the same lab.
source (status dirname)/_baseline.fish

_tgt_scenario_cli new dante >/dev/null
# Credentials and DC info are scenario-level now — set them via
# the proper CLI verbs rather than direct $TGT_* assignment.
tgt cred new admin --username admin --password secret >/dev/null
tgt dc new dc01 --domain dante.local \
    --kdc-host dc01.dante.local --kdc-ip 10.10.10.10 >/dev/null
set -gx TGT 10.10.10.10
set -gx TGT_HOSTS dc01.dante.local
_tgt_target_cli new dc01 --no-edit >/dev/null
_tgt_hosts_add dante dc01 10.10.10.10 dc01.dante.local

_p "tgt --show"
tgt --show
sleep 6

_p "tgt --revoke"
tgt --revoke
sleep 4

_p "tgt --show    # state cleared; scenario still active"
tgt --show
sleep 1

_demo_cleanup
