#!/usr/bin/env fish
# Demo: opt-in workspace folders. With autocreate on, new scenarios
# and targets get a fresh folder tree from the configured templates.
source (status dirname)/_baseline.fish

set -gx TGT_WORKSPACE_AUTOCREATE 1
set -gx TGT_WORKSPACE_LAYOUT nested

_p "tgt scenario new dante"
_tgt_scenario_cli new dante
sleep 3

_p "tgt new web01 --no-edit"
set -gx TGT 10.10.10.5
_tgt_target_cli new web01 --no-edit
set -e TGT
sleep 2.5

_p "tgt new dc01 --no-edit"
_tgt_target_cli new dc01 --no-edit
sleep 2.5

_p "tgt workspace"
tgt workspace
sleep 5.5

_p "tgt path     # active target's folder"
tgt path
sleep 3

_demo_cleanup
