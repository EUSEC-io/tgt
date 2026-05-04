# Ask for a credential-style value. Input is shown plainly (we use
# this for `tgt`'s password prompt — masking was deemed unnecessary
# in pentest workflows). `has_current` is 'yes' if there is a
# current value the user can keep by pressing Enter, else 'no'.
# Echoes the entered value (empty = "keep current" / "skip"),
# returns non-zero on abort.
function _tgt_ask_password --argument-names label has_current
    if command -q gum; and not set -q TGT_TEST_MODE; and not set -q TGT_NO_GUM
        set_color --bold yellow >&2; echo -n "  $label" >&2; set_color normal >&2; echo "" >&2
        if test "$has_current" = yes
            set_color brblack >&2; echo "    [Enter to keep current]" >&2; set_color normal >&2
        end
        echo "" >&2
        set -l value (command gum input)
        set -l rc $status
        echo "" >&2
        test $rc -ne 0; and return $rc
        echo $value
        return 0
    end

    if test "$has_current" = yes
        read -P "  $label [Enter to keep]: " value
    else
        read -P "  $label: " value
    end
    set -l rc $status
    test $rc -ne 0; and return $rc
    echo $value
    return 0
end
