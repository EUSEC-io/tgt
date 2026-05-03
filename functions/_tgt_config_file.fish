# Path to the persisted workspace config file. Lives under
# `_tgt_home` so $TGT_HOME redirects it for tests.
function _tgt_config_file
    echo (_tgt_home)/config.fish
end
