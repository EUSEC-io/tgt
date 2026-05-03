# Source the persisted workspace config file if it exists. No-op
# otherwise. The file uses `set -gx` so its values land in the
# current shell's global scope; env vars set before this call still
# win because the loader writes globals (env > local globals?
# Actually `set -gx` overwrites, but the convention is the file is
# the canonical source). Override at the call site by re-exporting
# the var after this runs.
function _tgt_config_load
    set -l file (_tgt_config_file)
    test -f $file; or return 0
    source $file
end
