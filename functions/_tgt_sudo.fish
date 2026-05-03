# Run a command with sudo (production) or directly when
# $TGT_TEST_MODE / $TGT_NO_SUDO is set (the latter is useful for vhs
# demos where the system files have been redirected to tmp paths).
function _tgt_sudo
    if set -q TGT_TEST_MODE; or set -q TGT_NO_SUDO
        $argv
    else
        _tgt_sudo_notice
        command sudo $argv
    end
end
