# Resolve the workspace path for `tgt cd` / `tgt path`.
# On success, prints the absolute path to stdout and returns 0.
# On error, prints to stderr and returns 1.
function _tgt_workspace_resolve
    argparse --name='tgt cd/path' 's/scenario' -- $argv
    or return 1

    set -l target_arg ""
    test (count $argv) -ge 1; and set target_arg $argv[1]

    if not set -q TGT_SCENARIO
        echo "tgt: no active scenario — run \`tgt scenario new <name>\` or \`tgt scenario switch <name>\` first" >&2
        return 1
    end
    set -l scenario $TGT_SCENARIO

    set -l target ""
    if not set -q _flag_scenario
        if test -n "$target_arg"
            set target $target_arg
        else if set -q TGT_ACTIVE
            set target $TGT_ACTIVE
        end
    end

    set -l dir (_tgt_workspace_dir $scenario $target)
    if not test -d $dir
        echo "tgt: $dir does not exist" >&2
        echo "  enable auto-create with \`set -Ux TGT_WORKSPACE_AUTOCREATE 1\` and recreate the scenario/target," >&2
        echo "  or run \`mkdir -p $dir\` to create it manually." >&2
        return 1
    end
    echo $dir
    return 0
end
