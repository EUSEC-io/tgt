# Dispatch for `tgt cd`, `tgt path`, `tgt workspace`. Called from tgt.fish.
function _tgt_workspace_cli
    set -l verb $argv[1]
    set -l rest $argv[2..]

    switch $verb
        case cd
            set -l dir (_tgt_workspace_resolve $rest)
            or return $status
            cd -- $dir
            return $status

        case path
            set -l dir (_tgt_workspace_resolve $rest)
            or return $status
            echo $dir
            return 0

        case workspace
            _tgt_workspace_show
            return 0

        case '*'
            echo "tgt: unknown workspace verb '$verb'" >&2
            return 1
    end
end

# Resolve the path the user is asking for. On success, prints the path
# to stdout and returns 0. On error, prints to stderr and returns 1.
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
        echo "    (no active scenario — \`tgt scenario new <name>\` to start)"
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
