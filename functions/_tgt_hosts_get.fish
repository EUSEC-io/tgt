# Output the hostnames recorded for a (scenario, target) — one per line.
# No output if no matching line exists.
function _tgt_hosts_get --argument-names scenario target
    set -l hosts_file (_tgt_hosts_file)
    set -l tag (_tgt_hosts_tag $scenario $target)
    set -l lines (command cat $hosts_file 2>/dev/null)
    set -l line (string match -r ".*\s$tag\$" -- $lines)
    test -z "$line"; and return 0

    set -l body (string replace -r "\s+$tag\$" "" -- $line)
    set -l fields (string split -n " " -- (string replace -ar '\s+' ' ' -- $body))
    # fields[1] is IP; the rest are hostnames.
    set -e fields[1]
    printf '%s\n' $fields
end
