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
        echo ""
        echo "  ENVIRONMENT VARIABLES"
        echo "    \$TGT  \$TGT_PORT  \$TGT_USERNAME  \$TGT_PASSWORD  \$TGT_AD_DOMAIN  \$TGT_DC  \$TGT_HOSTS"
        echo ""
        echo "  EXAMPLES"
        echo "    tgt                                        # set up a new target"
        echo "    tgt --add-host app.htb admin.app.htb       # found new vhosts"
        echo "    tgt --set-dc DC01.corp.htb                 # found the DC"
        echo "    tgt --rm-host old.app.htb                  # remove stale hostname"
        echo "    nmap -sV \$TGT                              # use in commands"
        echo "    tgt --revoke                               # done, clean up"
        echo ""
        return 0
    end

    # ── Revoke ──────────────────────────────────────────────
    if test (count $argv) -ge 1 && test $argv[1] = "--revoke"
        # Clean /etc/hosts
        if set -q TGT
            set -l escaped (string escape --style=regex $TGT)
            if grep -qP "^$escaped\s" /etc/hosts
                sudo sed -i "/^$escaped\s/d" /etc/hosts
                echo "✓ Removed $TGT from /etc/hosts"
            end
        end

        # Clean krb5.conf
        if set -q TGT_AD_DOMAIN
            set -l realm (string upper $TGT_AD_DOMAIN)
            if grep -q "$realm" /etc/krb5.conf 2>/dev/null
                sudo python3 -c '
import re, sys
realm = sys.argv[1]
with open("/etc/krb5.conf", "r") as f:
    content = f.read()
content = re.sub(r"^\s*default_realm\s*=\s*" + re.escape(realm) + r"\s*$", "\tdefault_realm = ATHENA.MIT.EDU", content, flags=re.MULTILINE)
content = re.sub(r"\s*" + re.escape(realm) + r"\s*=\s*\{[^}]*\}\n?", "", content)
with open("/etc/krb5.conf", "w") as f:
    f.write(content)
