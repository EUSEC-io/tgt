# Remove a DC entry file. Idempotent (no-op if missing).
function _tgt_dc_destroy --argument-names scenario alias
    set -l file (_tgt_dc_file $scenario $alias)
    test -f $file; or return 0
    command rm -f -- $file
end
