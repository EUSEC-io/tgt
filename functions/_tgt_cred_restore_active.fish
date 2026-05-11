# Restore the active credential for a scenario into the current
# shell: read the .active-cred marker, source the cred file (sets
# TGT_CRED_* and the derived TGT_USERNAME / TGT_PASSWORD).
#
# No-op when the scenario has no marker (or the marker points at
# a missing entry — in which case the stale marker is also cleared).
function _tgt_cred_restore_active --argument-names scenario
    set -l alias (_tgt_cred_get_active $scenario 2>/dev/null)
    test -z "$alias"; and return 0

    if not _tgt_cred_exists $scenario $alias
        _tgt_cred_clear_active $scenario
        return 0
    end

    _tgt_cred_load $scenario $alias
end