' "$realm" 2>/dev/null
                echo "✓ Removed $realm from /etc/krb5.conf"
            end
        end

        set -q TGT           && set -Ue TGT           && echo "✓ TGT unset"           || echo "- TGT was not set"
        set -q TGT_PORT      && set -Ue TGT_PORT      && echo "✓ TGT_PORT unset"      || echo "- TGT_PORT was not set"
        set -q TGT_USERNAME  && set -Ue TGT_USERNAME   && echo "✓ TGT_USERNAME unset"  || echo "- TGT_USERNAME was not set"
        set -q TGT_PASSWORD  && set -Ue TGT_PASSWORD   && echo "✓ TGT_PASSWORD unset"  || echo "- TGT_PASSWORD was not set"
        set -q TGT_AD_DOMAIN && set -Ue TGT_AD_DOMAIN  && echo "✓ TGT_AD_DOMAIN unset" || echo "- TGT_AD_DOMAIN was not set"
        set -q TGT_DC        && set -Ue TGT_DC         && echo "✓ TGT_DC unset"        || echo "- TGT_DC was not set"
        set -q TGT_HOSTS     && set -Ue TGT_HOSTS      && echo "✓ TGT_HOSTS unset"     || echo "- TGT_HOSTS was not set"
        return 0
    end

    # ── Show current state ──────────────────────────────────
    if test (count $argv) -ge 1 && test $argv[1] = "--show"
        echo ""
        echo "─────────────────────────────────"
        set -q TGT           && echo "  TGT           = $TGT"           || echo "  TGT           = (not set)"
        set -q TGT_PORT      && echo "  TGT_PORT      = $TGT_PORT"      || echo "  TGT_PORT      = (not set)"
        set -q TGT_USERNAME  && echo "  TGT_USERNAME  = $TGT_USERNAME"  || echo "  TGT_USERNAME  = (not set)"
        set -q TGT_PASSWORD  && echo "  TGT_PASSWORD  = ********"       || echo "  TGT_PASSWORD  = (not set)"
        set -q TGT_AD_DOMAIN && echo "  TGT_AD_DOMAIN = $TGT_AD_DOMAIN" || echo "  TGT_AD_DOMAIN = (not set)"
        set -q TGT_DC        && echo "  TGT_DC        = $TGT_DC"        || echo "  TGT_DC        = (not set)"
        set -q TGT_HOSTS     && echo "  TGT_HOSTS     = $TGT_HOSTS"     || echo "  TGT_HOSTS     = (not set)"
        echo "─────────────────────────────────"
        echo ""
        if set -q TGT
            echo "  /etc/hosts:"
            grep -P "^"(string escape --style=regex $TGT)"\s" /etc/hosts 2>/dev/null || echo "    (no entries)"
        end
        if set -q TGT_AD_DOMAIN
            set -l realm (string upper $TGT_AD_DOMAIN)
            echo ""
            echo "  /etc/krb5.conf:"
            grep -A2 "$realm" /etc/krb5.conf 2>/dev/null || echo "    (no entries)"
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

        # Remove these hostnames from ANY other IP lines first (dedup)
        for h in $new_hosts
            set -l h_escaped (string escape --style=regex $h)
            sudo sed -i -E "s/\s+$h_escaped(\s|\$)/\1/g" /etc/hosts
            # Clean up lines that now have only an IP and no hostnames
            sudo sed -i -E '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\s*$/d' /etc/hosts
        end

        # Get existing hostnames for this IP
        set -l existing_line (grep -P "^$escaped\s" /etc/hosts 2>/dev/null)
        if test -n "$existing_line"
            set -l existing_hosts (string split " " -- (string replace -r "^$escaped\s+" "" $existing_line))
            for h in $new_hosts
                if not contains $h $existing_hosts
                    set -a existing_hosts $h
                end
            end
            sudo sed -i "s/^$escaped\s.*/$TGT $existing_hosts/" /etc/hosts
        else
            sudo sh -c "echo '$TGT $new_hosts' >> /etc/hosts"
        end

        set -Ux TGT_HOSTS (grep -P "^$escaped\s" /etc/hosts | string replace -r "^$escaped\s+" "")
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
            sudo sed -i -E "s/\s+$h_escaped(\s|\$)/\1/g" /etc/hosts
        end
        # Clean up line if only IP remains
        sudo sed -i -E '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\s*$/d' /etc/hosts

        set -l remaining (grep -P "^$escaped\s" /etc/hosts 2>/dev/null | string replace -r "^$escaped\s+" "")
        if test -n "$remaining"
            set -Ux TGT_HOSTS $remaining
            echo "✓ /etc/hosts: $TGT $TGT_HOSTS"
        else
            set -q TGT_HOSTS && set -Ue TGT_HOSTS
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
        set -Ux TGT_DC $argv[2]
        _tgt_update_krb5
        # Also add DC hostname to /etc/hosts
        tgt --add-host $TGT_DC
        return 0
    end

    # ── Interactive setup ───────────────────────────────────
    echo ""
    echo "[ Target ]"

    # TGT — clean old /etc/hosts entry if IP changes
    set -l cur_tgt (set -q TGT && echo $TGT || echo "")
    if test -n "$cur_tgt"
        read -P "  Host (TGT) [$cur_tgt]: " input_tgt
    else
        read -P "  Host (TGT): " input_tgt
    end

    if test -n "$input_tgt"
        # If IP changed, clean old entry
        if test -n "$cur_tgt" && test "$input_tgt" != "$cur_tgt"
            set -l escaped (string escape --style=regex $cur_tgt)
            sudo sed -i "/^$escaped\s/d" /etc/hosts 2>/dev/null
        end
        set -Ux TGT $input_tgt
    else if test -n "$cur_tgt"
        set -Ux TGT $cur_tgt
    else
        echo "Error: TGT is required"
        return 1
    end

    # TGT_PORT
    set -l cur_port (set -q TGT_PORT && echo $TGT_PORT || echo "")
    if test -n "$cur_port"
        read -P "  Port (TGT_PORT) [$cur_port]: " input_port
    else
        read -P "  Port (TGT_PORT) [None]: " input_port
    end

    if test -n "$input_port"
        set -Ux TGT_PORT $input_port
    else if test -n "$cur_port"
        set -Ux TGT_PORT $cur_port
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
        sudo sed -i "/^$escaped\s/d" /etc/hosts 2>/dev/null
        sudo sh -c "echo '$TGT $input_hosts' >> /etc/hosts"
        set -Ux TGT_HOSTS $input_hosts
        echo "  ✓ Added: $TGT $input_hosts"
    else if test -n "$cur_hosts"
        set -Ux TGT_HOSTS $cur_hosts
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
            set -Ux TGT_USERNAME $input_user
        else if test -n "$cur_user"
            set -Ux TGT_USERNAME $cur_user
        end

        set -l cur_pass (set -q TGT_PASSWORD && echo $TGT_PASSWORD || echo "")
        if test -n "$cur_pass"
            read -sP "  Password (TGT_PASSWORD) [********]: " input_pass
        else
            read -sP "  Password (TGT_PASSWORD): " input_pass
        end
        echo ""

        if test -n "$input_pass"
            set -Ux TGT_PASSWORD $input_pass
        else if test -n "$cur_pass"
            set -Ux TGT_PASSWORD $cur_pass
        end
    else
        set -q TGT_USERNAME && set -Ue TGT_USERNAME
        set -q TGT_PASSWORD && set -Ue TGT_PASSWORD
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
        # Domain
        if test -n "$cur_domain"
            read -P "  Domain (TGT_AD_DOMAIN) [$cur_domain]: " input_domain
        else
            read -P "  Domain (TGT_AD_DOMAIN): " input_domain
        end

        if test -n "$input_domain"
            set -Ux TGT_AD_DOMAIN $input_domain
        else if test -n "$cur_domain"
            set -Ux TGT_AD_DOMAIN $cur_domain
        end

        # DC hostname
        set -l cur_dc (set -q TGT_DC && echo $TGT_DC || echo "")
        if test -n "$cur_dc"
            read -P "  DC hostname (TGT_DC) [$cur_dc]: " input_dc
        else
            read -P "  DC hostname (TGT_DC, e.g. DC01.DOMAIN.HTB): " input_dc
        end

        if test -n "$input_dc"
            set -Ux TGT_DC $input_dc
        else if test -n "$cur_dc"
            set -Ux TGT_DC $cur_dc
        end

        # Add DC to /etc/hosts if set and not already there
        if set -q TGT_DC
            set -l escaped (string escape --style=regex $TGT)
            set -l existing (grep -P "^$escaped\s" /etc/hosts 2>/dev/null)
            if test -n "$existing"
                if not string match -q "*$TGT_DC*" $existing
                    tgt --add-host $TGT_DC >/dev/null
                end
            else
                sudo sh -c "echo '$TGT $TGT_DC' >> /etc/hosts"
            end
        end

        # Update krb5.conf
        _tgt_update_krb5
    else
        # Clean AD if previously set
        if set -q TGT_AD_DOMAIN
            set -l realm (string upper $TGT_AD_DOMAIN)
            _tgt_clean_krb5 $realm
        end
        set -q TGT_AD_DOMAIN && set -Ue TGT_AD_DOMAIN
        set -q TGT_DC        && set -Ue TGT_DC
    end

    # ── Summary ─────────────────────────────────────────────
    tgt --show
