# Render a [scenario:target[:port][@dc]] indicator for use in
# fish_prompt or fish_right_prompt. Empty output when no scenario
# is active.
#
# Color reflects damage potential:
#   red     credentials loaded ($TGT_PASSWORD set)
#   yellow  host, port, or active DC set — no creds yet
#   default scenario only (no target loaded yet)
#
# Add to your prompt with e.g.:
#   function fish_right_prompt
#       tgt_prompt
#   end
function tgt_prompt --description 'Render a [scenario:target[:port][@dc]] indicator'
    set -q TGT_SCENARIO; or return

    set -l label $TGT_SCENARIO
    set -q TGT_ACTIVE; and set label "$label:$TGT_ACTIVE"
    set -q TGT_PORT; and set label "$label:$TGT_PORT"
    set -q TGT_DC_NAME; and set label "$label@$TGT_DC_NAME"

    if set -q TGT_PASSWORD
        set_color red
    else if set -q TGT; or set -q TGT_PORT; or set -q TGT_DC_NAME
        set_color yellow
    else
        set_color normal
    end
    echo -n "[$label]"
    set_color normal
end
