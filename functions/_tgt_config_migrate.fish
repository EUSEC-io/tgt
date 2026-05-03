# One-shot upgrade path: if the user has workspace settings as
# universal variables (the old storage) and no config file yet,
# write the current values into the file and erase the universals
# so the file becomes the source of truth.
function _tgt_config_migrate
    set -l file (_tgt_config_file)
    test -f $file; and return 0

    set -l have_any 0
    for var in TGT_WORKSPACE_ROOT TGT_WORKSPACE_LAYOUT TGT_WORKSPACE_AUTOCREATE TGT_WORKSPACE_TARGET_TEMPLATE TGT_WORKSPACE_SCENARIO_TEMPLATE
        if set -q $var
            set have_any 1
            break
        end
    end
    test $have_any -eq 0; and return 0

    _tgt_config_save
    for var in TGT_WORKSPACE_ROOT TGT_WORKSPACE_LAYOUT TGT_WORKSPACE_AUTOCREATE TGT_WORKSPACE_TARGET_TEMPLATE TGT_WORKSPACE_SCENARIO_TEMPLATE
        set -qU $var; and set -eU $var
    end

    set_color brblack
    echo "tgt: migrated workspace config from universals to $file" >&2
    set_color normal
end
