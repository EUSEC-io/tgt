# Rewrite /etc/hosts lines tagged for (old_scenario, old_target) so
# they're tagged for (new_scenario, new_target) instead. No-op when
# no matching lines exist.
# Usage: _tgt_hosts_retag <old_scenario> <old_target> <new_scenario> <new_target>
function _tgt_hosts_retag --argument-names old_scenario old_target new_scenario new_target
    set -l hosts_file (_tgt_hosts_file)
    set -l old_tag (_tgt_hosts_tag $old_scenario $old_target)
    set -l new_tag (_tgt_hosts_tag $new_scenario $new_target)
    set -l lines (command cat $hosts_file 2>/dev/null)
    set -l escaped (string escape --style=regex -- $old_tag)

    set -l updated
    set -l changed 0
    for line in $lines
        if string match -rq -- ".*\s$escaped\$" $line
            set line (string replace -- $old_tag $new_tag $line)
            set changed 1
        end
        set -a updated $line
    end

    test $changed -eq 0; and return 0
    printf '%s\n' $updated | _tgt_hosts_write
end
