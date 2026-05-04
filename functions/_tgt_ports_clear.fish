# Wipe all port records for the target. No-op if file absent.
function _tgt_ports_clear --argument-names scenario target
    set -l file (_tgt_ports_file $scenario $target)
    test -f $file; and command rm -f -- $file
    return 0
end
