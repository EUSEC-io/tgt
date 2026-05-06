# Ask for a text value with `default` shown / pre-filled. Empty
# input keeps the default (matches `_tgt_ask_text`). To CLEAR the
# field, the user types a single `!` — that's the explicit
# delete sentinel.
#
# Behavior:
#   default empty + input empty       → returns empty
#   default empty + input X           → returns X
#   default non-empty + input ""      → returns default (keep)
#   default non-empty + input "!"     → returns empty (clear)
#   default non-empty + input "X!"    → also clear when X == default
#                                       (gum pre-fills the input;
#                                        users typing "!" on top
#                                        of the default get default!)
#   default non-empty + input X       → returns X (replace)
#
# Use this for OPTIONAL fields in edit wizards where the user
# might want to drop the value rather than just keep or replace it.
# `_tgt_ask_text` (the "default-keeps" variant) stays the right
# choice for required fields.
#
# Test injection: pop one entry from `TGT_ASK_QUEUE` per call.
function _tgt_ask_text_optional --argument-names label default
    if set -q TGT_ASK_QUEUE; and test (count $TGT_ASK_QUEUE) -gt 0
        set -l value $TGT_ASK_QUEUE[1]
        set -e TGT_ASK_QUEUE[1]
        if test "$value" = "!"; or begin; test -n "$default"; and test "$value" = "$default!"; end
            echo ""
            return 0
        end
        if test -z "$value"
            echo $default
            return 0
        end
        echo $value
        return 0
    end

    if command -q gum; and not set -q TGT_TEST_MODE; and not set -q TGT_NO_GUM
        set_color --bold yellow >&2; echo -n "  $label" >&2; set_color normal >&2; echo "" >&2
        if test -n "$default"
            set_color brblack >&2
            echo "    [Enter keeps: $default — type ! to clear]" >&2
            set_color normal >&2
        else
            set_color brblack >&2
            echo "    [optional — Enter to skip]" >&2
            set_color normal >&2
        end
        echo "" >&2
        set -l value (command gum input --value "$default")
        set -l rc $status
        echo "" >&2
        test $rc -ne 0; and return $rc
        if test "$value" = "!"; or begin; test -n "$default"; and test "$value" = "$default!"; end
            echo ""
            return 0
        end
        if test -z "$value"
            echo $default
            return 0
        end
        echo $value
        return 0
    end

    if test -n "$default"
        read -P "  $label [$default; '!' to clear]: " value
    else
        read -P "  $label (optional): " value
    end
    set -l rc $status
    test $rc -ne 0; and return $rc
    if test "$value" = "!"
        echo ""
        return 0
    end
    if test -z "$value"
        echo $default
        return 0
    end
    echo $value
    return 0
end
