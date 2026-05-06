# Ask for a credential-style value. Input is shown plainly (we use
# this for `tgt`'s password prompt — masking was deemed unnecessary
# in pentest workflows). `has_current` is 'yes' if a value already
# exists.
#
# Three return paths via the printed value:
#   <new value>    user typed something — caller sets that
#   "<KEEP>"       "keep current" (only when has_current=yes; user
#                  pressed Enter without typing anything)
#   ""             "clear" intent (only when has_current=yes and
#                  the user typed a literal `!`)
#
# Caller pattern:
#   set -l v (_tgt_ask_password label $has_pass)
#   switch $v
#       case "<KEEP>"  ;# do nothing
#       case ""        ;# clear (caller calls _tgt_unexport)
#       case '*'       ;# set to $v
#   end
function _tgt_ask_password --argument-names label has_current
    if set -q TGT_ASK_QUEUE; and test (count $TGT_ASK_QUEUE) -gt 0
        set -l value $TGT_ASK_QUEUE[1]
        set -e TGT_ASK_QUEUE[1]
        if test "$value" = "!"
            echo ""
            return 0
        end
        if test -z "$value"; and test "$has_current" = yes
            echo "<KEEP>"
            return 0
        end
        echo $value
        return 0
    end

    if command -q gum; and not set -q TGT_TEST_MODE; and not set -q TGT_NO_GUM
        set_color --bold yellow >&2; echo -n "  $label" >&2; set_color normal >&2; echo "" >&2
        if test "$has_current" = yes
            set_color brblack >&2
            echo "    [Enter keeps current — type ! to clear]" >&2
            set_color normal >&2
        end
        echo "" >&2
        set -l value (command gum input)
        set -l rc $status
        echo "" >&2
        test $rc -ne 0; and return $rc
        if test "$value" = "!"
            echo ""
            return 0
        end
        if test -z "$value"; and test "$has_current" = yes
            echo "<KEEP>"
            return 0
        end
        echo $value
        return 0
    end

    if test "$has_current" = yes
        read -P "  $label [Enter to keep, '!' to clear]: " value
    else
        read -P "  $label: " value
    end
    set -l rc $status
    test $rc -ne 0; and return $rc
    if test "$value" = "!"
        echo ""
        return 0
    end
    if test -z "$value"; and test "$has_current" = yes
        echo "<KEEP>"
        return 0
    end
    echo $value
    return 0
end
