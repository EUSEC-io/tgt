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
        # When invoked from tgt-web, SUDO_ASKPASS points at a
        # graphical helper (zenity/kdialog/ssh-askpass); `sudo -A`
        # consults it instead of blocking on a non-existent TTY.
        if set -q SUDO_ASKPASS
            command sudo -A install -m 644 -o root -g root $tmp $krb5
        else
            command sudo install -m 644 -o root -g root $tmp $krb5
        end
        command rm -f $tmp
    end
end
