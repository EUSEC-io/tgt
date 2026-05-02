function tgt --description 'Set penetration testing target environment variables'
    # ── Help ────────────────────────────────────────────────
    if test (count $argv) -ge 1; and begin; test $argv[1] = "--help"; or test $argv[1] = "-h"; end
        echo ""
        echo "  tgt — target environment manager"
        echo ""
        echo "  USAGE"
        echo "    tgt                          Interactive setup (host, port, creds, AD, hostnames)"
        echo "    tgt --show                   Show current target config + /etc/hosts + krb5"
        echo "    tgt --revoke                 Clear everything (env vars, /etc/hosts, krb5.conf)"
        echo ""
        echo "  HOSTNAMES"
        echo "    tgt --add-host <h1> [h2..]   Add hostnames to /etc/hosts for \$TGT (deduplicates)"
        echo "    tgt --rm-host  <h1> [h2..]   Remove hostnames from /etc/hosts"
        echo ""
        echo "  ACTIVE DIRECTORY"
        echo "    tgt --set-dc <DC_HOSTNAME>   Set domain controller + update krb5.conf + /etc/hosts"
        echo "    tgt ingest <U> <P> [--zip]   Run bloodhound-python (optional: --zip <col> <name>)"
        echo ""
        echo "  ENVIRONMENT VARIABLES"
        echo "    \$TGT  \$TGT_PORT  \$TGT_USERNAME  \$TGT_PASSWORD  \$TGT_AD_DOMAIN  \$TGT_DC  \$TGT_HOSTS"
        echo ""
        return 0
    end

    set -l hosts_file (_tgt_hosts_file)
    set -l krb5_file  (_tgt_krb5_file)

    # ── Revoke ──────────────────────────────────────────────
    if test (count $argv) -ge 1 && test $argv[1] = "--revoke"
        # Clean /etc/hosts
        if set -q TGT
            set -l escaped (string escape --style=regex $TGT)
            if grep -qP "^$escaped\s" $hosts_file
                _tgt_sudo sed -i "/^$escaped\s/d" $hosts_file
                echo "✓ Removed $TGT from /etc/hosts"
            end
        end

        # Clean krb5.conf
        if set -q TGT_AD_DOMAIN
            set -l realm (string upper $TGT_AD_DOMAIN)
            if grep -q "$realm" $krb5_file 2>/dev/null
                _tgt_clean_krb5 $realm
                echo "✓ Removed $realm from /etc/krb5.conf"
            end
        end

        set -q TGT            && _tgt_unexport TGT            && echo "✓ TGT unset"            || echo "- TGT was not set"
        set -q TGT_PORT       && _tgt_unexport TGT_PORT       && echo "✓ TGT_PORT unset"       || echo "- TGT_PORT was not set"
        set -q TGT_USERNAME   && _tgt_unexport TGT_USERNAME   && echo "✓ TGT_USERNAME unset"   || echo "- TGT_USERNAME was not set"
        set -q TGT_PASSWORD   && _tgt_unexport TGT_PASSWORD   && echo "✓ TGT_PASSWORD unset"   || echo "- TGT_PASSWORD was not set"
        set -q TGT_AD_DOMAIN  && _tgt_unexport TGT_AD_DOMAIN  && echo "✓ TGT_AD_DOMAIN unset"  || echo "- TGT_AD_DOMAIN was not set"
        set -q TGT_DC         && _tgt_unexport TGT_DC         && echo "✓ TGT_DC unset"         || echo "- TGT_DC was not set"
        set -q TGT_HOSTS      && _tgt_unexport TGT_HOSTS      && echo "✓ TGT_HOSTS unset"      || echo "- TGT_HOSTS was not set"
        return 0
    end

    # ── Show current state ──────────────────────────────────
    if test (count $argv) -ge 1 && test $argv[1] = "--show"
        echo ""
        echo "─────────────────────────────────"
        set -q TGT            && echo "  TGT           = $TGT"            || echo "  TGT           = (not set)"
        set -q TGT_PORT       && echo "  TGT_PORT      = $TGT_PORT"       || echo "  TGT_PORT      = (not set)"
        set -q TGT_USERNAME   && echo "  TGT_USERNAME  = $TGT_USERNAME"   || echo "  TGT_USERNAME  = (not set)"
        set -q TGT_PASSWORD   && echo "  TGT_PASSWORD  = ********"        || echo "  TGT_PASSWORD  = (not set)"
        set -q TGT_AD_DOMAIN  && echo "  TGT_AD_DOMAIN = $TGT_AD_DOMAIN" || echo "  TGT_AD_DOMAIN = (not set)"
        set -q TGT_DC         && echo "  TGT_DC        = $TGT_DC"         || echo "  TGT_DC        = (not set)"
        set -q TGT_HOSTS      && echo "  TGT_HOSTS     = $TGT_HOSTS"      || echo "  TGT_HOSTS     = (not set)"
        echo "─────────────────────────────────"
        echo ""
        if set -q TGT
            echo "  /etc/hosts:"
            grep -P "^"(string escape --style=regex $TGT)"\s" $hosts_file 2>/dev/null || echo "    (no entries)"
        end
        if set -q TGT_AD_DOMAIN
            set -l realm (string upper $TGT_AD_DOMAIN)
            echo ""
            echo "  /etc/krb5.conf:"
            grep -A2 "$realm" $krb5_file 2>/dev/null || echo "    (no entries)"
        end
        echo ""
        return 0
    end

    # ── Quick add hostnames ─────────────────────────────────
    if test (count $argv) -ge 1 && test $argv[1] = "--add-host"
        if not set -q TGT
            echo "Error: TGT not set. Run tgt first."
            return 1
        end
        if test (count $argv) -lt 2
            echo "Usage: tgt --add-host hostname1 [hostname2 ...]"
            return 1
        end
        set -l new_hosts $argv[2..]
        set -l escaped (string escape --style=regex $TGT)

        for h in $new_hosts
            set -l h_escaped (string escape --style=regex $h)
            _tgt_sudo sed -i -E "s/\s+$h_escaped(\s|\$)/\1/g" $hosts_file
            _tgt_sudo sed -i -E '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\s*$/d' $hosts_file
        end

        set -l existing_line (grep -P "^$escaped\s" $hosts_file 2>/dev/null)
        if test -n "$existing_line"
            set -l existing_hosts (string split " " -- (string replace -r "^$escaped\s+" "" $existing_line))
            for h in $new_hosts
                if not contains $h $existing_hosts
                    set -a existing_hosts $h
                end
            end
            _tgt_sudo sed -i "s/^$escaped\s.*/$TGT $existing_hosts/" $hosts_file
        else
            _tgt_sudo sh -c "echo '$TGT $new_hosts' >> $hosts_file"
        end

        _tgt_export TGT_HOSTS (grep -P "^$escaped\s" $hosts_file | string replace -r "^$escaped\s+" "")
        echo "✓ /etc/hosts: $TGT $TGT_HOSTS"
        return 0
    end

    # ── Quick remove hostnames ──────────────────────────────
    if test (count $argv) -ge 1 && test $argv[1] = "--rm-host"
        if not set -q TGT
            echo "Error: TGT not set. Run tgt first."
            return 1
        end
        if test (count $argv) -lt 2
            echo "Usage: tgt --rm-host hostname1 [hostname2 ...]"
            return 1
        end
        set -l rm_hosts $argv[2..]
        set -l escaped (string escape --style=regex $TGT)

        for h in $rm_hosts
            set -l h_escaped (string escape --style=regex $h)
            _tgt_sudo sed -i -E "s/\s+$h_escaped(\s|\$)/\1/g" $hosts_file
        end
        _tgt_sudo sed -i -E '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\s*$/d' $hosts_file

        set -l remaining (grep -P "^$escaped\s" $hosts_file 2>/dev/null | string replace -r "^$escaped\s+" "")
        if test -n "$remaining"
            _tgt_export TGT_HOSTS $remaining
            echo "✓ /etc/hosts: $TGT $TGT_HOSTS"
        else
            set -q TGT_HOSTS && _tgt_unexport TGT_HOSTS
            echo "✓ All hostnames removed for $TGT"
        end
        return 0
    end

    # ── Quick set DC ────────────────────────────────────────
    if test (count $argv) -ge 1 && test $argv[1] = "--set-dc"
        if not set -q TGT_AD_DOMAIN
            echo "Error: TGT_AD_DOMAIN not set. Run tgt with AD domain first."
            return 1
        end
        if test (count $argv) -lt 2
            echo "Usage: tgt --set-dc DC_HOSTNAME"
            return 1
        end
        _tgt_export TGT_DC $argv[2]
        _tgt_update_krb5
        tgt --add-host $TGT_DC
        return 0
    end

    # ── BloodHound CLI Ingest ───────────────────────────────
    if test (count $argv) -ge 1 && test $argv[1] = "ingest"
        if test (count $argv) -lt 3
            echo "Usage: tgt ingest <User> <Pass> [--zip [collection] [zipname]]"
            return 1
        end

        set -l bh_user $argv[2]
        set -l bh_pass $argv[3]
        set -l do_zip false
        set -l collection "all"
        set -l zip_name "bloodhound_data.zip"

        # Dynamically parse the remaining arguments
        if test (count $argv) -ge 4; and test $argv[4] = "--zip"
            set do_zip true
            if test (count $argv) -ge 5
                set collection $argv[5]
            end
            if test (count $argv) -ge 6
                set zip_name $argv[6]
                if not string match -q "*.zip" $zip_name
                    set zip_name "$zip_name.zip"
                end
            end
        end

        _tgt_run_bloodhound "$bh_user" "$bh_pass" "$collection" "$do_zip" "$zip_name"
        return $status
    end

    # ── Interactive setup ───────────────────────────────────
    echo ""
    echo "[ Target ]"

    set -l cur_tgt (set -q TGT && echo $TGT || echo "")
    if test -n "$cur_tgt"
        read -P "  Host (TGT) [$cur_tgt]: " input_tgt
    else
        read -P "  Host (TGT): " input_tgt
    end

    if test -n "$input_tgt"
        if test -n "$cur_tgt" && test "$input_tgt" != "$cur_tgt"
            set -l escaped (string escape --style=regex $cur_tgt)
            _tgt_sudo sed -i "/^$escaped\s/d" $hosts_file 2>/dev/null
        end
        _tgt_export TGT $input_tgt
    else if test -n "$cur_tgt"
        _tgt_export TGT $cur_tgt
    else
        echo "Error: TGT is required"
        return 1
    end

    set -l cur_port (set -q TGT_PORT && echo $TGT_PORT || echo "")
    if test -n "$cur_port"
        read -P "  Port (TGT_PORT) [$cur_port]: " input_port
    else
        read -P "  Port (TGT_PORT) [None]: " input_port
    end

    if test -n "$input_port"
        _tgt_export TGT_PORT $input_port
    else if test -n "$cur_port"
        _tgt_export TGT_PORT $cur_port
    end

    # ── Hostnames ───────────────────────────────────────────
    echo ""
    echo "[ Hostnames → /etc/hosts ]"

    set -l cur_hosts (set -q TGT_HOSTS && echo $TGT_HOSTS || echo "")
    if test -n "$cur_hosts"
        echo "  Current: $TGT $cur_hosts"
        read -P "  Hostnames (space-separated) [$cur_hosts]: " input_hosts
    else
        read -P "  Hostnames (space-separated, blank to skip): " input_hosts
    end

    if test -n "$input_hosts"
        set -l hosts_list (string split " " -- $input_hosts)
        set -l escaped (string escape --style=regex $TGT)
        _tgt_sudo sed -i "/^$escaped\s/d" $hosts_file 2>/dev/null
        _tgt_sudo sh -c "echo '$TGT $input_hosts' >> $hosts_file"
        _tgt_export TGT_HOSTS $input_hosts
        echo "  ✓ Added: $TGT $input_hosts"
    else if test -n "$cur_hosts"
        _tgt_export TGT_HOSTS $cur_hosts
    end

    # ── Credentials ─────────────────────────────────────────
    echo ""
    echo "[ Credentials ]"
    set -l cur_user (set -q TGT_USERNAME && echo $TGT_USERNAME || echo "")
    set -l set_creds

    if test -n "$cur_user"
        read -P "  Set credentials? (Y/n): " set_creds
    else
        read -P "  Set credentials? (y/N): " set_creds
    end

    if test "$set_creds" = y || test "$set_creds" = Y || begin; test -n "$cur_user"; and test -z "$set_creds"; end
        if test -n "$cur_user"
            read -P "  Username (TGT_USERNAME) [$cur_user]: " input_user
        else
            read -P "  Username (TGT_USERNAME): " input_user
        end

        if test -n "$input_user"
            _tgt_export TGT_USERNAME $input_user
        else if test -n "$cur_user"
            _tgt_export TGT_USERNAME $cur_user
        end

        set -l cur_pass (set -q TGT_PASSWORD && echo $TGT_PASSWORD || echo "")
        if test -n "$cur_pass"
            read -sP "  Password (TGT_PASSWORD) [********]: " input_pass
        else
            read -sP "  Password (TGT_PASSWORD): " input_pass
        end
        echo ""

        if test -n "$input_pass"
            _tgt_export TGT_PASSWORD $input_pass
        else if test -n "$cur_pass"
            _tgt_export TGT_PASSWORD $cur_pass
        end
    else
        set -q TGT_USERNAME && _tgt_unexport TGT_USERNAME
        set -q TGT_PASSWORD && _tgt_unexport TGT_PASSWORD
    end

    # ── Active Directory ────────────────────────────────────
    echo ""
    echo "[ Active Directory ]"
    set -l cur_domain (set -q TGT_AD_DOMAIN && echo $TGT_AD_DOMAIN || echo "")
    set -l is_ad

    if test -n "$cur_domain"
        read -P "  Active Directory target? (Y/n): " is_ad
    else
        read -P "  Active Directory target? (y/N): " is_ad
    end

    if test "$is_ad" = y || test "$is_ad" = Y || begin; test -n "$cur_domain"; and test -z "$is_ad"; end
        if test -n "$cur_domain"
            read -P "  Domain (TGT_AD_DOMAIN) [$cur_domain]: " input_domain
        else
            read -P "  Domain (TGT_AD_DOMAIN): " input_domain
        end

        if test -n "$input_domain"
            _tgt_export TGT_AD_DOMAIN $input_domain
        else if test -n "$cur_domain"
            _tgt_export TGT_AD_DOMAIN $cur_domain
        end

        set -l cur_dc (set -q TGT_DC && echo $TGT_DC || echo "")
        if test -n "$cur_dc"
            read -P "  DC hostname (TGT_DC) [$cur_dc]: " input_dc
        else
            read -P "  DC hostname (TGT_DC, e.g. DC01.DOMAIN.HTB): " input_dc
        end

        if test -n "$input_dc"
            _tgt_export TGT_DC $input_dc
        else if test -n "$cur_dc"
            _tgt_export TGT_DC $cur_dc
        end

        if set -q TGT_DC
            set -l escaped (string escape --style=regex $TGT)
            set -l existing (grep -P "^$escaped\s" $hosts_file 2>/dev/null)
            if test -n "$existing"
                if not string match -q "*$TGT_DC*" $existing
                    tgt --add-host $TGT_DC >/dev/null
                end
            else
                _tgt_sudo sh -c "echo '$TGT $TGT_DC' >> $hosts_file"
            end
        end

        _tgt_update_krb5
    else
        if set -q TGT_AD_DOMAIN
            set -l realm (string upper $TGT_AD_DOMAIN)
            _tgt_clean_krb5 $realm
        end
        set -q TGT_AD_DOMAIN && _tgt_unexport TGT_AD_DOMAIN
        set -q TGT_DC        && _tgt_unexport TGT_DC
    end

    # ── BloodHound Interactive Follow-Up ────────────────────
    if set -q TGT_AD_DOMAIN; and set -q TGT_USERNAME; and set -q TGT_PASSWORD
        echo ""
        echo "[ BloodHound ]"
        read -P "  Run bloodhound-python ingest now? (y/N): " run_bh
        if test "$run_bh" = y -o "$run_bh" = Y
            read -P "  Zip results? (Y/n): " do_zip_input
            set -l do_zip true
            if test "$do_zip_input" = n -o "$do_zip_input" = N
                set do_zip false
            end

            set -l zip_name "bloodhound_data.zip"
            if test "$do_zip" = true
                read -P "  Zip filename [$zip_name]: " input_zip_name
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

    # ── Summary ─────────────────────────────────────────────
    tgt --show
end
