# Load a target's saved env vars by sourcing its registry file.
function _tgt_target_load --argument-names scenario target
    _tgt_target_exists $scenario $target; or return 1
    source (_tgt_target_file $scenario $target)
end
