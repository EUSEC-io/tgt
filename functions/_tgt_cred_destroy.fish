# Remove a credential entry file. Idempotent.
function _tgt_cred_destroy --argument-names scenario alias
    set -l file (_tgt_cred_file $scenario $alias)
    test -f $file; or return 0
    command rm -f -- $file
end
