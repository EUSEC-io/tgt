# Set a tgt env var. Universal-exported in production, global in test mode.
function _tgt_export
    if set -q TGT_TEST_MODE
        set -gx $argv
    else
        set -Ux $argv
    end
end
