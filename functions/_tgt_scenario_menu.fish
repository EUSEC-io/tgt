# Interactive scenario action picker. Used when `tgt scenario` is
# invoked with no verb in an interactive shell. Falls back to the
# help text in non-interactive contexts (no gum / test mode / no tty).
function _tgt_scenario_menu
    echo ""
    set_color cyan; echo "  tgt scenario — pick an action"; set_color normal
    set -l current "(none)"
    set -q TGT_SCENARIO; and set current $TGT_SCENARIO
    set_color brblack; echo "    active scenario: $current"; set_color normal

    set -l choice (_tgt_ask_choice "Action" new new switch show rm cancel)
    if test $status -ne 0
        set_color brblack; echo "  cancelled."; set_color normal
        return 1
    end
    test "$choice" = cancel; and return 0
    test -z "$choice"; and return 0

    # `new` needs a name; the others delegate (switch/show/rm without
    # an arg use fzf or default to the active scenario).
    if test "$choice" = new
        set -l name (_tgt_ask_text "New scenario name" "")
        if test $status -ne 0; or test -z "$name"
            set_color brblack; echo "  cancelled."; set_color normal
            return 1
        end
        _tgt_scenario_cli new $name
        return $status
    end

    _tgt_scenario_cli $choice
    return $status
end
