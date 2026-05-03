# Load the persisted workspace config at shell startup. Migrates
# legacy universal-var storage on first run, then sources the file
# into the current shell's global scope.
_tgt_config_migrate
_tgt_config_load
