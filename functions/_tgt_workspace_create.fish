# Idempotently create the workspace folder tree for a scenario, and
# (in nested layout) optionally for a target inside it.
#
#   flat   layout, no target:  <root>/<scenario>/{scans,loot,exploits,screenshots}
#                              <root>/<scenario>/notes.md
#   flat   layout, with target: same as above (target arg ignored)
#   nested layout, no target:  <root>/<scenario>/_report/{findings,screenshots}
#                              <root>/<scenario>/_engagement.md
#   nested layout, with target: scenario-level setup above, plus
#                              <root>/<scenario>/<target>/{scans,loot,exploits,screenshots}
#                              <root>/<scenario>/<target>/notes.md
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
            mkdir -p -- "$scenario_dir/_report/findings" "$scenario_dir/_report/screenshots"
            or return 1
            touch -- "$scenario_dir/_engagement.md"
            if test -n "$target"
                set -l target_dir "$scenario_dir/$target"
                mkdir -p -- "$target_dir/scans" "$target_dir/loot" "$target_dir/exploits" "$target_dir/screenshots"
                or return 1
                touch -- "$target_dir/notes.md"
            end
        case flat '*'
            mkdir -p -- "$scenario_dir/scans" "$scenario_dir/loot" "$scenario_dir/exploits" "$scenario_dir/screenshots"
            or return 1
            touch -- "$scenario_dir/notes.md"
    end
    return 0
end
