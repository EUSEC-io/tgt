# Remove the record matching <port>+<proto>. Idempotent: no-op (exit 0)
# if no matching record exists. Removes the file when it ends up empty.
function _tgt_ports_remove --argument-names scenario target port proto
    _tgt_ports_validate_port $port; or return 1
    _tgt_ports_validate_proto $proto; or return 1

    set -l file (_tgt_ports_file $scenario $target)
    test -f $file; or return 0

    set -l tmp (command mktemp)
    while read -l line
        set -l fields (string split \t -- $line)
        test (count $fields) -lt 2; and continue
        if test "$fields[1]" = "$port"; and test "$fields[2]" = "$proto"
            continue
        end
        echo $line >> $tmp
    end < $file

    if test -s $tmp
        command mv -- $tmp $file
    else
        command rm -f -- $tmp $file
    end
end
