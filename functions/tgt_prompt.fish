# Render a [scenario:target] indicator for use in fish_prompt or
# fish_right_prompt. Empty output when no scenario is active.
#
# Color reflects damage potential:
#   red     credentials loaded ($TGT_PASSWORD set)
#   yellow  host/port set, no creds
#   default scenario only (no target loaded yet)
#
# Add to your prompt with e.g.:
#   function fish_right_prompt
#       tgt_prompt
#   end
function tgt_prompt --description 'Render a [scenario:target] indicator'
    set -q TGT_SCENARIO; or return

    set -l label $TGT_SCENARIO
    set -q TGT_ACTIVE; and set label "$label:$TGT_ACTIVE"

    if set -q TGT_PASSWORD
        set_color red
    else if set -q TGT
        set_color yellow
    else
        set_color normal
    end
    echo -n "[$label]"
    set_color normal
end
