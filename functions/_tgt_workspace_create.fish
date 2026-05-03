# Idempotently create the workspace folder tree for a scenario, and
# (in nested layout) optionally for a target inside it.
#
#   flat   layout: scenario dir + per-target template applied there
#                  (target arg is ignored)
#   nested layout: scenario dir + per-scenario template applied there;
#                  if a target is given, the per-target template is
#                  applied under <scenario>/<target>
#
# Templates come from _tgt_workspace_{target,scenario}_template.
function _tgt_workspace_create --argument-names scenario target
    test -z "$scenario"; and return 1
    set -l layout (_tgt_workspace_layout)
    set -l root (_tgt_workspace_root)
    set -l scenario_dir "$root/$scenario"

    if not mkdir -p -- $scenario_dir
        echo "tgt workspace: cannot create $scenario_dir" >&2
        return 1
    end

    switch $layout
        case nested
            _tgt_workspace_apply_template $scenario_dir (_tgt_workspace_scenario_template)
            or return 1
            if test -n "$target"
                set -l target_dir "$scenario_dir/$target"
                if not mkdir -p -- $target_dir
                    echo "tgt workspace: cannot create $target_dir" >&2
                    return 1
                end
                _tgt_workspace_apply_template $target_dir (_tgt_workspace_target_template)
                or return 1
            end
        case flat '*'
            _tgt_workspace_apply_template $scenario_dir (_tgt_workspace_target_template)
            or return 1
    end
    return 0
end
