# Render a host/ip pair for `tgt dc show`. When both are known, show
# the mapping with an arrow ("dc01.dante.local  →  10.10.10.5"); fall
# back to whichever is set, or "(not set)" if neither.
function _tgt_dc_cli_emit_pair --argument-names host ip
    if test -n "$host"; and test -n "$ip"
        echo "$host  →  $ip"
    else if test -n "$host"
        echo "$host"
    else if test -n "$ip"
        echo "$ip"
    else
        set_color brblack; echo "(not set)"; set_color normal
    end
end