end


# ── Helper: update /etc/krb5.conf ──────────────────────────
function _tgt_update_krb5
    if not set -q TGT_AD_DOMAIN
        return
    end

    set -l realm (string upper $TGT_AD_DOMAIN)
    set -l kdc_host ""

    if set -q TGT_DC
        set kdc_host $TGT_DC
    else if set -q TGT
        set kdc_host $TGT
    else
        return
    end

    # Clean any previous entry for this realm
    _tgt_clean_krb5 $realm

    # Set default_realm
    sudo sed -i "s/^\s*default_realm\s*=.*/\tdefault_realm = $realm/" /etc/krb5.conf

    # Add realm block before any existing realm or at end of [realms]
    set -l realm_block "\n    $realm = {\n        kdc = $kdc_host\n    }"

    if grep -q "^\[realms\]" /etc/krb5.conf
        sudo sed -i "/^\[realms\]/a\\    $realm = {\n        kdc = $kdc_host\n    }" /etc/krb5.conf
    else
        sudo sh -c "printf '\n[realms]\n    $realm = {\n        kdc = $kdc_host\n    }\n' >> /etc/krb5.conf"
    end

    echo "  ✓ krb5.conf: default_realm = $realm, kdc = $kdc_host"
end


# ── Helper: remove realm from krb5.conf ─────────────────────
function _tgt_clean_krb5
    set -l realm $argv[1]
    if grep -q "$realm" /etc/krb5.conf 2>/dev/null
        sudo python3 -c '
import re, sys
realm = sys.argv[1]
with open("/etc/krb5.conf", "r") as f:
    content = f.read()
content = re.sub(r"\n?\s*" + re.escape(realm) + r"\s*=\s*\{[^}]*\}", "", content)
with open("/etc/krb5.conf", "w") as f:
    f.write(content)
' "$realm"
    end
end
