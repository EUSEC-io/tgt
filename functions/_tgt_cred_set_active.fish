# Mark a credential alias as active for its scenario by writing
# the .active-cred file.
function _tgt_cred_set_active --argument-names scenario alias
    set -l file (_tgt_cred_active_file $scenario)
    command mkdir -p (dirname $file)
    echo $alias > $file
end
