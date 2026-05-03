# Print a one-time-per-`tgt`-invocation note explaining why sudo is
# about to prompt. Suppressed in test mode and after the first call
# in the current invocation (deduped via $_tgt_sudo_announced, which
# tgt.fish clears on entry).
function _tgt_sudo_notice
    set -q TGT_TEST_MODE; and return 0
    set -q _tgt_sudo_announced; and return 0
    set -g _tgt_sudo_announced 1
    set_color brblack
    echo "  ℹ sudo required: tgt is about to modify a root-owned system file" >&2
    echo "    (/etc/hosts or /etc/krb5.conf — both rewritten atomically via `install`)." >&2
    set_color normal
end
