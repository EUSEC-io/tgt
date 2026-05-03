# Path to the workspace root. Per-target/scenario folders live under
# this. Override via $TGT_WORKSPACE_ROOT.
function _tgt_workspace_root
    if set -q TGT_WORKSPACE_ROOT
        echo $TGT_WORKSPACE_ROOT
    else
        echo $HOME/Documents/pentest
    end
end
