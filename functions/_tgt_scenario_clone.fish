# Copy a scenario's registry state — targets, port records, DC
# entries, and the active-DC marker — into a new scenario. The
# workspace folder is intentionally NOT copied: cloning is for
# carrying configuration forward, not engagement output.
#
# Errors when src doesn't exist, new name is invalid, or new name
# already exists. Doesn't activate the clone.
function _tgt_scenario_clone --argument-names src new
    if not _tgt_scenario_exists $src
        echo "_tgt_scenario_clone: source scenario '$src' does not exist" >&2
        return 1
    end
    if not _tgt_scenario_validate_name $new
        echo "_tgt_scenario_clone: invalid scenario name '$new'" >&2
        return 1
    end
    if _tgt_scenario_exists $new
        echo "_tgt_scenario_clone: scenario '$new' already exists" >&2
        return 1
    end

    set -l src_dir (_tgt_scenario_dir $src)
    set -l new_dir (_tgt_scenario_dir $new)

    command mkdir -p $new_dir/targets

    # targets/ — both <alias>.fish (env vars) and <alias>.ports
    # (port records) get copied wholesale.
    if test -d $src_dir/targets
        for f in $src_dir/targets/*
            test -e $f; or continue
            command cp -- $f $new_dir/targets/(basename $f)
        end
    end

    # dcs/ — same wholesale copy. Active marker comes along too so
    # the clone starts with the same DC active.
    if test -d $src_dir/dcs
        command mkdir -p $new_dir/dcs
        for f in $src_dir/dcs/*
            test -e $f; or continue
            command cp -- $f $new_dir/dcs/(basename $f)
        end
    end

    if test -f $src_dir/.active-dc
        command cp -- $src_dir/.active-dc $new_dir/.active-dc
    end

    # creds/ — same as dcs/. Credential entries are config (which
    # user identities to pivot between), not engagement output, so
    # they belong on a clone.
    if test -d $src_dir/creds
        command mkdir -p $new_dir/creds
        for f in $src_dir/creds/*
            test -e $f; or continue
            command cp -- $f $new_dir/creds/(basename $f)
        end
    end

    if test -f $src_dir/.active-cred
        command cp -- $src_dir/.active-cred $new_dir/.active-cred
    end

    # `.archived` is intentionally left behind — clones start active.
end
