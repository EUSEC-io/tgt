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
