# Mark a DC alias as active for its scenario by writing the .active-dc
# file. Per-scenario active state survives `tgt scenario switch` cycles.
function _tgt_dc_set_active --argument-names scenario alias
    set -l file (_tgt_dc_active_file $scenario)
    command mkdir -p (dirname $file)
    echo $alias > $file
end
