# Resolve the workspace path for a (scenario [, target]) pair.
#
#   flat   layout: <root>/<scenario>          (target arg ignored)
#   nested layout: <root>/<scenario>          when target is empty
#                  <root>/<scenario>/<target> when target is given
#
# Does not check whether the path exists.
function _tgt_workspace_dir --argument-names scenario target
    test -z "$scenario"; and return 1
    set -l root (_tgt_workspace_root)
    set -l layout (_tgt_workspace_layout)

    if test "$layout" = nested; and test -n "$target"
        echo "$root/$scenario/$target"
    else
        echo "$root/$scenario"
    end
end
