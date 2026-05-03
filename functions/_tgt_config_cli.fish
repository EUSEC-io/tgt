# Dispatch for `tgt config <verb>`. Called from tgt.fish.
function _tgt_config_cli
    set -l verb ""
    test (count $argv) -ge 1; and set verb $argv[1]

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
            echo "    tgt config show         Print current settings"
            echo "    tgt config reset        Erase all custom workspace settings"
            echo ""
            echo "  Settings are persisted as fish universals so they survive shell"
            echo "  restarts. Templates are entries (one per line); trailing '/'"
            echo "  marks a directory, anything else is a file. Uses `gum` if"
            echo "  installed, plain `read` + \$EDITOR otherwise."
            echo ""
            return 0
        case '*'
            echo "tgt config: unknown verb '$verb'" >&2
            echo "Try: tgt config --help" >&2
            return 1
    end
end

function _tgt_config_reset
    # Erase from every scope: globals (live), universals (legacy
    # pre-file storage), and delete the file itself.
    for v in TGT_WORKSPACE_ROOT TGT_WORKSPACE_LAYOUT TGT_WORKSPACE_AUTOCREATE TGT_WORKSPACE_TARGET_TEMPLATE TGT_WORKSPACE_SCENARIO_TEMPLATE
        set -qg $v; and set -eg $v
        set -qU $v; and set -eU $v
    end
    set -l file (_tgt_config_file)
    test -f $file; and command rm -f -- $file
    echo "  ✓ workspace settings reset to defaults"
end

