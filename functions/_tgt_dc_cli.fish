# Dispatch for `tgt dc …` — DC entries (per-scenario krb5 realm
# definitions) live alongside targets and ports.
#
# This commit lands list / show / rm / new. `switch`, `unset`,
# krb5 sync, /etc/hosts integration, the wizard, and prompt
# coupling come later.
#
#   tgt dc list                 list all DCs in the active scenario
#   tgt dc show [alias]         detailed view (no arg → fzf picker)
#   tgt dc new <alias> --domain <d> [--realm <R>]
#                      [--kdc-host <h>] [--kdc-ip <ip>]
#                      [--admin-host <h>] [--admin-ip <ip>]
#   tgt dc rm   [alias]         remove a DC entry
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
        case '' list
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
            # split that inspect collapses into a single kdc/admin.
            set -l file (_tgt_dc_file $scenario $alias)
            set -l kdc_host ""
            set -l kdc_ip ""
            set -l admin_host ""
            set -l admin_ip ""
            while read -l ln
                set -l m (string match -r '^_tgt_export\s+(\S+)\s+(.*)$' -- $ln)
                test (count $m) -lt 3; and continue
                switch $m[2]
                    case TGT_DC_HOST
                        set kdc_host $m[3]
                    case TGT_DC_IP
                        set kdc_ip $m[3]
                    case TGT_DC_ADMIN_HOST
                        set admin_host $m[3]
                    case TGT_DC_ADMIN_IP
                        set admin_ip $m[3]
                end
            end < $file
            set_color brblack; printf '  alias:        '; set_color normal; echo $fields[1]
            set_color brblack; printf '  domain:       '; set_color normal; echo $fields[2]
            set_color brblack; printf '  realm:        '; set_color normal; echo $fields[3]
            set_color brblack; printf '  kdc:          '; set_color normal
            _tgt_dc_cli_emit_pair "$kdc_host" "$kdc_ip"
            set_color brblack; printf '  admin_server: '; set_color normal
            _tgt_dc_cli_emit_pair "$admin_host" "$admin_ip"
            return 0

        case new
            argparse --name='tgt dc new' \
                'd/domain=' 'r/realm=' \
                'kdc-host=' 'kdc-ip=' \
                'admin-host=' 'admin-ip=' \
                -- $rest
            or return 1

            set -l alias $argv[1]
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

            # Stage env vars, save, clear (active-on-new lands with
            # the switch/unset commit).
            set -gx TGT_DC_DOMAIN $_flag_domain
            set -gx TGT_DC_REALM $realm
            test -n "$_flag_kdc_host"   ; and set -gx TGT_DC_HOST $_flag_kdc_host
            test -n "$_flag_kdc_ip"     ; and set -gx TGT_DC_IP $_flag_kdc_ip
            test -n "$_flag_admin_host" ; and set -gx TGT_DC_ADMIN_HOST $_flag_admin_host
            test -n "$_flag_admin_ip"   ; and set -gx TGT_DC_ADMIN_IP $_flag_admin_ip

            _tgt_dc_save $scenario $alias
            set -l rc $status

            for v in TGT_DC_DOMAIN TGT_DC_REALM TGT_DC_HOST TGT_DC_IP TGT_DC_ADMIN_HOST TGT_DC_ADMIN_IP
                set -q $v; and _tgt_unexport $v
            end

            test $rc -eq 0; or return $rc
            _tgt_krb5_apply_scenario $scenario
            set_color green; echo "✓ DC '$alias' created in '$scenario'"; set_color normal
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
            _tgt_krb5_apply_scenario $scenario
            set_color green; echo "✓ DC '$alias' removed from '$scenario'"; set_color normal
            return 0

        case '*'
            echo "tgt dc: unknown subcommand '$verb'" >&2
            return 1
    end
end
