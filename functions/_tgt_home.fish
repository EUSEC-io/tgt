# Path to the tgt registry root. Override via $TGT_HOME for tests.
function _tgt_home
    if set -q TGT_HOME
        echo $TGT_HOME
    else
        echo $HOME/.config/fish/tgt
    end
end
