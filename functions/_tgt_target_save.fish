# Snapshot the current $TGT* env vars into a target's registry file.
# The file is written as `_tgt_export <var> <values>` lines so it can
# be sourced (via _tgt_target_load) and respects production-vs-test
# scoping the same way live exports do.
function _tgt_target_save --argument-names scenario target
    _tgt_scenario_validate_name $scenario; or return 1
    _tgt_target_validate_name $target; or return 1
    _tgt_scenario_exists $scenario; or return 1

    set -l file (_tgt_target_file $scenario $target)
    set -l tmp (command mktemp)

    for var in TGT TGT_USERNAME TGT_PASSWORD TGT_HOSTS
        if set -q $var
            set -l escaped (string escape -- $$var)
            echo "_tgt_export $var "(string join " " -- $escaped) >> $tmp
        end
    end

    command mv $tmp $file
end
