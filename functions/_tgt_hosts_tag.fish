# Format the /etc/hosts comment tag for a (scenario, target) pair.
function _tgt_hosts_tag --argument-names scenario target
    echo "# tgt:$scenario:$target"
end
