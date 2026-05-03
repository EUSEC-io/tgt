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
    echo "  Configure the active target's environment: IP / port,"
    echo "  hostnames in /etc/hosts, credentials, AD domain + DC."
    echo "  Each field defaults to its current value — Enter keeps it."
    echo ""
    set_color brblack
    echo "  Active scope: $hosts_scenario:$hosts_target"
    echo "  Press Ctrl-C any time to abort. UI mode: $ui_mode"
    set_color normal

    # ── 1/5 · Host & port ──
    _tgt_ui_section "1/5" "Host & port"
    echo "    Target IP / hostname (TGT) and optional port (TGT_PORT)."

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

    set -l cur_port (set -q TGT_PORT && echo $TGT_PORT || echo "")
    set -l input_port (_tgt_ask_text "Port (TGT_PORT)" $cur_port)
    if test $status -ne 0
        set_color brblack; echo "  aborted."; set_color normal
        return 1
    end
    if test -n "$input_port"
        _tgt_export TGT_PORT $input_port
    end

    # ── 2/5 · Hostnames ──
    _tgt_ui_section "2/5" "Hostnames → /etc/hosts"
    echo "    Aliases for this target (space-separated). Tagged with"
    echo "    # tgt:$hosts_scenario:$hosts_target so removal is precise."

    set -l cur_hosts (set -q TGT_HOSTS && echo $TGT_HOSTS || echo "")
    set -l input_hosts (_tgt_ask_text "Hostnames" $cur_hosts)
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
    end

    # ── 3/5 · Credentials ──
    _tgt_ui_section "3/5" "Credentials"
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
        set -l input_user (_tgt_ask_text "Username (TGT_USERNAME)" $cur_user)
        if test $status -ne 0
            set_color brblack; echo "  aborted."; set_color normal
            return 1
        end
        if test -n "$input_user"
            _tgt_export TGT_USERNAME $input_user
        end

        set -l has_pass no
        set -q TGT_PASSWORD; and set has_pass yes
        set -l input_pass (_tgt_ask_password "Password (TGT_PASSWORD)" $has_pass)
        if test $status -ne 0
            set_color brblack; echo "  aborted."; set_color normal
            return 1
        end
        if test -n "$input_pass"
            _tgt_export TGT_PASSWORD $input_pass
        end
    else
        set -q TGT_USERNAME; and _tgt_unexport TGT_USERNAME
        set -q TGT_PASSWORD; and _tgt_unexport TGT_PASSWORD
    end

    # ── 4/5 · Active Directory ──
    _tgt_ui_section "4/5" "Active Directory"
    echo "    AD domain (TGT_AD_DOMAIN) and DC hostname (TGT_DC)."
    echo "    Setting these wires up /etc/krb5.conf realms automatically."

    set -l cur_domain (set -q TGT_AD_DOMAIN && echo $TGT_AD_DOMAIN || echo "")
    set -l ad_default n
    test -n "$cur_domain"; and set ad_default y

    set -l is_ad (_tgt_ask_confirm "Active Directory target?" $ad_default)
    if test $status -ne 0
        set_color brblack; echo "  aborted."; set_color normal
        return 1
    end
    if test "$is_ad" = yes
        set -l input_domain (_tgt_ask_text "Domain (TGT_AD_DOMAIN)" $cur_domain)
        if test $status -ne 0
            set_color brblack; echo "  aborted."; set_color normal
            return 1
        end
        if test -n "$input_domain"
            _tgt_export TGT_AD_DOMAIN $input_domain
        end

        set -l cur_dc (set -q TGT_DC && echo $TGT_DC || echo "")
        set -l input_dc (_tgt_ask_text "DC hostname (e.g. DC01.DOMAIN.HTB)" $cur_dc)
        if test $status -ne 0
            set_color brblack; echo "  aborted."; set_color normal
            return 1
        end
        if test -n "$input_dc"
            _tgt_export TGT_DC $input_dc
        end

        if set -q TGT_DC
            _tgt_hosts_add $hosts_scenario $hosts_target $TGT $TGT_DC
        end

        _tgt_update_krb5
    else
        if set -q TGT_AD_DOMAIN
            set -l realm (string upper $TGT_AD_DOMAIN)
            _tgt_clean_krb5 $realm
        end
        set -q TGT_AD_DOMAIN; and _tgt_unexport TGT_AD_DOMAIN
        set -q TGT_DC; and _tgt_unexport TGT_DC
    end

    # ── 5/5 · BloodHound (only if AD + creds set) ──
    if set -q TGT_AD_DOMAIN; and set -q TGT_USERNAME; and set -q TGT_PASSWORD
        _tgt_ui_section "5/5" "BloodHound ingest"
        echo "    AD + creds are set — run bloodhound-python now?"

        set -l run_bh (_tgt_ask_confirm "Run bloodhound-python ingest?" n)
        if test $status -ne 0
            set_color brblack; echo "  aborted."; set_color normal
            return 1
        end
        if test "$run_bh" = yes
            set -l do_zip_ans (_tgt_ask_confirm "Zip the results?" y)
            if test $status -ne 0
                set_color brblack; echo "  aborted."; set_color normal
                return 1
            end
            set -l do_zip true
            test "$do_zip_ans" = no; and set do_zip false

            set -l zip_name "bloodhound_data.zip"
            if test "$do_zip" = true
                set -l input_zip_name (_tgt_ask_text "Zip filename" $zip_name)
                if test $status -ne 0
                    set_color brblack; echo "  aborted."; set_color normal
                    return 1
                end
                if test -n "$input_zip_name"
                    set zip_name $input_zip_name
                    if not string match -q "*.zip" $zip_name
                        set zip_name "$zip_name.zip"
                    end
                end
            end

            echo ""
            _tgt_run_bloodhound "$TGT_USERNAME" "$TGT_PASSWORD" "all" "$do_zip" "$zip_name"
        end
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
