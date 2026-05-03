# Atomically replace the hosts file with content read from stdin.
# Production: writes to a temp file then `sudo install`s over the real
# path with root:root ownership. Test mode: just `mv`s into place.
function _tgt_hosts_write
    set -l hosts_file (_tgt_hosts_file)
    set -l tmp (command mktemp)
    command cat > $tmp
    if set -q TGT_TEST_MODE
        command mv $tmp $hosts_file
    else
        _tgt_sudo_notice
        command sudo install -m 644 -o root -g root $tmp $hosts_file
        command rm -f $tmp
    end
end
