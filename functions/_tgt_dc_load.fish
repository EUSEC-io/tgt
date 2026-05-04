# Source a DC entry's storage file into the current shell, then
# derive the two computed fields:
#
#   TGT_DC      = TGT_DC_HOST if set, else TGT_DC_IP
#                 (whatever ends up on the krb5.conf `kdc =` line)
#   TGT_DC_NAME = the alias (taken from the file path, not stored)
#
# Errors if the file is missing.
function _tgt_dc_load --argument-names scenario alias
    set -l file (_tgt_dc_file $scenario $alias)
    test -f $file; or return 1
    source $file
    if set -q TGT_DC_HOST
        _tgt_export TGT_DC $TGT_DC_HOST
    else if set -q TGT_DC_IP
        _tgt_export TGT_DC $TGT_DC_IP
    end
    _tgt_export TGT_DC_NAME $alias
end
