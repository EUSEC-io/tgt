# Render a single port record for display in `tgt ports list` and the
# picker. Records in the interesting set get a bright marker + bold
# cyan port/proto so they jump out when scanning a long list.
#
# Output layout (single line, no trailing newline — the caller adds it):
#   <marker> <port/proto>  <service>[  <comment>]
function _tgt_ports_format_record --argument-names port proto service comment
    set -l marker "  "
    set -l color ""
    set -l reset ""
    if _tgt_ports_is_interesting $port $proto
        set marker (set_color brcyan)"★ "(set_color normal)
        set color (set_color brcyan)
        set reset (set_color normal)
    end
    set -l portproto "$port/$proto"
    if test -n "$comment"
        printf '%s%s%-10s%s  %-20s  %s' \
            $marker $color $portproto $reset $service $comment
    else
        printf '%s%s%-10s%s  %s' \
            $marker $color $portproto $reset $service
    end
end
