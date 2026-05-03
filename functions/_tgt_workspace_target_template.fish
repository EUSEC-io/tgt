# Per-target folder/file template. Each entry is created relative to
# the target dir (nested layout) or scenario dir (flat layout).
# Trailing '/' marks a directory; everything else is touch-created.
#
# Override via $TGT_WORKSPACE_TARGET_TEMPLATE (fish list).
function _tgt_workspace_target_template
    if set -q TGT_WORKSPACE_TARGET_TEMPLATE
        printf '%s\n' $TGT_WORKSPACE_TARGET_TEMPLATE
    else
        printf '%s\n' scans/ loot/ exploits/ screenshots/ notes.md
    end
end
