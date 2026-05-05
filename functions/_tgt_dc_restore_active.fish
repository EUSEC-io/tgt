# Restore the active DC for a scenario into the current shell:
# read the .active-dc marker, source the dc file (sets all the
# TGT_DC_* env vars), and update /etc/krb5.conf's default_realm.
#
# No-op when the scenario has no marker (or the marker points at a
# missing entry — in which case the stale marker is also cleared).
function _tgt_dc_restore_active --argument-names scenario
    set -l alias (_tgt_dc_get_active $scenario 2>/dev/null)
    test -z "$alias"; and return 0

    if not _tgt_dc_exists $scenario $alias
        # Marker points at a deleted entry — drop it.
        _tgt_dc_clear_active $scenario
        return 0
    end

    _tgt_dc_load $scenario $alias
    set -q TGT_DC_REALM; and _tgt_krb5_set_default_realm $TGT_DC_REALM
end
