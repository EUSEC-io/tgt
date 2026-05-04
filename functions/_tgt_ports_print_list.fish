# Print a target's port records, one per line, with ANSI marker for
# interesting ones. Used by `tgt ports list` and as the leading
# summary before the picker in `tgt ports`.
function _tgt_ports_print_list --argument-names scenario target
    set -l records (_tgt_ports_list $scenario $target)
    if test (count $records) -eq 0
        echo "(no ports recorded for $scenario:$target)"
        return 0
    end
    for rec in $records
        set -l fields (string split \t -- $rec)
        test (count $fields) -lt 2; and continue
        set -l service ""
        set -l comment ""
        test (count $fields) -ge 3; and set service $fields[3]
        test (count $fields) -ge 4; and set comment $fields[4]
        _tgt_ports_format_record $fields[1] $fields[2] $service $comment
        echo
    end
end
