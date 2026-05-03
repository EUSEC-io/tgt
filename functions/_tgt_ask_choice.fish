# Pick one of $choices, defaulting to $default. Echoes label and a
# selector hint to stderr, then runs gum choose (or `read` fallback).
# Returns non-zero if aborted (Ctrl-C).
# Args: label default choice1 choice2 ...
function _tgt_ask_choice
    set -l label $argv[1]
    set -l default $argv[2]
    set -l choices $argv[3..]

    if command -q gum; and not set -q TGT_TEST_MODE; and not set -q TGT_NO_GUM
        set_color --bold yellow >&2; echo -n "  $label" >&2; set_color normal >&2; echo "" >&2
        set_color brblack >&2; echo "    [↑/↓ to select, Enter to confirm; current: $default]" >&2; set_color normal >&2
        echo "" >&2
        set -l value (command gum choose --selected "$default" $choices)
        set -l rc $status
        echo "" >&2
        test $rc -ne 0; and return $rc
        test -z "$value"; and set value "$default"
        echo $value
        return 0
    end

    set -l joined (string join '/' -- $choices)
    while true
        read -P "  $label, $joined [$default]: " value
        set -l rc $status
        test $rc -ne 0; and return $rc
        test -z "$value"; and set value "$default"
        if contains -- $value $choices
            echo $value
            return 0
        end
        echo "    invalid; expected one of: $joined" >&2
    end
end
