# Path to the hosts file. Override via $TGT_HOSTS_FILE for tests.
function _tgt_hosts_file
    if set -q TGT_HOSTS_FILE
        echo $TGT_HOSTS_FILE
    else
        echo /etc/hosts
    end
end
