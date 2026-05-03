# Set a tgt env var. Universal-exported in production, global when
# either $TGT_TEST_MODE or $TGT_NO_UNIVERSALS is set (the latter is
# useful for vhs demos where gum should still fire but we don't want
# universal pollution).
function _tgt_export
    if set -q TGT_TEST_MODE; or set -q TGT_NO_UNIVERSALS
        set -gx $argv
    else
        set -Ux $argv
    end
end
