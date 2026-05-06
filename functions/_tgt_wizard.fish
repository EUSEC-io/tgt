# Interactive setup walker for the active target. Invoked when the
# user runs `tgt` with no args. Each step is gum-aware (with read
# fallback) and Ctrl-C aborts cleanly at any prompt.
function _tgt_wizard
    set -l krb5_file (_tgt_krb5_file)
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
    echo "  Configure the active target's environment: IP, hostnames"
    echo "  in /etc/hosts, and credentials."
    echo "  Each field defaults to its current value — Enter keeps it."
    echo "  AD/DC config is per-scenario now; use `tgt dc new`."
    echo ""
    set_color brblack
    echo "  Active scope: $hosts_scenario:$hosts_target"
    echo "  Press Ctrl-C any time to abort. UI mode: $ui_mode"
    set_color normal

    # ── 1/3 · Host ──
    _tgt_ui_section "1/3" "Host"
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

    # ── 2/3 · Hostnames ──
    _tgt_ui_section "2/3" "Hostnames → /etc/hosts"
    echo "    Aliases for this target (space-separated). Tagged with"
    echo "    # tgt:$hosts_scenario:$hosts_target so removal is precise."

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
        # User confirmed-cleared the hostnames. Drop the /etc/hosts
        # tagged line and the env list together.
        _tgt_hosts_revoke $hosts_scenario $hosts_target
        set -q TGT_HOSTS; and _tgt_unexport TGT_HOSTS
        set_color yellow; echo "  ✓ hostnames cleared"; set_color normal
    end

    # ── 3/3 · Credentials ──
    _tgt_ui_section "3/3" "Credentials"
    echo "    Username + password for this target. Skip if you don't"
    echo "    have creds yet."

    set -l cur_user (set -q TGT_USERNAME && echo $TGT_USERNAME || echo "")
    set -l default_yn n
    test -n "$cur_user"; and set default_yn y

    set -l set_creds (_tgt_ask_confirm "Set credentials?" $default_yn)
    if test $status -ne 0
        set_color brblack; echo "  aborted."; set_color normal
        return 1
    end
    if test "$set_creds" = yes
        set -l input_user (_tgt_ask_text_optional "Username (TGT_USERNAME)" $cur_user)
        if test $status -ne 0
            set_color brblack; echo "  aborted."; set_color normal
            return 1
        end
        if test -n "$input_user"
            _tgt_export TGT_USERNAME $input_user
        else if test -n "$cur_user"
            # User confirmed-cleared.
            _tgt_unexport TGT_USERNAME
        end

        set -l has_pass no
        set -q TGT_PASSWORD; and set has_pass yes
        set -l input_pass (_tgt_ask_password "Password (TGT_PASSWORD)" $has_pass)
        if test $status -ne 0
            set_color brblack; echo "  aborted."; set_color normal
            return 1
        end
        switch $input_pass
            case "<KEEP>"
                # Default path when has_current=yes and user
                # confirmed "no" to clear — nothing to do.
            case ""
                # Either has_current=no (just empty input, skip) or
                # has_current=yes and user confirmed clear. Either way,
                # ensure no password is set.
                set -q TGT_PASSWORD; and _tgt_unexport TGT_PASSWORD
            case '*'
                _tgt_export TGT_PASSWORD $input_pass
        end
    else
        set -q TGT_USERNAME; and _tgt_unexport TGT_USERNAME
        set -q TGT_PASSWORD; and _tgt_unexport TGT_PASSWORD
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
