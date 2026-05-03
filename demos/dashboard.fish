#!/usr/bin/env fish
# Demo: scenario list + per-scenario dashboard.
source (status dirname)/_baseline.fish

_tgt_scenario_cli new dante >/dev/null

set -gx TGT 10.10.10.5
_tgt_target_cli new web01 --no-edit >/dev/null
_tgt_target_save dante web01
set -e TGT

set -gx TGT 10.10.10.10
set -gx TGT_PORT 445
set -gx TGT_USERNAME admin
set -gx TGT_PASSWORD secret
set -gx TGT_AD_DOMAIN dante.local
set -gx TGT_HOSTS dc01.dante.local dc01
_tgt_target_cli new dc01 --no-edit >/dev/null
_tgt_target_save dante dc01
set -e TGT TGT_PORT TGT_USERNAME TGT_PASSWORD TGT_AD_DOMAIN TGT_HOSTS

set -gx TGT 10.10.10.20
set -gx TGT_USERNAME svc
set -gx TGT_HOSTS fileserver.dante.local
_tgt_target_cli new fileserver --no-edit >/dev/null
_tgt_target_save dante fileserver
set -e TGT TGT_USERNAME TGT_HOSTS

_tgt_scenario_cli new acme >/dev/null

set -gx TGT_SCENARIO dante
set -gx TGT_ACTIVE web01

_p "tgt scenario list"
tgt scenario list
sleep 4.5

_p "tgt scenario show"
tgt scenario show
sleep 6

_demo_cleanup
