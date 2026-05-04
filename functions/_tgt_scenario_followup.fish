# Interactive chain run after `tgt scenario new` / `tgt scenario
# switch`. Suggests creating a target (when the scenario is empty)
# or loading one (when it has them). Skipped in TGT_TEST_MODE and
# non-TTY contexts so scripts/CI/tests are unaffected.
function _tgt_scenario_followup --argument-names scenario
    set -q TGT_TEST_MODE; and return 0
    isatty stdin; or return 0
    test -z "$scenario"; and return 0

    set -l targets (_tgt_target_list $scenario)
    set -l count (count $targets)

    if test $count -eq 0
        set -l ans (_tgt_ask_confirm "No targets in '$scenario' yet. Create one now?" y)
        test $status -ne 0; and return 0
        test "$ans" != yes; and return 0
        set -l alias (_tgt_ask_text "Target alias" "")
        if test $status -ne 0; or test -z "$alias"
            set_color brblack; echo "  cancelled."; set_color normal
            return 0
        end
        _tgt_target_cli new $alias
        return $status
    end

    if test $count -eq 1
        set -l only $targets[1]
        set -l ans (_tgt_ask_confirm "Load target '$only'?" y)
        test $status -ne 0; and return 0
        test "$ans" != yes; and return 0
        _tgt_target_cli switch $only
        return $status
    end

    set -l ans (_tgt_ask_confirm "Pick a target now?" y)
    test $status -ne 0; and return 0
    test "$ans" != yes; and return 0
    _tgt_target_cli switch
    return $status
end
