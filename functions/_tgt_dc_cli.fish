# Dispatch for `tgt dc …` — DC entries (per-scenario krb5 realm
# definitions) live alongside targets and ports.
#
#   tgt dc list                 list all DCs in the active scenario
#   tgt dc show [alias]         detailed view (no arg → fzf picker)
#   tgt dc new <alias> --domain <d> [--realm <R>]
#                      [--kdc-host <h>] [--kdc-ip <ip>]
#                      [--admin-host <h>] [--admin-ip <ip>]
#   tgt dc switch [alias]       activate (loads env, sets default_realm)
#   tgt dc unset                clear active-DC env vars + per-scenario marker
#   tgt dc edit [alias]         interactive editor with current values prefilled
#   tgt dc rename [<old>] <new> rename a DC entry (alias the active one when <old> omitted)
#   tgt dc rm   [alias]         remove a DC entry
#
# Active-DC behavior: `tgt dc new` auto-activates the just-created
# entry. The active DC is remembered per-scenario via a marker file,
# so `tgt scenario switch` restores whichever DC was last active in
# the scenario you're moving into.
function _tgt_dc_cli
    set -l verb $argv[1]
    set -l rest $argv[2..]

    if not set -q TGT_SCENARIO
        echo "tgt dc: no active scenario — run `tgt scenario new <name>` or `tgt scenario switch <name>` first" >&2
        return 1
    end
    set -l scenario $TGT_SCENARIO

    if not _tgt_scenario_exists $scenario
        echo "tgt dc: active scenario '$scenario' is missing from the registry" >&2
        return 1
    end

    switch $verb
        case list
            set -l aliases (_tgt_dc_list $scenario)
            if test (count $aliases) -eq 0
                echo "(no DCs recorded for $scenario)"
                return 0
            end
            for a in $aliases
                set -l line (_tgt_dc_inspect $scenario $a)
                set -l fields (string split \t -- $line)
                # alias  domain  realm  kdc  admin
                printf '  %-12s %-20s %-20s %-24s %s\n' \
                    $fields[1] $fields[2] $fields[3] $fields[4] $fields[5]
            end
            return 0

        case ''
            # No verb → drop into the switch picker (mirrors `tgt
            # switch` / `tgt ports`). `tgt dc list` is for just-show-me.
            set -l aliases (_tgt_dc_list $scenario)
            if test (count $aliases) -eq 0
                echo "(no DCs recorded for $scenario — `tgt dc new` to add one)"
                return 0
            end
            _tgt_dc_cli switch
            return $status

        case show
            set -l alias $rest[1]
            if test -z "$alias"
                set -l aliases (_tgt_dc_list $scenario)
                if test (count $aliases) -eq 0
                    echo "tgt dc show: no DCs in scenario '$scenario'" >&2
                    return 1
                end
                set alias (_tgt_pick "DC" $aliases)
                test -z "$alias"; and return 1
            end
            if not _tgt_dc_exists $scenario $alias
                echo "tgt dc show: DC '$alias' does not exist in scenario '$scenario'" >&2
                return 1
            end
            set -l line (_tgt_dc_inspect $scenario $alias)
            set -l fields (string split \t -- $line)
            # Walk the file once more to surface the host/ip pair
            # split that inspect collapses, plus the IP source
            # attribution so the user can tell where the address
            # came from (user input, /etc/hosts, or DNS probe).
            set -l file (_tgt_dc_file $scenario $alias)
            set -l kdc_host ""
            set -l kdc_ip ""
            set -l kdc_ip_src ""
            set -l admin_host ""
            set -l admin_ip ""
            set -l admin_ip_src ""
            while read -l ln
                set -l m (string match -r '^_tgt_export\s+(\S+)\s+(.*)$' -- $ln)
                test (count $m) -lt 3; and continue
                set -l val (string unescape -- $m[3])
                switch $m[2]
                    case TGT_DC_HOST
                        set kdc_host $val
                    case TGT_DC_IP
                        set kdc_ip $val
                    case TGT_DC_IP_SOURCE
                        set kdc_ip_src $val
                    case TGT_DC_ADMIN_HOST
                        set admin_host $val
                    case TGT_DC_ADMIN_IP
                        set admin_ip $val
                    case TGT_DC_ADMIN_IP_SOURCE
                        set admin_ip_src $val
                end
            end < $file
            set_color brblack; printf '  alias:        '; set_color normal; echo $fields[1]
            set_color brblack; printf '  domain:       '; set_color normal; echo $fields[2]
            set_color brblack; printf '  realm:        '; set_color normal; echo $fields[3]
            set_color brblack; printf '  kdc:          '; set_color normal
            _tgt_dc_cli_emit_pair "$kdc_host" "$kdc_ip" "$kdc_ip_src"
            set_color brblack; printf '  admin_server: '; set_color normal
            _tgt_dc_cli_emit_pair "$admin_host" "$admin_ip" "$admin_ip_src"
            return 0

        case new
            argparse --name='tgt dc new' \
                'd/domain=' 'r/realm=' \
                'kdc-host=' 'kdc-ip=' \
                'admin-host=' 'admin-ip=' \
                -- $rest
            or return 1

            set -l alias $argv[1]

            # No data flags → drop into the interactive wizard.
            # In TGT_TEST_MODE we skip the wizard so non-interactive
            # tests can rely on flag parsing failing fast.
            set -l have_data_flags 0
            for f in _flag_domain _flag_realm _flag_kdc_host _flag_kdc_ip _flag_admin_host _flag_admin_ip
                set -q $f; and set have_data_flags 1
            end
            if test $have_data_flags -eq 0; and not set -q TGT_TEST_MODE
                _tgt_dc_wizard $scenario $alias
                return $status
            end

            if test -z "$alias"
                echo "Usage: tgt dc new <alias> --domain <d> [--realm <R>] [--kdc-host <h>] [--kdc-ip <ip>] [--admin-host <h>] [--admin-ip <ip>]" >&2
                return 1
            end
            if not _tgt_dc_validate_name $alias
                echo "tgt dc new: invalid alias '$alias' (allowed: A-Z a-z 0-9 _ -)" >&2
                return 1
            end
            if _tgt_dc_exists $scenario $alias
                echo "tgt dc new: DC '$alias' already exists in scenario '$scenario'" >&2
                return 1
            end
            if not set -q _flag_domain; or test -z "$_flag_domain"
                echo "tgt dc new: --domain is required" >&2
                return 1
            end
            if test -z "$_flag_kdc_host"; and test -z "$_flag_kdc_ip"
                echo "tgt dc new: at least one of --kdc-host or --kdc-ip is required" >&2
                return 1
            end

            # Realm defaults to upper(domain). User-provided realm is
            # silently uppercased — kerberos realms are uppercase by
            # convention; a lowercase realm would footgun every tool.
            set -l realm $_flag_realm
            test -z "$realm"; and set realm $_flag_domain
            set realm (string upper -- $realm)

            # Clear any prior DC's runtime first so absent flags
            # don't inherit stale values from the previously-active
            # DC's saved state. Then stage and let the finalizer
            # handle save / sync / auto-activate.
            _tgt_dc_clear_runtime
            set -gx TGT_DC_DOMAIN $_flag_domain
            set -gx TGT_DC_REALM $realm
            test -n "$_flag_kdc_host"   ; and set -gx TGT_DC_HOST $_flag_kdc_host
            test -n "$_flag_kdc_ip"     ; and set -gx TGT_DC_IP $_flag_kdc_ip
            test -n "$_flag_admin_host" ; and set -gx TGT_DC_ADMIN_HOST $_flag_admin_host
            test -n "$_flag_admin_ip"   ; and set -gx TGT_DC_ADMIN_IP $_flag_admin_ip

            _tgt_dc_finalize_new $scenario $alias
            or return $status

            set_color green; echo "✓ DC '$alias' created in '$scenario' and activated"; set_color normal
            return 0

        case switch
            set -l alias $rest[1]
            if test -z "$alias"
                set -l aliases (_tgt_dc_list $scenario)
                if test (count $aliases) -eq 0
                    echo "tgt dc switch: no DCs in scenario '$scenario'" >&2
                    return 1
                end
                set alias (_tgt_pick "DC" $aliases)
                test -z "$alias"; and return 1
            end
            if not _tgt_dc_exists $scenario $alias
                echo "tgt dc switch: DC '$alias' does not exist in scenario '$scenario'" >&2
                return 1
            end
            _tgt_dc_clear_runtime
            _tgt_dc_load $scenario $alias
            _tgt_dc_set_active $scenario $alias
            set -q TGT_DC_REALM; and _tgt_krb5_set_default_realm $TGT_DC_REALM
            set_color green; echo "✓ active DC: $scenario:$alias"; set_color normal
            return 0

        case unset
            if set -q TGT_DC_NAME
                set -l prev $TGT_DC_NAME
                _tgt_dc_clear_runtime
                _tgt_dc_clear_active $scenario
                set_color green; echo "✓ DC unset (was $prev)"; set_color normal
            else
                # Marker may still exist even when env was cleared
                # by another path — clear it too for consistency.
                _tgt_dc_clear_active $scenario
                echo "- no DC was active"
            end
            return 0

        case rename
            set -l old ""
            set -l new ""
            if test (count $rest) -ge 2
                set old $rest[1]
                set new $rest[2]
            else if test (count $rest) -ge 1
                set old (_tgt_dc_get_active $scenario 2>/dev/null)
                if test -z "$old"
                    echo "tgt dc rename: no active DC. Specify <old> <new>." >&2
                    return 1
                end
                set new $rest[1]
            else
                echo "Usage: tgt dc rename [<old>] <new>" >&2
                return 1
            end
            if test "$old" = "$new"
                echo "tgt dc rename: same name, nothing to do" >&2
                return 1
            end
            if not _tgt_dc_validate_name $new
                echo "tgt dc rename: invalid name '$new' (allowed: A-Z a-z 0-9 _ -)" >&2
                return 1
            end
            if not _tgt_dc_exists $scenario $old
                echo "tgt dc rename: DC '$old' does not exist in scenario '$scenario'" >&2
                return 1
            end
            if _tgt_dc_exists $scenario $new
                echo "tgt dc rename: DC '$new' already exists in scenario '$scenario'" >&2
                return 1
            end

            set -l old_file (_tgt_dc_file $scenario $old)
            set -l new_file (_tgt_dc_file $scenario $new)
            if not command mv -- $old_file $new_file
                echo "tgt dc rename: failed to move registry file" >&2
                return 1
            end

            # If the renamed DC was active, repoint the marker and
            # the in-shell TGT_DC_NAME (when this scenario is the
            # active one).
            set -l active (_tgt_dc_get_active $scenario 2>/dev/null)
            if test "$active" = "$old"
                _tgt_dc_set_active $scenario $new
                if set -q TGT_SCENARIO; and test "$TGT_SCENARIO" = "$scenario"
                    and set -q TGT_DC_NAME; and test "$TGT_DC_NAME" = "$old"
                    _tgt_export TGT_DC_NAME $new
                end
            end

            # Re-emit krb5 + hosts so the `# tgt:dc:<scen>:<alias>`
            # comment markers carry the new name.
            _tgt_krb5_apply_scenario $scenario
            _tgt_hosts_apply_scenario $scenario

            set_color green; echo "✓ renamed DC '$old' → '$new'"; set_color normal
            return 0

        case edit
            # Flag-driven non-interactive edit when ANY of the six
            # field flags is set; falls through to the wizard when
            # none is. Empty value clears that field (domain stays
            # required; realm auto-derives from domain when empty,
            # matching the wizard).
            argparse --name='tgt dc edit' \
                'd/domain=' 'r/realm=' \
                'kdc-host=' 'kdc-ip=' \
                'admin-host=' 'admin-ip=' \
                -- $rest
            or return 1

            set -l alias ""
            test (count $argv) -ge 1; and set alias $argv[1]
            if test -z "$alias"
                set -l aliases (_tgt_dc_list $scenario)
                if test (count $aliases) -eq 0
                    echo "tgt dc edit: no DCs in scenario '$scenario'" >&2
                    return 1
                end
                set alias (_tgt_pick "DC to edit" $aliases)
                test -z "$alias"; and return 1
            end
            if not _tgt_dc_exists $scenario $alias
                echo "tgt dc edit: DC '$alias' does not exist in scenario '$scenario'" >&2
                return 1
            end

            set -l any_flag 0
            for f in _flag_domain _flag_realm _flag_kdc_host _flag_kdc_ip \
                     _flag_admin_host _flag_admin_ip
                set -q $f; and set any_flag 1; and break
            end
            if test $any_flag -eq 0
                _tgt_dc_edit_wizard $scenario $alias
                return $status
            end

            # Read current fields from disk (no helper exists for DC
            # the way _tgt_cred_read_fields does for creds — wizard
            # inlines the same loop).
            set -l cur_domain ""
            set -l cur_realm ""
            set -l cur_kdc_host ""
            set -l cur_kdc_ip ""
            set -l cur_admin_host ""
            set -l cur_admin_ip ""
            set -l file (_tgt_dc_file $scenario $alias)
            while read -l line
                set -l m (string match -r '^_tgt_export\s+(\S+)\s+(.*)$' -- $line)
                test (count $m) -lt 3; and continue
                set -l val (string unescape -- $m[3])
                switch $m[2]
                    case TGT_DC_DOMAIN
                        set cur_domain $val
                    case TGT_DC_REALM
                        set cur_realm $val
                    case TGT_DC_HOST
                        set cur_kdc_host $val
                    case TGT_DC_IP
                        set cur_kdc_ip $val
                    case TGT_DC_ADMIN_HOST
                        set cur_admin_host $val
                    case TGT_DC_ADMIN_IP
                        set cur_admin_ip $val
                end
            end < $file

            set -l new_domain $cur_domain
            set -l new_realm $cur_realm
            set -l new_kdc_host $cur_kdc_host
            set -l new_kdc_ip $cur_kdc_ip
            set -l new_admin_host $cur_admin_host
            set -l new_admin_ip $cur_admin_ip
            set -q _flag_domain;     and set new_domain $_flag_domain
            set -q _flag_realm;      and set new_realm $_flag_realm
            set -q _flag_kdc_host;   and set new_kdc_host $_flag_kdc_host
            set -q _flag_kdc_ip;     and set new_kdc_ip $_flag_kdc_ip
            set -q _flag_admin_host; and set new_admin_host $_flag_admin_host
            set -q _flag_admin_ip;   and set new_admin_ip $_flag_admin_ip

            if test -z "$new_domain"
                echo "tgt dc edit: domain cannot be empty" >&2
                return 1
            end
            if test -z "$new_kdc_host"; and test -z "$new_kdc_ip"
                echo "tgt dc edit: at least one of --kdc-host or --kdc-ip must be set" >&2
                return 1
            end
            # Auto-derive realm from domain when empty, then always
            # uppercase. Mirrors wizard.
            test -z "$new_realm"; and set new_realm $new_domain
            set new_realm (string upper -- $new_realm)

            # Stage + save (matches wizard). Flag-mode IPs are always
            # attributed to `user` (vs. wizard which preserves DNS-
            # resolver attribution for accepted-default IPs).
            for v in TGT_DC_DOMAIN TGT_DC_REALM \
                     TGT_DC_HOST TGT_DC_IP TGT_DC_IP_SOURCE \
                     TGT_DC_ADMIN_HOST TGT_DC_ADMIN_IP TGT_DC_ADMIN_IP_SOURCE
                set -q $v; and _tgt_unexport $v
            end
            set -gx TGT_DC_DOMAIN $new_domain
            set -gx TGT_DC_REALM $new_realm
            test -n "$new_kdc_host"  ; and set -gx TGT_DC_HOST $new_kdc_host
            if test -n "$new_kdc_ip"
                set -gx TGT_DC_IP $new_kdc_ip
                set -gx TGT_DC_IP_SOURCE user
            end
            test -n "$new_admin_host"; and set -gx TGT_DC_ADMIN_HOST $new_admin_host
            if test -n "$new_admin_ip"
                set -gx TGT_DC_ADMIN_IP $new_admin_ip
                set -gx TGT_DC_ADMIN_IP_SOURCE user
            end

            _tgt_dc_save $scenario $alias
            or return $status

            # Resolve any host without an IP, honoring "user just
            # cleared" intent (mirrors the wizard).
            set -l skip_kdc 0
            set -l skip_admin 0
            test -n "$cur_kdc_ip";   and test -z "$new_kdc_ip";   and set skip_kdc 1
            test -n "$cur_admin_ip"; and test -z "$new_admin_ip"; and set skip_admin 1
            _tgt_dc_resolve_missing $scenario $alias $skip_kdc $skip_admin

            _tgt_krb5_apply_scenario $scenario
            _tgt_hosts_apply_scenario $scenario

            set -l active (_tgt_dc_get_active $scenario 2>/dev/null)
            _tgt_dc_clear_runtime
            if test -n "$active"
                _tgt_dc_load $scenario $active
                set -q TGT_DC_REALM; and _tgt_krb5_set_default_realm $TGT_DC_REALM
            end

            set_color green; echo "✓ DC '$alias' updated in '$scenario'"; set_color normal
            return 0

        case rm
            set -l alias $rest[1]
            if test -z "$alias"
                set -l aliases (_tgt_dc_list $scenario)
                if test (count $aliases) -eq 0
                    echo "tgt dc rm: no DCs in scenario '$scenario'" >&2
                    return 1
                end
                set alias (_tgt_pick "DC to remove" $aliases)
                test -z "$alias"; and return 1
            end
            if not _tgt_dc_exists $scenario $alias
                echo "tgt dc rm: DC '$alias' does not exist in scenario '$scenario'" >&2
                return 1
            end
            _tgt_dc_destroy $scenario $alias
            # Clear active marker (and current-shell runtime) if we
            # just removed the active DC. Capture the active alias
            # into a local first — splicing the command sub directly
            # into `test ... = ...` breaks when there's no active DC
            # (the empty expansion eats the third arg).
            set -l active (_tgt_dc_get_active $scenario 2>/dev/null)
            if test "$alias" = "$active"
                _tgt_dc_clear_active $scenario
                _tgt_dc_clear_runtime
            end
            _tgt_krb5_apply_scenario $scenario
            _tgt_hosts_apply_scenario $scenario
            set_color green; echo "✓ DC '$alias' removed from '$scenario'"; set_color normal
            return 0

        case '*'
            echo "tgt dc: unknown subcommand '$verb'" >&2
            return 1
    end
end
