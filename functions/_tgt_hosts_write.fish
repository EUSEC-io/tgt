# Atomically replace the hosts file with content read from stdin.
# Production: writes to a temp file then `sudo install`s over the real
# path with root:root ownership. Test mode: just `mv`s into place.
function _tgt_hosts_write
    set -l hosts_file (_tgt_hosts_file)
    set -l tmp (command mktemp)
    command cat > $tmp
    if set -q TGT_TEST_MODE; or set -q TGT_NO_SUDO
        command mv $tmp $hosts_file
    else
        _tgt_sudo_notice
        # When invoked from tgt-web, SUDO_ASKPASS points at a
        # graphical helper (zenity/kdialog/ssh-askpass); `sudo -A`
        # consults it instead of blocking on a non-existent TTY,
        # and we pass `-p $TGT_SUDO_REASON` so the dialog says
        # *which* tgt action wants /etc/hosts modified. The CLI
        # path stays untouched — sudo's default TTY prompt is
        # what shell users expect, no -p override there.
        if set -q SUDO_ASKPASS
            set -l prompt 'tgt: update /etc/hosts'
            set -q TGT_SUDO_REASON; and test -n "$TGT_SUDO_REASON"
                and set prompt $TGT_SUDO_REASON
            command sudo -A -p $prompt install -m 644 -o root -g root $tmp $hosts_file
        else
            command sudo install -m 644 -o root -g root $tmp $hosts_file
        end
        command rm -f $tmp
    end
end
