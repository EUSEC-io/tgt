# Snapshot the current TGT_CRED_* env vars (raw fields only —
# USERNAME, PASSWORD, DOMAIN, NOTES) into a credential entry file.
#
# The "public" env vars TGT_USERNAME and TGT_PASSWORD (the ones
# pentest tools actually consume) are NOT stored separately —
# they're derived at load time from TGT_CRED_USERNAME and
# TGT_CRED_PASSWORD. TGT_CRED_NAME is derived from the file path.
function _tgt_cred_save --argument-names scenario alias
    _tgt_scenario_validate_name $scenario; or return 1
    _tgt_cred_validate_name $alias; or return 1
    _tgt_scenario_exists $scenario; or return 1

    set -l file (_tgt_cred_file $scenario $alias)
    command mkdir -p (dirname $file)
    set -l tmp (command mktemp)

    for var in TGT_CRED_USERNAME TGT_CRED_PASSWORD TGT_CRED_DOMAIN TGT_CRED_NOTES
        # Skip both unset and empty — fish's `set -q` returns true
        # for vars assigned the empty string, so without this check
        # a stray `set -gx TGT_CRED_DOMAIN ""` upstream would persist
        # an `_tgt_export TGT_CRED_DOMAIN ''` line. We want empty to
        # mean "field absent" everywhere.
        set -q $var; or continue
        test -n "$$var"; or continue
        set -l escaped (string escape -- $$var)
        echo "_tgt_export $var "(string join " " -- $escaped) >> $tmp
    end

    command mv $tmp $file
end
