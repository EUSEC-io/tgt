# Write the currently-set workspace settings to the config file.
# Only writes vars that are set in the current shell — unset vars
# are omitted, so loading the file later leaves them at their
# default. Atomic via `mktemp` + `mv`.
function _tgt_config_save
    set -l file (_tgt_config_file)
    set -l dir (dirname -- $file)
    mkdir -p -- $dir
    set -l tmp (command mktemp)

    echo "# tgt workspace config — managed by `tgt config`. Edit by hand if you like." > $tmp
    echo "# Last written: "(date) >> $tmp
    echo "" >> $tmp

    for var in TGT_WORKSPACE_ROOT TGT_WORKSPACE_LAYOUT TGT_WORKSPACE_AUTOCREATE TGT_WORKSPACE_TARGET_TEMPLATE TGT_WORKSPACE_SCENARIO_TEMPLATE
        if set -q $var
            set -l escaped (string escape -- $$var)
            echo "set -gx $var "(string join " " -- $escaped) >> $tmp
        end
    end

    command mv -- $tmp $file
end
