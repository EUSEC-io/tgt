# Emit a target's port records, one per line, tab-separated:
#   <port>\t<proto>\t<service>\t<comment>
# Empty (or no file) → no output, exit 0. Records are kept sorted by
# port, then by proto, by `_tgt_ports_add`.
function _tgt_ports_list --argument-names scenario target
    set -l file (_tgt_ports_file $scenario $target)
    test -f $file; or return 0
    command cat -- $file
end
