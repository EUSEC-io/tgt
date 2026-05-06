# Resolve a host_name to an IPv4 address. Tries /etc/hosts first
# (manual entries + tgt-tagged lines), then DNS with a short
# timeout. On success, prints two lines:
#
#   <ip>
#   <source>      ; one of "hosts" / "dns"
#
# Returns non-zero with no output when nothing matched.
#
# Used at DC create/edit time to fill in a missing kdc-ip /
# admin-ip when the user only supplied the host_name. Read-only:
# does not write to /etc/hosts itself — the apply_scenario step
# does that, since we'll have just stored the resolved IP into
# the DC entry.
function _tgt_resolve_ip --argument-names host_name
    test -z "$host_name"; and return 1
    set -l lc (string lower -- $host_name)

    # ── Step 1: /etc/hosts lookup (manual entries only) ─────
    # Skip tgt-tagged lines — those were written by us, so
    # consulting them creates a feedback loop: clearing a field
    # would re-fill itself from the entry's own previous
    # /etc/hosts line.
    set -l hosts_file (_tgt_hosts_file)
    if test -f $hosts_file
        while read -l line
            string match -rq '^\s*#' -- $line; and continue
            string match -q '*# tgt:*' -- $line; and continue
            set -l body (string replace -r '\s*#.*$' '' -- $line)
            set -l fields (string split -n " " -- $body)
            test (count $fields) -lt 2; and continue
            set -l ip $fields[1]
            for h in $fields[2..]
                if test (string lower -- $h) = "$lc"
                    echo $ip
                    echo hosts
                    return 0
                end
            end
        end < $hosts_file
    end

    # ── Step 2: DNS probe with short timeout ────────────────
    # Prefer `host` (bind9-host) for explicit DNS + timeout flag;
    # fall back to `getent` (glibc) which respects nsswitch order.
    if command -q host
        set -l result (command host -W 2 $host_name 2>/dev/null | string match -ra '\d+\.\d+\.\d+\.\d+')
        if test (count $result) -ge 1
            echo $result[1]
            echo dns
            return 0
        end
    else if command -q getent
        set -l result (command getent ahostsv4 $host_name 2>/dev/null | head -1 | string split -n " " | string match -r '^\d+\.\d+\.\d+\.\d+$')
        if test -n "$result"
            echo $result
            echo dns
            return 0
        end
    end

    return 1
end
