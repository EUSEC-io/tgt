# Dispatch for `tgt hosts <verb>`. Called from tgt.fish.
function _tgt_hosts_cli
    set -l verb ""
    test (count $argv) -ge 1; and set verb $argv[1]

    switch "$verb"
        case "" edit
            _tgt_hosts_edit
            return $status
        case -h --help
            echo ""
            echo "  tgt hosts — edit /etc/hosts entries for the active target"
            echo ""
            echo "    tgt hosts                Open the multi-line editor (default)"
            echo "    tgt hosts edit           Same as above"
            echo ""
            echo "  Each line is one hostname; blanks and comments are skipped."
            echo "  Saving rewrites only the lines tagged for the active scope"
            echo "  (# tgt:<scenario>:<target>) — your manual entries are safe."
            echo ""
            return 0
        case '*'
            echo "tgt hosts: unknown verb '$verb'" >&2
            echo "Try: tgt hosts --help" >&2
            return 1
    end
end

function _tgt_hosts_edit
    if not set -q TGT
        echo "tgt hosts: no active target (TGT unset). Run `tgt` or `tgt switch <alias>` first." >&2
        return 1
    end

    set -l scenario (_tgt_active_scenario_name)
    set -l target (_tgt_active_target_name)
    set -l current
    set -q TGT_HOSTS; and set current $TGT_HOSTS

    set_color cyan; echo "  Editing hostnames for $scenario:$target ($TGT)"; set_color normal
    set -l new_hosts (_tgt_ask_multiline "Hostnames (one per line)" $current)
    if test $status -ne 0
        set_color brblack; echo "  cancelled."; set_color normal
        return 1
    end

    _tgt_hosts_revoke $scenario $target
    if test (count $new_hosts) -gt 0
        _tgt_hosts_add $scenario $target $TGT $new_hosts
        _tgt_export TGT_HOSTS $new_hosts
        set_color green; echo "  ✓ /etc/hosts: $TGT "(string join " " -- $new_hosts); set_color normal
    else
        set -q TGT_HOSTS; and _tgt_unexport TGT_HOSTS
        set_color green; echo "  ✓ all hostnames removed for $TGT"; set_color normal
    end
    _tgt_maybe_save_active
    return 0
end
