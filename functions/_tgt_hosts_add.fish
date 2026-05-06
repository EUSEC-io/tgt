# Add hostname(s) to a (scenario, target)'s tagged line in /etc/hosts.
# Creates the line if it doesn't exist. Existing hostnames are preserved
# and deduplicated against the new ones.
# Usage: _tgt_hosts_add <scenario> <target> <ip> <host>...
function _tgt_hosts_add
    if test (count $argv) -lt 4
        echo "_tgt_hosts_add: usage: <scenario> <target> <ip> <host>..." >&2
        return 1
    end

    set -l scenario $argv[1]
    set -l target $argv[2]
    set -l ip $argv[3]
    # /etc/hosts is case-insensitive in DNS terms — lowercase here
    # so duplicates can't sneak in via case differences. krb5 keeps
    # the case from the DC entry (kerberos SPNs are case-sensitive).
    set -l new_hosts (string lower -- $argv[4..])

    set -l hosts_file (_tgt_hosts_file)
    set -l tag (_tgt_hosts_tag $scenario $target)
    set -l lines (command cat $hosts_file 2>/dev/null)

    set -l keep
    set -l existing
    for line in $lines
        if string match -rq -- ".*\s$tag\$" $line
            set -l body (string replace -r "\s+$tag\$" "" -- $line | string replace -r "^\S+\s+" "")
            set existing (string split -n " " -- (string replace -ar '\s+' ' ' -- $body))
        else
            set -a keep $line
        end
    end

    for h in $new_hosts
        if not contains -- $h $existing
            set -a existing $h
        end
    end

    set -a keep "$ip "(string join " " -- $existing)" $tag"
    printf '%s\n' $keep | _tgt_hosts_write
end
