function tgt --description 'Set penetration testing target environment variables'
    set -e _tgt_sudo_announced
    _tgt_maybe_migrate

    # ── Version ─────────────────────────────────────────────
    # Plain-text version string, matched against tgt-web's own
    # version at startup so a mismatched web/CLI pair is flagged
    # in the UI banner. Bump in lock-step with tgt-web's
    # __version__.
    if test (count $argv) -ge 1; and begin; test $argv[1] = "--version"; or test $argv[1] = "-v"; end
        echo "1.1.1"
        return 0
    end

    # ── Drift contract: list every mutating verb ────────────
    # Consumed by tgt-web's `tests/test_drift.py`: every entry
    # must have a matching key in `tgt_web/actions.py::ACTIONS`.
    # Add a row here whenever a write-side verb lands in fish,
    # then mirror it on the web side. Pure listing — no state
    # changes, safe to call from CI.
    if test (count $argv) -ge 1; and test $argv[1] = "--list-mutating-verbs"
        if test (count $argv) -ge 2; and test $argv[2] = "--json"
            echo '['
            echo '  {"action": "scenario_new",       "argv": ["scenario", "new", "<name>"]},'
            echo '  {"action": "scenario_clone",     "argv": ["scenario", "clone", "<src>", "<new>"]},'
            echo '  {"action": "scenario_rename",    "argv": ["scenario", "rename", "<old>", "<new>"]},'
            echo '  {"action": "scenario_switch",    "argv": ["scenario", "switch", "<name>"]},'
            echo '  {"action": "scenario_unload",    "argv": ["scenario", "unload"]},'
            echo '  {"action": "scenario_archive",   "argv": ["scenario", "archive", "<name>"]},'
            echo '  {"action": "scenario_unarchive", "argv": ["scenario", "unarchive", "<name>"]},'
            echo '  {"action": "scenario_rm",        "argv": ["scenario", "rm", "<name>", "[--purge-workspace]"]},'
            echo '  {"action": "target_new",         "argv": ["new", "<alias>", "[--host]", "[--hosts]"]},'
            echo '  {"action": "target_switch",      "argv": ["switch", "<alias>"]},'
            echo '  {"action": "target_edit",        "argv": ["edit", "<alias>", "[--host]", "[--hosts]"]},'
            echo '  {"action": "target_revoke",      "argv": ["revoke"]},'
            echo '  {"action": "target_rm",          "argv": ["rm", "<alias>", "[--purge-workspace]"]},'
            echo '  {"action": "cred_new",           "argv": ["cred", "new", "<alias>", "--username", "<u>", "[--password]", "[--domain]", "[--notes]"]},'
            echo '  {"action": "cred_edit",          "argv": ["cred", "edit", "<alias>", "[--username]", "[--password]", "[--domain]", "[--notes]"]},'
            echo '  {"action": "cred_rename",        "argv": ["cred", "rename", "<old>", "<new>"]},'
            echo '  {"action": "cred_rm",            "argv": ["cred", "rm", "<alias>"]},'
            echo '  {"action": "cred_switch",        "argv": ["cred", "switch", "<alias>"]},'
            echo '  {"action": "cred_unset",         "argv": ["cred", "unset"]},'
            echo '  {"action": "dc_new",             "argv": ["dc", "new", "<alias>", "[--domain]", "[--realm]", "[--kdc-host]", "[--kdc-ip]", "[--admin-host]", "[--admin-ip]"]},'
            echo '  {"action": "dc_edit",            "argv": ["dc", "edit", "<alias>", "[--domain]", "[--realm]", "[--kdc-host]", "[--kdc-ip]", "[--admin-host]", "[--admin-ip]"]},'
            echo '  {"action": "dc_switch",          "argv": ["dc", "switch", "<alias>"]},'
            echo '  {"action": "dc_unset",           "argv": ["dc", "unset"]},'
            echo '  {"action": "dc_rm",              "argv": ["dc", "rm", "<alias>"]},'
            echo '  {"action": "ports_add",          "argv": ["ports", "add", "--target", "<t>", "<port>[/<proto>]", "[service]", "[comment]"]},'
            echo '  {"action": "ports_rm",           "argv": ["ports", "rm", "--target", "<t>", "<port>[/<proto>]"]},'
            echo '  {"action": "ports_clear",        "argv": ["ports", "clear", "--target", "<t>"]},'
            echo '  {"action": "ports_comment",      "argv": ["ports", "comment", "--target", "<t>", "<port>[/<proto>]", "<text>"]},'
            echo '  {"action": "ports_service",      "argv": ["ports", "service", "--target", "<t>", "<port>[/<proto>]", "<name>"]}'
            echo ']'
            return 0
        end
        echo "Usage: tgt --list-mutating-verbs --json" >&2
        return 1
    end

    # ── Help ────────────────────────────────────────────────
    if test (count $argv) -ge 1; and begin; test $argv[1] = "--help"; or test $argv[1] = "-h"; end
        echo ""
        echo "  tgt — target environment manager"
        echo ""
        echo "  USAGE"
        echo "    tgt                          Interactive action picker (gum + TTY)"
        echo "    tgt show                     Show current target + active cred + active DC + /etc/hosts + krb5"
        echo "    tgt revoke                   Clear target runtime (TGT/PORT/HOSTS); creds + DC survive"
        echo "    (--show / --revoke also work for backward compat.)"
        echo ""
        echo "  HOSTNAMES"
        echo "    tgt --add-host <h1> [h2..]   Add hostnames to /etc/hosts for \$TGT (deduplicates)"
        echo "    tgt --rm-host  <h1> [h2..]   Remove hostnames from /etc/hosts"
        echo ""
        echo "  PORTS"
        echo "    tgt ports                    Per-target port records: list / pick / nmap import"
        echo ""
        echo "  ACTIVE DIRECTORY"
        echo "    tgt dc                       Per-scenario DC entries: new / switch / list / rm"
        echo "    tgt cred                     Per-scenario credentials: new / switch / list / rm"
        echo ""
        echo "  SCENARIOS & TARGETS"
        echo "    tgt scenario                 Pick an action interactively (or --help for verbs)"
        echo "    tgt new [alias] [--no-edit]  Create a target + drop into the wizard (--no-edit skips it)"
        echo "    tgt switch [alias]           Load a saved target's settings"
        echo "    tgt edit [alias]             Switch (if needed) + run the wizard for a target"
        echo "    tgt rename [<old>] <new>     Rename a target (or the active one); retags /etc/hosts"
        echo "    tgt list                     List targets in the active scenario"
        echo "    tgt rm <alias>               Drop a target + its /etc/hosts entries"
        echo "    tgt hosts                    Multi-line editor for active target's hostnames"
        echo ""
        echo "  PROMPT"
        echo "    tgt prompt install           Wire tgt_prompt into your fish prompt"
        echo "                                   --right (default) | --left | --force"
        echo "    tgt prompt uninstall         Remove the managed prompt file(s)"
        echo "    tgt prompt status            Show what's currently installed"
        echo "    tgt_prompt                   Render [scenario:target] (color = damage potential)"
        echo ""
        echo "  WORKSPACE"
        echo "    tgt cd [alias|--scenario]    cd to active target's / scenario's workspace folder"
        echo "    tgt path [alias|--scenario]  Print the workspace path (no cd)"
        echo "    tgt workspace                Show settings + visualize current scenario's tree"
        echo "    tgt workspace create [alias] Build the folder tree manually (regardless of autocreate)"
        echo "    tgt config                   Interactive editor for workspace settings"
        echo "    tgt config reset             Revert all workspace settings to defaults"
        echo ""
        echo "  ENVIRONMENT VARIABLES"
        echo "    target:    \$TGT  \$TGT_PORT  \$TGT_HOSTS"
        echo "    cred:      \$TGT_CRED_NAME  \$TGT_USERNAME  \$TGT_PASSWORD  \$TGT_CRED_DOMAIN"
        echo "    AD/DC:     \$TGT_DC_NAME  \$TGT_DC_DOMAIN  \$TGT_DC_REALM"
        echo "               \$TGT_DC  \$TGT_DC_HOST  \$TGT_DC_IP"
        echo "    scope:     \$TGT_SCENARIO  \$TGT_ACTIVE"
        echo "    workspace: \$TGT_WORKSPACE_ROOT  \$TGT_WORKSPACE_LAYOUT  \$TGT_WORKSPACE_AUTOCREATE"
        echo "               \$TGT_WORKSPACE_TARGET_TEMPLATE  \$TGT_WORKSPACE_SCENARIO_TEMPLATE"
        echo ""
        echo "  SEE ALSO"
        echo "    tgt scenario --help    tgt prompt --help    tgt config --help"
        echo "    tgt hosts --help       tgt workspace --help"
        echo ""
        return 0
    end

    set -l krb5_file (_tgt_krb5_file)
    set -l hosts_scenario (_tgt_active_scenario_name)
    set -l hosts_target   (_tgt_active_target_name)

    # ── Revoke ──────────────────────────────────────────────
    if test (count $argv) -ge 1; and begin; test $argv[1] = "--revoke"; or test $argv[1] = "revoke"; end
        # Clean /etc/hosts
        if set -q TGT
            set -l existing (_tgt_hosts_get $hosts_scenario $hosts_target)
            if test (count $existing) -gt 0
                _tgt_hosts_revoke $hosts_scenario $hosts_target
                echo "✓ Removed $TGT from /etc/hosts"
            end
        end

        # Target-level runtime only — credentials and DC are
        # scenario-level now and survive a target switch. Use
        # `tgt cred unset` / `tgt dc unset` to clear those.
        set -q TGT            && _tgt_unexport TGT            && echo "✓ TGT unset"            || echo "- TGT was not set"
        set -q TGT_PORT       && _tgt_unexport TGT_PORT       && echo "✓ TGT_PORT unset"       || echo "- TGT_PORT was not set"
        set -q TGT_HOSTS      && _tgt_unexport TGT_HOSTS      && echo "✓ TGT_HOSTS unset"      || echo "- TGT_HOSTS was not set"
        set -q TGT_ACTIVE     && _tgt_unexport TGT_ACTIVE     && echo "✓ TGT_ACTIVE unset (target deselected; scenario kept)" || echo "- TGT_ACTIVE was not set"
        return 0
    end

    # ── Show current state ──────────────────────────────────
    if test (count $argv) -ge 1; and begin; test $argv[1] = "--show"; or test $argv[1] = "show"; end
        echo ""
        echo "─────────────────────────────────"
        set -q TGT            && echo "  TGT           = $TGT"            || echo "  TGT           = (not set)"
        set -q TGT_PORT       && echo "  TGT_PORT      = $TGT_PORT"       || echo "  TGT_PORT      = (not set)"
        set -q TGT_HOSTS      && echo "  TGT_HOSTS     = $TGT_HOSTS"      || echo "  TGT_HOSTS     = (not set)"
        if set -q TGT_CRED_NAME
            echo ""
            echo "  active credential:"
            echo "    alias       = $TGT_CRED_NAME"
            set -q TGT_USERNAME     && echo "    username    = $TGT_USERNAME"
            set -q TGT_PASSWORD     && echo "    password    = $TGT_PASSWORD"
            set -q TGT_CRED_DOMAIN  && echo "    domain      = $TGT_CRED_DOMAIN"
            set -q TGT_CRED_NOTES   && echo "    notes       = $TGT_CRED_NOTES"
        end
        if set -q TGT_DC_NAME
            echo ""
            echo "  active DC:"
            echo "    name        = $TGT_DC_NAME"
            set -q TGT_DC_DOMAIN && echo "    domain      = $TGT_DC_DOMAIN"
            set -q TGT_DC_REALM  && echo "    realm       = $TGT_DC_REALM"
            set -q TGT_DC_HOST   && echo "    kdc host    = $TGT_DC_HOST"
            set -q TGT_DC_IP     && echo "    kdc ip      = $TGT_DC_IP"
        end
        echo "─────────────────────────────────"
        echo ""
        if set -q TGT
            echo "  /etc/hosts:"
            set -l hosts (_tgt_hosts_get $hosts_scenario $hosts_target)
            if test (count $hosts) -gt 0
                echo "    $TGT "(string join " " -- $hosts)
            else
                echo "    (no entries)"
            end
        end
        if set -q TGT_DC_REALM
            echo ""
            echo "  /etc/krb5.conf:"
            grep -A2 "$TGT_DC_REALM" $krb5_file 2>/dev/null || echo "    (no entries)"
        end
        # Workspace section — only when scenario is active and the
        # workspace dir exists on disk (otherwise nothing useful to
        # show, and we don't want to nudge users about a feature
        # they haven't opted into).
        if set -q TGT_SCENARIO
            set -l ws_dir (_tgt_workspace_dir $TGT_SCENARIO)
            if test -d $ws_dir
                _tgt_workspace_show
            end
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

        _tgt_hosts_add $hosts_scenario $hosts_target $TGT $new_hosts

        set -l updated (_tgt_hosts_get $hosts_scenario $hosts_target)
        _tgt_export TGT_HOSTS $updated
        _tgt_maybe_save_active
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

        _tgt_hosts_remove $hosts_scenario $hosts_target $rm_hosts

        set -l remaining (_tgt_hosts_get $hosts_scenario $hosts_target)
        if test (count $remaining) -gt 0
            _tgt_export TGT_HOSTS $remaining
            echo "✓ /etc/hosts: $TGT $TGT_HOSTS"
        else
            set -q TGT_HOSTS && _tgt_unexport TGT_HOSTS
            echo "✓ All hostnames removed for $TGT"
        end
        _tgt_maybe_save_active
        return 0
    end

    # ── Scenarios ───────────────────────────────────────────
    if test (count $argv) -ge 1 && test $argv[1] = "scenario"
        _tgt_scenario_cli $argv[2..]
        return $status
    end

    # ── Prompt segment ──────────────────────────────────────
    if test (count $argv) -ge 1 && test $argv[1] = "prompt"
        _tgt_prompt_cli $argv[2..]
        return $status
    end

    # ── Workspace folders / cd / path ───────────────────────
    if test (count $argv) -ge 1
        switch $argv[1]
            case cd path workspace
                _tgt_workspace_cli $argv
                return $status
        end
    end

    # ── Config (interactive editor for workspace settings) ──
    if test (count $argv) -ge 1 && test $argv[1] = "config"
        _tgt_config_cli $argv[2..]
        return $status
    end

    # ── Targets within the active scenario ─────────────────
    if test (count $argv) -ge 1
        switch $argv[1]
            case new switch list rm edit rename
                _tgt_target_cli $argv
                return $status
        end
    end

    # ── Hosts editor (multi-line /etc/hosts editor) ─────────
    if test (count $argv) -ge 1 && test $argv[1] = "hosts"
        _tgt_hosts_cli $argv[2..]
        return $status
    end

    # ── Ports (per-target port records) ─────────────────────
    if test (count $argv) -ge 1 && test $argv[1] = "ports"
        _tgt_ports_cli $argv[2..]
        return $status
    end

    # ── DCs (per-scenario krb5 realm definitions) ───────────
    if test (count $argv) -ge 1 && test $argv[1] = "dc"
        _tgt_dc_cli $argv[2..]
        return $status
    end

    # ── Credentials (per-scenario, floating across targets) ─
    if test (count $argv) -ge 1 && test $argv[1] = "cred"
        _tgt_cred_cli $argv[2..]
        return $status
    end

    # ── Web UI (proof of concept, see web/server.py) ────────
    if test (count $argv) -ge 1 && test $argv[1] = "web"
        tgt_web $argv[2..]
        return $status
    end

    # ── Anything else: unknown ──────────────────────────────
    # Fall-through means the user typed something that didn't
    # match any verb / flag above. Refuse loudly instead of
    # silently running the wizard for the active target.
    if test (count $argv) -gt 0
        echo "tgt: unknown command '$argv[1]'" >&2
        echo "Try: tgt --help" >&2
        return 1
    end

    # ── No args: action picker (gum + TTY) or help text ────
    if command -q gum; and not set -q TGT_TEST_MODE; and isatty stdin
        _tgt_action_menu
        return $status
    end
    tgt --help
end
