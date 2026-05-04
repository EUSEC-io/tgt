# Upsert one port record into a target's ports file.
#
# Identity is <port>+<proto>: re-adding the same pair replaces the
# existing service/comment fields. Records are written sorted by port
# (numeric) then proto so listings are stable and `tgt ports list`
# output diffs cleanly between runs.
#
# Usage: _tgt_ports_add <scenario> <target> <port> <proto> [service] [comment]
function _tgt_ports_add --argument-names scenario target port proto service comment
    _tgt_target_validate_name $target; or return 1
    _tgt_target_exists $scenario $target; or return 1
    _tgt_ports_validate_port $port; or return 1
    _tgt_ports_validate_proto $proto; or return 1
    test -z "$service"; and set service ""
    test -z "$comment"; and set comment ""

    set -l file (_tgt_ports_file $scenario $target)
    set -l tmp (command mktemp)

    # Carry over every existing record except the one we're replacing,
    # then append the new one and re-sort.
    if test -f $file
        while read -l line
            set -l fields (string split \t -- $line)
            test (count $fields) -lt 2; and continue
            if test "$fields[1]" = "$port"; and test "$fields[2]" = "$proto"
                continue
            end
            echo $line >> $tmp
        end < $file
    end
    printf '%s\t%s\t%s\t%s\n' $port $proto $service $comment >> $tmp

    set -l sorted (command mktemp)
    command sort -t (printf '\t') -k1,1n -k2,2 -- $tmp > $sorted
    command rm -f -- $tmp
    command mv -- $sorted $file
end
