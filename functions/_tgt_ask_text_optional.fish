# Ask for a text value with `default` shown / pre-filled, but treat
# explicit empty input as a clear-intent (when default is non-empty)
# rather than silently keeping the default.
#
# Behavior:
#   default empty + input empty   → returns empty (nothing to clear)
#   default empty + input X       → returns X
#   default non-empty + input X   → returns X
#   default non-empty + input ""  → confirm "Clear (was: X)?". `n` keeps,
#                                   `y` clears.
#
# Use this for OPTIONAL fields in edit wizards where the user
# might want to drop the value rather than just keep or replace it.
# `_tgt_ask_text` (the "default-keeps" variant) stays the right
# choice for required fields.
#
# Test injection follows the same TGT_ASK_QUEUE pattern as the
# other ask_* helpers — both this prompt AND the clear-confirm
# pull from the queue, so tests must include the confirm answer
# when an empty input would trigger one.
function _tgt_ask_text_optional --argument-names label default
    if set -q TGT_ASK_QUEUE; and test (count $TGT_ASK_QUEUE) -gt 0
        set -l value $TGT_ASK_QUEUE[1]
        set -e TGT_ASK_QUEUE[1]
        if test -z "$value"; and test -n "$default"
            # Empty input + has-default → confirm clear.
            set -l confirm (_tgt_ask_confirm "Clear '$default'?" n)
            if test "$confirm" = yes
                echo ""
                return 0
            end
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
            echo "    [press Enter to keep: $default — clear it by deleting + Enter]" >&2
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
        if test -z "$value"; and test -n "$default"
            set -l confirm (_tgt_ask_confirm "Clear '$default'?" n)
            if test "$confirm" = yes
                echo ""
                return 0
            end
            echo $default
            return 0
        end
        echo $value
        return 0
    end

    if test -n "$default"
        read -P "  $label [$default; '' to clear]: " value
    else
        read -P "  $label (optional): " value
    end
    set -l rc $status
    test $rc -ne 0; and return $rc
    if test -z "$value"; and test -n "$default"
        set -l confirm (_tgt_ask_confirm "Clear '$default'?" n)
        if test "$confirm" = yes
            echo ""
            return 0
        end
        echo $default
        return 0
    end
    echo $value
    return 0
end
