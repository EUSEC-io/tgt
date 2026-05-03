# Workspace folder layout: 'flat' (everything at scenario level —
# good for HTB single boxes) or 'nested' (per-target subfolders +
# scenario-level _report/ — better for Pro Labs / client engagements).
# Override via $TGT_WORKSPACE_LAYOUT. Unknown values fall back to flat.
function _tgt_workspace_layout
    if set -q TGT_WORKSPACE_LAYOUT
        switch $TGT_WORKSPACE_LAYOUT
            case flat nested
                echo $TGT_WORKSPACE_LAYOUT
                return 0
        end
    end
    echo flat
end
