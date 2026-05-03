# Pick one item from a list interactively.
# Uses fzf if available; falls back to a numbered-list `read` prompt.
#
# Test overrides:
#   $TGT_PICKER_TEST_RESULT: bypass entirely, echo this value and exit 0.
#                            Use from tests of picker *callers*.
#   $TGT_PICKER_NO_FZF:      skip fzf, force the numbered fallback. Used
#                            by direct fallback-logic tests.
#   $TGT_PICKER_USE_STDIN:   read user input from stdin instead of /dev/tty.
#                            Used by direct fallback tests so they don't
#                            need a real terminal.
#
# Why /dev/tty by default? When _tgt_pick is invoked inside a command
# substitution (the typical caller pattern: `set alias (_tgt_pick ...)`),
# fish closes the inner stdin. Reading from /dev/tty bypasses that.
#
# Usage: _tgt_pick "<prompt>" item1 item2 ...
# Output: chosen item on stdout, empty + nonzero exit if nothing chosen.
function _tgt_pick --argument-names prompt
    set -e argv[1]
    set -l items $argv

    test (count $items) -eq 0; and return 1

    if set -q TGT_PICKER_TEST_RESULT
        echo $TGT_PICKER_TEST_RESULT
        return 0
    end

    if command -q fzf; and not set -q TGT_PICKER_NO_FZF
        # fzf opens /dev/tty itself, so it works inside command substitutions.
        printf '%s\n' $items | command fzf \
            --prompt="$prompt> " \
            --height=40% \
            --reverse \
            --no-multi
        return $status
    end

    for i in (seq (count $items))
        echo "  [$i] $items[$i]" >&2
    end
    set -l choice
    if set -q TGT_PICKER_USE_STDIN
        read -P "$prompt [1-"(count $items)"]: " choice
    else
        read -P "$prompt [1-"(count $items)"]: " choice </dev/tty
    end
    if string match -rq '^[0-9]+$' -- $choice
        if test $choice -ge 1; and test $choice -le (count $items)
            echo $items[$choice]
            return 0
        end
    end
    return 1
end