function _tgt_config_edit
    set -l ui_mode plain
    command -q gum; and not set -q TGT_TEST_MODE; and set ui_mode gum

    # ── Intro ──
    echo ""
    set_color cyan; echo "  ══════════════════════════════════════════════════════"; set_color normal
    set_color --bold cyan; echo "  tgt config — workspace settings wizard"; set_color normal
    set_color cyan; echo "  ══════════════════════════════════════════════════════"; set_color normal
    echo ""
    set_color --bold; echo "  CONCEPTS"; set_color normal
    echo "    SCENARIO   An engagement, HTB Pro Lab season, or"
    echo "               client. Holds a set of related targets."
    echo "    TARGET     One box / host. Has IP, port, creds,"
    echo "               AD info, and hostnames."
    echo "    WORKSPACE  Per-scenario / per-target dir on disk for"
    echo "               scans, loot, exploits, notes — useful for"
    echo "               reporting at the end of an engagement."
    echo ""
    echo "  This wizard configures where workspace folders live,"
    echo "  the layout (flat vs. nested), the per-scenario and"
    echo "  per-target template, and whether folders are auto-built"
    echo "  by `tgt scenario new` / `tgt new`."
    echo ""
    set_color brblack
    echo "  Press Ctrl-C any time to abort."
    echo "  Press Enter at any prompt to keep the current value."
    echo "  UI mode: $ui_mode"
    set_color normal

    # ── 1. Workspace root ──
    _tgt_ui_section "1/5" "Workspace root"
    echo "    The directory under which all per-scenario / per-target"
    echo "    folders live."
    set -l new_root (_tgt_ask_text "Workspace root" (_tgt_workspace_root))
    if test $status -ne 0
        echo "  aborted." >&2
        return 1
    end

    # ── 2. Layout ──
    _tgt_ui_section "2/5" "Layout"
    echo "    flat   — every folder lives at scenario level."
    echo "             Best for HTB single boxes."
    echo "    nested — each target gets its own subfolder; the"
    echo "             scenario root holds report assets. Best"
    echo "             for Pro Labs and client engagements with"
    echo "             multiple targets."
    set -l new_layout (_tgt_ask_choice "Layout" (_tgt_workspace_layout) flat nested)
    if test $status -ne 0
        echo "  aborted." >&2
        return 1
    end

    # ── 3. Autocreate ──
    _tgt_ui_section "3/5" "Auto-create folders"
    echo "    When on, `tgt scenario new` and `tgt new` automatically"
    echo "    build the workspace tree from the templates below. Off"
    echo "    means folders are never created without explicit action."
    set -l current_auto n
    _tgt_workspace_autocreate; and set current_auto y
    set -l auto_ans (_tgt_ask_confirm "Auto-create on `tgt new` / `tgt scenario new`?" $current_auto)
    if test $status -ne 0
        echo "  aborted." >&2
        return 1
    end
    set -l new_auto n
    test "$auto_ans" = yes; and set new_auto y

    # ── 4. Per-target template ──
    _tgt_ui_section "4/5" "Per-target template"
    echo "    Folders and files created inside each target's dir"
    echo "    (nested layout) or directly under the scenario (flat)."
    echo "    Trailing '/' = directory; anything else = touched file."
    echo "    Default: scans/  loot/  exploits/  screenshots/  notes.md"
    set -l new_target_tpl (_tgt_ask_multiline "Per-target template (one entry per line)" (_tgt_workspace_target_template))
    if test $status -ne 0
        echo "  aborted." >&2
        return 1
    end

    # ── 5. Per-scenario template ──
    _tgt_ui_section "5/5" "Per-scenario template (nested layout only)"
    echo "    Applied at the scenario root in nested layout. Use it"
    echo "    for cross-target assets like report folders or an"
    echo "    engagement README. Ignored in flat layout."
    echo "    Default: _report/findings/  _report/screenshots/  _engagement.md"
    set -l new_scenario_tpl (_tgt_ask_multiline "Per-scenario template (one entry per line)" (_tgt_workspace_scenario_template))
    if test $status -ne 0
        echo "  aborted." >&2
        return 1
    end

    # ── Summary ──
    set -l auto_label disabled
    test "$new_auto" = y; and set auto_label enabled

    echo ""
    set_color cyan
    echo "  ─── Summary ──────────────────────────────────────────"
    set_color normal
    echo "    root:        $new_root"
    echo "    layout:      $new_layout"
    echo "    autocreate:  $auto_label"
    echo "    per-target template ("(count $new_target_tpl)" entries):"
    for e in $new_target_tpl
        echo "      • $e"
    end
    echo "    per-scenario template ("(count $new_scenario_tpl)" entries):"
    for e in $new_scenario_tpl
        echo "      • $e"
    end
    set -l save_ans (_tgt_ask_confirm "Save these settings?" y)
    if test $status -ne 0
        echo "  aborted." >&2
        return 1
    end
    if test "$save_ans" != yes
        echo "  cancelled, nothing changed."
        return 1
    end

    # Update globals (live shell) and persist to file. Each var
    # is either set globally or erased from globals (so that the
    # saved file matches the new state exactly).
    set -gx TGT_WORKSPACE_ROOT $new_root
    set -gx TGT_WORKSPACE_LAYOUT $new_layout
    if test "$new_auto" = y
        set -gx TGT_WORKSPACE_AUTOCREATE 1
    else
        set -qg TGT_WORKSPACE_AUTOCREATE; and set -eg TGT_WORKSPACE_AUTOCREATE
    end
    if test (count $new_target_tpl) -gt 0
        set -gx TGT_WORKSPACE_TARGET_TEMPLATE $new_target_tpl
    else
        set -qg TGT_WORKSPACE_TARGET_TEMPLATE; and set -eg TGT_WORKSPACE_TARGET_TEMPLATE
    end
    if test (count $new_scenario_tpl) -gt 0
        set -gx TGT_WORKSPACE_SCENARIO_TEMPLATE $new_scenario_tpl
    else
        set -qg TGT_WORKSPACE_SCENARIO_TEMPLATE; and set -eg TGT_WORKSPACE_SCENARIO_TEMPLATE
    end

    _tgt_config_save

    set_color green; echo "  ✓ saved to "(_tgt_config_file); set_color normal
    return 0
end
