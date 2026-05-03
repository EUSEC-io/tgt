#!/usr/bin/env fish
# Demo: how `tgt_prompt` color tracks damage potential.
source (status dirname)/_baseline.fish

function _state
    set_color brblack
    printf '  %-46s' $argv[1]
    set_color normal
    printf 'prompt: '
    tgt_prompt
    echo ""
    sleep 2.5
end

set_color cyan
echo "  tgt_prompt — color tracks damage potential"
set_color normal
echo ""
sleep 1.6

_state "no scope"
set -gx TGT_SCENARIO dante
_state "scenario active                    [dante]"
set -gx TGT_ACTIVE web01
_state "+ target loaded                    [dante:web01]"
set -gx TGT 10.10.10.5
_state "+ host loaded — yellow (recon)"
set -gx TGT_PASSWORD secret
_state "+ creds loaded — red (damage)"

sleep 1

_demo_cleanup
