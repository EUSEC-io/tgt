# Remove the workspace folder for a (scenario [, target]) pair.
# Refuses to act unless the resolved path is under $TGT_WORKSPACE_ROOT
# and is not the root itself. Idempotent: missing folder → no-op.
function _tgt_workspace_purge --argument-names scenario target
    test -z "$scenario"; and return 1
    set -l root (_tgt_workspace_root)
    test -z "$root"; and return 1
    set -l dir (_tgt_workspace_dir $scenario $target)

    if not string match -q "$root/*" -- $dir
        echo "tgt workspace: refusing to remove $dir (outside workspace root $root)" >&2
        return 1
    end

    test -d $dir; or return 0

    if not command rm -rf -- $dir
        echo "tgt workspace: failed to remove $dir" >&2
        return 1
    end
    echo "✓ removed workspace folder $dir"
    return 0
end
