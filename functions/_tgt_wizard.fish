# Interactive setup walker for the active target. Invoked when the
# user runs `tgt edit` (or selects "edit" in the action picker).
# Each step is gum-aware (with read fallback) and Ctrl-C aborts
# cleanly at any prompt.
#
# The target schema now covers only host + hostnames. Credentials
# and AD/DC info moved to per-scenario entries — `tgt cred new`
# and `tgt dc new` respectively.
function _tgt_wizard
    set -l hosts_scenario (_tgt_active_scenario_name)
    set -l hosts_target   (_tgt_active_target_name)
    set -l ui_mode plain
    command -q gum; and not set -q TGT_TEST_MODE; and set ui_mode gum

    # ── Intro ──
    echo ""
    set_color cyan; echo "  ══════════════════════════════════════════════════════"; set_color normal
    set_color --bold cyan; echo "  tgt — interactive target setup"; set_color normal
    set_color cyan; echo "  ══════════════════════════════════════════════════════"; set_color normal
    echo ""
    echo "  Configure the active target: IP and hostnames in /etc/hosts."
    echo "  Credentials and AD/DC are per-scenario — use `tgt cred new`"
    echo "  and `tgt dc new` for those."
    echo ""
    set_color brblack
    echo "  Active scope: $hosts_scenario:$hosts_target"
    echo "  Press Ctrl-C any time to abort. UI mode: $ui_mode"
    set_color normal

    # ── 1/2 · Host ──
    _tgt_ui_section "1/2" "Host"
    echo "    Target IP / hostname (TGT)."

    set -l cur_tgt (set -q TGT && echo $TGT || echo "")
    set -l input_tgt (_tgt_ask_text "Host (TGT)" $cur_tgt)
    if test $status -ne 0
        set_color brblack; echo "  aborted."; set_color normal
        return 1
    end
    if test -z "$input_tgt"
        set_color red; echo "  ✗ Host is required."; set_color normal
        return 1
    end
    if test -n "$cur_tgt"; and test "$input_tgt" != "$cur_tgt"
        _tgt_hosts_revoke $hosts_scenario $hosts_target
    end
    _tgt_export TGT $input_tgt

    # ── 2/2 · Hostnames ──
    _tgt_ui_section "2/2" "Hostnames → /etc/hosts"
    echo "    Aliases for this target (space-separated). Tagged with"
    echo "    # tgt:$hosts_scenario:$hosts_target so removal is precise."
    echo "    Empty input keeps the current list; type '!' to clear all."

    set -l cur_hosts (set -q TGT_HOSTS && echo $TGT_HOSTS || echo "")
    set -l input_hosts (_tgt_ask_text_optional "Hostnames" $cur_hosts)
    if test $status -ne 0
        set_color brblack; echo "  aborted."; set_color normal
        return 1
    end
    if test -n "$input_hosts"
        set -l hosts_list (string split " " -- $input_hosts)
        _tgt_hosts_revoke $hosts_scenario $hosts_target
        _tgt_hosts_add $hosts_scenario $hosts_target $TGT $hosts_list
        _tgt_export TGT_HOSTS $hosts_list
        set_color green; echo "  ✓ /etc/hosts: $TGT $input_hosts"; set_color normal
    else if test -n "$cur_hosts"
        # User cleared via `!`. Drop the /etc/hosts tagged line and
        # the env list together.
        _tgt_hosts_revoke $hosts_scenario $hosts_target
        set -q TGT_HOSTS; and _tgt_unexport TGT_HOSTS
        set_color yellow; echo "  ✓ hostnames cleared"; set_color normal
    end

    # ── Persist + summary ──
    if set -q TGT_SCENARIO; and set -q TGT_ACTIVE
        if _tgt_scenario_exists $TGT_SCENARIO
            _tgt_target_save $TGT_SCENARIO $TGT_ACTIVE
        end
    end

    echo ""
    set_color cyan; echo "  ─── Summary ──────────────────────────────────────────"; set_color normal
    tgt --show
end
