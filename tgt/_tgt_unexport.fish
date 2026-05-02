# Erase a tgt env var. Universal scope in production, any scope in test mode.
function _tgt_unexport
    if set -q TGT_TEST_MODE
        set -e $argv
    else
        set -Ue $argv
    end
end
