# Drop the entire (scenario, target) line from /etc/hosts. No-op if no
# such line exists.
# Usage: _tgt_hosts_revoke <scenario> <target>
function _tgt_hosts_revoke --argument-names scenario target
    set -l hosts_file (_tgt_hosts_file)
    set -l tag (_tgt_hosts_tag $scenario $target)
    set -l lines (command cat $hosts_file 2>/dev/null)

    set -l keep
    for line in $lines
        if not string match -rq -- ".*\s$tag\$" $line
            set -a keep $line
        end
    end

    printf '%s\n' $keep | _tgt_hosts_write
end
