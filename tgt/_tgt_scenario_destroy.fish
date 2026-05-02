# Remove a scenario's directory tree from the registry.
# Idempotent: succeeds on missing scenarios. Returns 1 on invalid names.
# Does NOT touch /etc/hosts or krb5.conf — that's a higher layer's job.
function _tgt_scenario_destroy --argument-names name
    _tgt_scenario_validate_name $name; or return 1
    set -l dir (_tgt_scenario_dir $name)
    test -d $dir; or return 0
    command rm -rf $dir
end
