# Create a scenario's directory (and its empty targets/ subdir).
# Idempotent: succeeds on existing scenarios. Returns 1 on invalid names.
function _tgt_scenario_create --argument-names name
    if not _tgt_scenario_validate_name $name
        echo "_tgt_scenario_create: invalid scenario name: '$name'" >&2
        return 1
    end
    command mkdir -p (_tgt_scenario_dir $name)/targets
end
