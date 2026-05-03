# Atomically replace the krb5 config file with content read from stdin.
# Production: writes a temp file then `sudo install`s it over the real
# path with root:root ownership. Test mode: just `mv`s into place.
function _tgt_krb5_write
    set -l krb5 (_tgt_krb5_file)
    set -l tmp (command mktemp)
    command cat > $tmp
    if set -q TGT_TEST_MODE; or set -q TGT_NO_SUDO
        command mv $tmp $krb5
    else
        _tgt_sudo_notice
        command sudo install -m 644 -o root -g root $tmp $krb5
        command rm -f $tmp
    end
end
