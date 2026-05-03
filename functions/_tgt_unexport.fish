# Erase a tgt env var. Universal scope in production, any scope when
# $TGT_TEST_MODE / $TGT_NO_UNIVERSALS is set.
function _tgt_unexport
    if set -q TGT_TEST_MODE; or set -q TGT_NO_UNIVERSALS
        set -e $argv
    else
        set -Ue $argv
    end
end
