# Drop every /etc/hosts line tagged for the named scenario, regardless
# of which target it belonged to. Engagement-teardown helper.
function _tgt_hosts_revoke_scenario --argument-names scenario
    set -l hosts_file (_tgt_hosts_file)
    set -l lines (command cat $hosts_file 2>/dev/null)

    set -l keep
    for line in $lines
        if not string match -rq -- ".*\s# tgt:$scenario:[A-Za-z0-9_][A-Za-z0-9_-]*\$" $line
            set -a keep $line
        end
    end

    printf '%s\n' $keep | _tgt_hosts_write
end
