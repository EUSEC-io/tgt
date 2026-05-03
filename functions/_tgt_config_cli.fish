# Dispatch for `tgt config <verb>`. Called from tgt.fish.
function _tgt_config_cli
    set -l verb ""
    test (count $argv) -ge 1; and set verb $argv[1]
    set -l rest $argv[2..]

    switch "$verb"
        case "" edit
            _tgt_config_edit
            return $status
        case show
            _tgt_workspace_show
            return 0
        case reset
            _tgt_config_reset
            return 0
        case -h --help
            echo ""
            echo "  tgt config — edit workspace settings"
            echo ""
            echo "    tgt config              Open the interactive editor (default)"
            echo "    tgt config show         Print current settings (alias for \`tgt workspace\`)"
            echo "    tgt config reset        Erase all custom workspace settings (revert to defaults)"
            echo ""
            echo "  Settings are persisted as fish universals (\`set -Ux\`) so they"
            echo "  survive shell restarts. Templates: each entry is one line;"
            echo "  trailing '/' marks a directory, anything else is a touched file."
            echo ""
            return 0
        case '*'
            echo "tgt config: unknown verb '$verb'" >&2
            echo "Try: tgt config --help" >&2
            return 1
    end
end

function _tgt_config_reset
    for v in TGT_WORKSPACE_ROOT TGT_WORKSPACE_LAYOUT TGT_WORKSPACE_AUTOCREATE TGT_WORKSPACE_TARGET_TEMPLATE TGT_WORKSPACE_SCENARIO_TEMPLATE
        set -q $v; and _tgt_unexport $v
    end
    echo "  ✓ workspace settings reset to defaults"
end

function _tgt_config_edit
    echo ""
    echo "  tgt config — edit workspace settings (Ctrl-C to abort, Enter to keep current)"
    echo ""

    set -l current_root (_tgt_workspace_root)
    read -P "  Workspace root [$current_root]: " new_root
    test -z "$new_root"; and set new_root $current_root

    set -l current_layout (_tgt_workspace_layout)
    set -l new_layout ""
    while true
        read -P "  Layout, flat or nested [$current_layout]: " new_layout
        test -z "$new_layout"; and set new_layout $current_layout
        if contains $new_layout flat nested
            break
        end
        echo "    invalid: expected 'flat' or 'nested'" >&2
    end

    set -l current_auto disabled
    _tgt_workspace_autocreate; and set current_auto enabled
    read -P "  Auto-create folders on \`tgt new\` (y/n) [$current_auto]: " ac_input
    set -l new_auto $current_auto
    if test -n "$ac_input"
        switch (string lower -- $ac_input)
            case y yes 1 true on enabled
                set new_auto enabled
            case n no 0 false off disabled
                set new_auto disabled
            case '*'
                echo "    unrecognized; keeping '$current_auto'" >&2
        end
    end

    set -l new_target_tpl (_tgt_config_edit_template "per-target template" (_tgt_workspace_target_template))
    if test $status -ne 0; return 1; end
    set -l new_scenario_tpl (_tgt_config_edit_template "per-scenario template (nested layout only)" (_tgt_workspace_scenario_template))
    if test $status -ne 0; return 1; end

    echo ""
    echo "  ─── Summary ────────────────────────────────────────"
    echo "    root:                  $new_root"
    echo "    layout:                $new_layout"
    echo "    autocreate:            $new_auto"
    echo "    per-target template:   "(string join ' ' -- $new_target_tpl)
    echo "    per-scenario template: "(string join ' ' -- $new_scenario_tpl)
    echo ""
    read -P "  Save? (Y/n): " confirm
    if test -n "$confirm"; and not contains (string lower -- $confirm) y yes
        echo "  cancelled."
        return 1
    end

    _tgt_export TGT_WORKSPACE_ROOT $new_root
    _tgt_export TGT_WORKSPACE_LAYOUT $new_layout
    if test "$new_auto" = enabled
        _tgt_export TGT_WORKSPACE_AUTOCREATE 1
    else
        set -q TGT_WORKSPACE_AUTOCREATE; and _tgt_unexport TGT_WORKSPACE_AUTOCREATE
    end
    if test (count $new_target_tpl) -gt 0
        _tgt_export TGT_WORKSPACE_TARGET_TEMPLATE $new_target_tpl
    else
        set -q TGT_WORKSPACE_TARGET_TEMPLATE; and _tgt_unexport TGT_WORKSPACE_TARGET_TEMPLATE
    end
    if test (count $new_scenario_tpl) -gt 0
        _tgt_export TGT_WORKSPACE_SCENARIO_TEMPLATE $new_scenario_tpl
    else
        set -q TGT_WORKSPACE_SCENARIO_TEMPLATE; and _tgt_unexport TGT_WORKSPACE_SCENARIO_TEMPLATE
    end

    echo "  ✓ saved (open a new shell or `set -S TGT_WORKSPACE_ROOT` to verify)"
    return 0
end

# Open $EDITOR on a tempfile pre-filled with current entries.
# Returns the parsed list (one per line) on stdout. Empty / comment
# lines are skipped.
function _tgt_config_edit_template
    set -l label $argv[1]
    set -l entries $argv[2..]
    set -l tmp (mktemp --suffix=.tgt-template)
    or return 1
    echo "# $label — one entry per line. Trailing '/' = directory; else touched file." > $tmp
    echo "# Lines starting with '#' (and blank lines) are ignored. Save and exit when done." >> $tmp
    for e in $entries
        echo $e >> $tmp
    end
    set -l editor $EDITOR
    test -z "$editor"; and set editor (command -v vim 2>/dev/null)
    test -z "$editor"; and set editor vi
    $editor $tmp
    set -l rc $status
    if test $rc -ne 0
        echo "tgt config: editor exited non-zero, aborting" >&2
        command rm -f $tmp
        return 1
    end
    while read -l line
        string match -rq '^\s*(#|$)' -- $line; and continue
        echo (string trim -- $line)
    end < $tmp
    command rm -f $tmp
    return 0
end
