# Remove hostname(s) from a (scenario, target)'s tagged line.
# Drops the line entirely if no hostnames remain afterward.
# Usage: _tgt_hosts_remove <scenario> <target> <host>...
function _tgt_hosts_remove
    if test (count $argv) -lt 3
        echo "_tgt_hosts_remove: usage: <scenario> <target> <host>..." >&2
        return 1
    end

    set -l scenario $argv[1]
    set -l target $argv[2]
    set -l rm_hosts $argv[3..]

    set -l hosts_file (_tgt_hosts_file)
    set -l tag (_tgt_hosts_tag $scenario $target)
    set -l lines (command cat $hosts_file 2>/dev/null)

    set -l keep
    for line in $lines
        if string match -rq -- ".*\s$tag\$" $line
            set -l body (string replace -r "\s+$tag\$" "" -- $line)
            set -l fields (string split -n " " -- (string replace -ar '\s+' ' ' -- $body))
            set -l ip $fields[1]
            set -e fields[1]

            set -l remaining
            for h in $fields
                if not contains -- $h $rm_hosts
                    set -a remaining $h
                end
            end

            if test (count $remaining) -gt 0
                set -a keep "$ip "(string join " " -- $remaining)" $tag"
            end
        else
            set -a keep $line
        end
    end

    printf '%s\n' $keep | _tgt_hosts_write
end
