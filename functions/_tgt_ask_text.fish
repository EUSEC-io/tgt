# Ask for a single-line text value, with `default` shown / pre-filled.
# Echoes label and default hint to stderr so they stay in scrollback,
# then runs gum input (or `read` fallback) for the actual edit.
# Empty input → default. Returns non-zero if gum/read aborted (Ctrl-C).
#
# Test injection: when `TGT_ASK_QUEUE` is set and non-empty, pop the
# first entry and use it as the answer instead of prompting. Lets
# tests drive multi-prompt wizards without juggling stdin pipes
# (fish command substitution doesn't pass stdin to its inner cmd).
function _tgt_ask_text --argument-names label default
    if set -q TGT_ASK_QUEUE; and test (count $TGT_ASK_QUEUE) -gt 0
        set -l value $TGT_ASK_QUEUE[1]
        set -e TGT_ASK_QUEUE[1]
        test -z "$value"; and set value "$default"
        echo $value
        return 0
    end

    if command -q gum; and not set -q TGT_TEST_MODE; and not set -q TGT_NO_GUM
        set_color --bold yellow >&2; echo -n "  $label" >&2; set_color normal >&2; echo "" >&2
        if test -n "$default"
            set_color brblack >&2; echo "    [press Enter to keep: $default]" >&2; set_color normal >&2
        else
            set_color brblack >&2; echo "    [optional — Enter to skip]" >&2; set_color normal >&2
        end
        echo "" >&2
        set -l value (command gum input --value "$default")
        set -l rc $status
        echo "" >&2
        test $rc -ne 0; and return $rc
        test -z "$value"; and set value "$default"
        echo $value
        return 0
    end

    if test -n "$default"
        read -P "  $label [$default]: " value
    else
        read -P "  $label (optional): " value
    end
    set -l rc $status
    test $rc -ne 0; and return $rc
    test -z "$value"; and set value "$default"
    echo $value
    return 0
end
