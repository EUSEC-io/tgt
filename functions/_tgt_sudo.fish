# Run a command with sudo (production) or directly (test mode).
function _tgt_sudo
    if set -q TGT_TEST_MODE
        $argv
    else
        command sudo $argv
    end
end
