# Print the current workspace settings + a tree visualization of
# the active scenario's folder. Used by `tgt workspace` and
# `tgt config show`.
function _tgt_workspace_show
    set -l root (_tgt_workspace_root)
    set -l layout (_tgt_workspace_layout)
    set -l auto disabled
    _tgt_workspace_autocreate; and set auto enabled

    echo ""
    echo "  tgt workspace"
    echo "  ─────────────────────────────────────────────"
    echo "    root         $root"
    echo "    layout       $layout      (\$TGT_WORKSPACE_LAYOUT: flat | nested)"
    echo "    autocreate   $auto    (\$TGT_WORKSPACE_AUTOCREATE: 1/true/yes/on to enable)"
    echo ""

    if not set -q TGT_SCENARIO
        echo "    (no active scenario — `tgt scenario new <name>` to start)"
        echo ""
        return 0
    end

    set -l scenario $TGT_SCENARIO
    set -l scenario_dir (_tgt_workspace_dir $scenario)
    echo "    scenario     $scenario  →  $scenario_dir"

    if set -q TGT_ACTIVE
        set -l target_dir (_tgt_workspace_dir $scenario $TGT_ACTIVE)
        echo "    target       $TGT_ACTIVE  →  $target_dir"
    end
    echo ""

    if not test -d $scenario_dir
        echo "    (folder does not exist on disk yet)"
        echo ""
        return 0
    end

    echo "    layout on disk:"
    if command -q tree
        command tree -L 2 --noreport -- $scenario_dir | string replace -r '^' '      '
    else
        for entry in $scenario_dir/*
            set -l name (string replace -r '.*/' '' -- $entry)
            test -d $entry; and echo "      $name/"
            test -f $entry; and echo "      $name"
        end
    end
    echo ""
end
