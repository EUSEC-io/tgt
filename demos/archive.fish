#!/usr/bin/env fish
# Demo: archive hides scenarios from the default list; --all surfaces
# them with an [archived] tag; unarchive brings them back.
source (status dirname)/_baseline.fish

_tgt_scenario_cli new dante >/dev/null
_tgt_scenario_cli new acme >/dev/null
_tgt_scenario_cli new htb-Lame >/dev/null
_tgt_scenario_cli new htb-Forest >/dev/null
_tgt_scenario_cli archive htb-Lame >/dev/null
_tgt_scenario_cli archive htb-Forest >/dev/null
set -gx TGT_SCENARIO dante

_p "tgt scenario list"
tgt scenario list
sleep 4

_p "tgt scenario list --all"
tgt scenario list --all
sleep 4.5

_p "tgt scenario unarchive htb-Lame"
tgt scenario unarchive htb-Lame
sleep 2.5

_p "tgt scenario list"
tgt scenario list
sleep 1

_demo_cleanup
