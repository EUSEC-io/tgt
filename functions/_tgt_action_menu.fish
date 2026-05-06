# Top-level action picker. Invoked when `tgt` runs with no args
# in an interactive shell — mirrors `tgt scenario`'s no-args
# behavior. Falls back to printing the help text when gum isn't
# available or the shell isn't a TTY.
function _tgt_action_menu
    echo ""
    set_color cyan; echo "  tgt — pick an action"; set_color normal
    set -l scen "(none)"
    set -q TGT_SCENARIO; and set scen $TGT_SCENARIO
    set -l targ "(none)"
    set -q TGT_ACTIVE; and set targ $TGT_ACTIVE
    set -l dc "(none)"
    set -q TGT_DC_NAME; and set dc $TGT_DC_NAME
    set_color brblack
    echo "    scenario: $scen"
    echo "    target:   $targ"
    echo "    dc:       $dc"
    set_color normal

    # Order by expected frequency. `cancel` is always last.
    set -l choice (_tgt_ask_choice "Action" switch \
        switch new show edit hosts ports dc scenario revoke cancel)
    if test $status -ne 0
        set_color brblack; echo "  cancelled."; set_color normal
        return 1
    end
    test "$choice" = cancel; and return 0
    test -z "$choice"; and return 0

    # `new` needs an alias up-front; everything else just delegates
    # to the equivalent subcommand (which has its own picker /
    # wizard logic when called without an arg).
    if test "$choice" = new
        set -l name (_tgt_ask_text "New target alias" "")
        if test $status -ne 0; or test -z "$name"
            set_color brblack; echo "  cancelled."; set_color normal
            return 1
        end
        tgt new $name
        return $status
    end

    tgt $choice
    return $status
end
