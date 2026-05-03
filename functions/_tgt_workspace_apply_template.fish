# Apply a template (list of entries) under a base directory.
# Entries ending in '/' are mkdir-p'd; others are touched.
# Idempotent. base_dir is assumed to already exist.
function _tgt_workspace_apply_template --argument-names base_dir
    test -z "$base_dir"; and return 1
    set -l entries $argv[2..]
    for entry in $entries
        test -z "$entry"; and continue
        if string match -q '*/' -- $entry
            mkdir -p -- "$base_dir/$entry"
            or return 1
        else
            set -l parent (dirname -- "$base_dir/$entry")
            mkdir -p -- $parent
            or return 1
            touch -- "$base_dir/$entry"
            or return 1
        end
    end
    return 0
end
