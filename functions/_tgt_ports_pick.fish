# Interactive port picker for the active target.
#
# Prints "port/proto" (e.g. "445/tcp") on stdout for the chosen
# record; non-zero exit + empty stdout if the user aborts or no
# records exist. Each line is rendered via _tgt_ports_format_record
# so interesting ports glow even inside fzf (we pass --ansi).
#
# Implementation note: we prefix each line with "<port/proto>\x1f"
# and tell fzf to render only fields after \x1f via --with-nth=2..
# That way the visible list stays clean while the chosen line still
# carries the structured key — no ANSI-stripping gymnastics needed.
#
# Test overrides mirror _tgt_pick: TGT_PICKER_TEST_RESULT bypasses
# entirely, TGT_PICKER_NO_FZF forces the numbered fallback.
function _tgt_ports_pick --argument-names scenario target
    set -l records (_tgt_ports_list $scenario $target)
    test (count $records) -eq 0; and return 1

    set -l US (printf '\x1f')
    set -l input
    for rec in $records
        set -l fields (string split \t -- $rec)
        test (count $fields) -lt 2; and continue
        set -l service ""
        set -l comment ""
        test (count $fields) -ge 3; and set service $fields[3]
        test (count $fields) -ge 4; and set comment $fields[4]
        set -l display (_tgt_ports_format_record $fields[1] $fields[2] $service $comment)
        set -a input "$fields[1]/$fields[2]$US$display"
    end
    test (count $input) -eq 0; and return 1

    if set -q TGT_PICKER_TEST_RESULT
        echo $TGT_PICKER_TEST_RESULT
        return 0
    end

    if command -q fzf; and not set -q TGT_PICKER_NO_FZF
        set -l choice (printf '%s\n' $input | command fzf \
            --ansi \
            --with-nth=2.. \
            --delimiter=$US \
            --prompt="port> " \
            --height=40% \
            --reverse \
            --no-multi)
        test -z "$choice"; and return 1
        echo (string split $US -- $choice)[1]
        return 0
    end

    for i in (seq (count $input))
        set -l parts (string split $US -- $input[$i])
        echo "  [$i] $parts[2]" >&2
    end
    set -l choice
    if set -q TGT_PICKER_USE_STDIN
        read -P "port [1-"(count $input)"]: " choice
    else
        read -P "port [1-"(count $input)"]: " choice </dev/tty
    end
    if string match -rq '^[0-9]+$' -- $choice
        if test $choice -ge 1; and test $choice -le (count $input)
            set -l parts (string split $US -- $input[$choice])
            echo $parts[1]
            return 0
        end
    end
    return 1
end
