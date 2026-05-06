# Ask for a credential-style value. Input is shown plainly (we use
# this for `tgt`'s password prompt — masking was deemed unnecessary
# in pentest workflows). `has_current` is 'yes' if a value already
# exists.
#
# Three return paths via the printed value:
#   <new value>    user typed something — caller sets that
#   ""             "clear" intent (only after a confirm-clear pass)
#   "<KEEP>"       "keep current" (only when has_current=yes)
#
# Empty input semantics:
#   has_current=yes: confirm "Clear current?" — yes → "", no → "<KEEP>"
#   has_current=no:  empty just returns empty (skip)
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
        if test -z "$value"; and test "$has_current" = yes
            set -l confirm (_tgt_ask_confirm "Clear current password?" n)
            if test "$confirm" = yes
                echo ""
                return 0
            end
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
            echo "    [Enter to keep — clear by deleting and confirming]" >&2
            set_color normal >&2
        end
        echo "" >&2
        set -l value (command gum input)
        set -l rc $status
        echo "" >&2
        test $rc -ne 0; and return $rc
        if test -z "$value"; and test "$has_current" = yes
            set -l confirm (_tgt_ask_confirm "Clear current password?" n)
            if test "$confirm" = yes
                echo ""
                return 0
            end
            echo "<KEEP>"
            return 0
        end
        echo $value
        return 0
    end

    if test "$has_current" = yes
        read -P "  $label [Enter to keep, '' + confirm to clear]: " value
    else
        read -P "  $label: " value
    end
    set -l rc $status
    test $rc -ne 0; and return $rc
    if test -z "$value"; and test "$has_current" = yes
        set -l confirm (_tgt_ask_confirm "Clear current password?" n)
        if test "$confirm" = yes
            echo ""
            return 0
        end
        echo "<KEEP>"
        return 0
    end
    echo $value
    return 0
end
