# cd to your HTB machines directory.
# Override the default with: set -Ux HTB_MACHINES_DIR /your/path
function machines --description 'cd to HTB machines directory'
    set -l dir
    if set -q HTB_MACHINES_DIR
        set dir $HTB_MACHINES_DIR
    else
        set dir $HOME/HTB/machines
    end
    cd $dir $argv
end
