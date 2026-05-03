# Ask a yes/no question. `default_yn` is 'y' or 'n'.
# Echoes 'yes' or 'no' on stdout and returns 0 on a clean answer.
# Returns non-zero only on abort (Ctrl-C / gum failure).
function _tgt_ask_confirm --argument-names label default_yn
    if command -q gum; and not set -q TGT_TEST_MODE; and not set -q TGT_NO_GUM
        echo "" >&2
        if test "$default_yn" = y
            command gum confirm "$label"
        else
            command gum confirm --default=false "$label"
        end
        set -l rc $status
        echo "" >&2
        switch $rc
            case 0
                echo yes
                return 0
            case 1
                echo no
                return 0
            case '*'
                return $rc
        end
    end

    set -l prompt "  $label "
    if test "$default_yn" = y
        set prompt "$prompt(Y/n): "
    else
        set prompt "$prompt(y/N): "
    end
    read -P "$prompt" value
    set -l rc $status
    test $rc -ne 0; and return $rc
    if test -z "$value"
        test "$default_yn" = y; and echo yes; or echo no
        return 0
    end
    switch (string lower -- $value)
        case y yes 1 true
            echo yes
        case '*'
            echo no
    end
    return 0
end
