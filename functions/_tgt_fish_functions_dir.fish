# Path to fish's user functions dir. Override via
# $TGT_FISH_FUNCTIONS_DIR for tests.
function _tgt_fish_functions_dir
    if set -q TGT_FISH_FUNCTIONS_DIR
        echo $TGT_FISH_FUNCTIONS_DIR
    else if set -q XDG_CONFIG_HOME
        echo $XDG_CONFIG_HOME/fish/functions
    else
        echo $HOME/.config/fish/functions
    end
end
