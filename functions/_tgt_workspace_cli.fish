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
            set -l sub ""
            test (count $rest) -ge 1; and set sub $rest[1]
            set -l sub_args $rest[2..]
            switch "$sub"
                case ""
                    _tgt_workspace_show
                    return 0
                case create
                    _tgt_workspace_create_cmd $sub_args
                    return $status
                case -h --help
                    echo ""
                    echo "  tgt workspace — workspace folders"
                    echo ""
                    echo "    tgt workspace                Show settings + tree"
                    echo "    tgt workspace create [alias] Create folders for active scenario"
                    echo "                                   (and target, if alias / TGT_ACTIVE given)"
                    echo ""
                    return 0
                case '*'
                    echo "tgt workspace: unknown subcommand '$sub'" >&2
                    echo "Try: tgt workspace --help" >&2
                    return 1
            end

        case '*'
            echo "tgt: unknown workspace verb '$verb'" >&2
            return 1
    end
end

# Create the workspace folder tree for the active scenario, with an
# optional alias to also build the per-target subfolder.
function _tgt_workspace_create_cmd
    if not set -q TGT_SCENARIO
        echo "tgt workspace create: no active scenario — run `tgt scenario new <name>` or `tgt scenario switch <name>` first" >&2
        return 1
    end
    set -l scenario $TGT_SCENARIO

    set -l target ""
    test (count $argv) -ge 1; and set target $argv[1]
    if test -z "$target"; and set -q TGT_ACTIVE
        set target $TGT_ACTIVE
    end

    # In flat layout, target makes no difference — _tgt_workspace_create
    # ignores it. In nested, an empty target builds only the scenario
    # root + scenario template; passing the target adds the target dir.
    if not _tgt_workspace_create $scenario $target
        return 1
    end

    set -l dir (_tgt_workspace_dir $scenario $target)
    set_color green; echo "  ✓ created $dir"; set_color normal
    return 0
end
