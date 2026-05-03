# Edit a list of entries (one per line). Uses `gum write` if
# available; otherwise opens $EDITOR (vim/vi fallback) on a tempfile
# pre-filled with the current entries.
#
# Echoes the parsed list on stdout (one entry per line). Comment
# lines (starting with '#') and blank lines are skipped. Returns
# non-zero if the editor aborted.
function _tgt_ask_multiline
    set -l label $argv[1]
    set -l entries $argv[2..]

    if command -q gum; and not set -q TGT_TEST_MODE
        set_color --bold yellow >&2; echo -n "  $label" >&2; set_color normal >&2; echo "" >&2
        set_color brblack >&2; echo "    [Esc or Ctrl-D to save & exit; one entry per line; trailing '/' = dir]" >&2; set_color normal >&2
        echo "" >&2
        set -l initial (string join \n -- $entries | string collect)
        set -l raw (command gum write --value "$initial" --width 60 --height 12 | string collect)
        set -l rc $status
        echo "" >&2
        test $rc -ne 0; and return $rc
        for line in (string split \n -- $raw)
            test -z "$line"; and continue
            string match -rq '^\s*#' -- $line; and continue
            echo (string trim -- $line)
        end
        return 0
    end

    set -l tmp (mktemp --suffix=.tgt-template)
    or return 1
    echo "# $label — one entry per line. Trailing '/' = directory; else touched file." > $tmp
    echo "# Lines starting with '#' (and blank lines) are ignored. Save and exit when done." >> $tmp
    for e in $entries
        echo $e >> $tmp
    end
    set -l editor $EDITOR
    test -z "$editor"; and set editor (command -v vim 2>/dev/null)
    test -z "$editor"; and set editor vi
    $editor $tmp
    set -l rc $status
    if test $rc -ne 0
        echo "tgt: editor exited non-zero, aborting" >&2
        command rm -f $tmp
        return 1
    end
    while read -l line
        string match -rq '^\s*(#|$)' -- $line; and continue
        echo (string trim -- $line)
    end < $tmp
    command rm -f $tmp
    return 0
end
