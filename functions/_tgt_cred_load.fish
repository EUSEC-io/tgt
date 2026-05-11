# Source a credential entry into the current shell, then derive
# the three computed fields:
#
#   TGT_USERNAME = TGT_CRED_USERNAME    ; what pentest tools read
#   TGT_PASSWORD = TGT_CRED_PASSWORD    ; same
#   TGT_CRED_NAME = the alias           ; for prompt + scripts
#
# Errors if the file is missing.
function _tgt_cred_load --argument-names scenario alias
    set -l file (_tgt_cred_file $scenario $alias)
    test -f $file; or return 1
    source $file
    set -q TGT_CRED_USERNAME; and _tgt_export TGT_USERNAME $TGT_CRED_USERNAME
    set -q TGT_CRED_PASSWORD; and _tgt_export TGT_PASSWORD $TGT_CRED_PASSWORD
    _tgt_export TGT_CRED_NAME $alias
end
