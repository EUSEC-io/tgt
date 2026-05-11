# Dispatch for `tgt cred …` — per-scenario credential entries.
#
#   tgt cred                       list + pick → set active (switch)
#   tgt cred list                  list, no picker
#   tgt cred show [alias] [--show-password]
#                                  detailed view (no arg → fzf picker)
#   tgt cred new [alias] --username <u> [--password <p>] [--domain <d>] [--notes <n>]
#                                  if [alias] omitted, defaults to --username
#                                  when the username is a valid alias
#   tgt cred new                   (no data flags) drops into wizard
#   tgt cred edit [alias]          wizard with current values prefilled
#   tgt cred rename [<old>] <new>  rename a cred entry
#   tgt cred switch [alias]        activate (loads TGT_USERNAME / TGT_PASSWORD)
#   tgt cred unset                 clear active-cred env vars + marker
#   tgt cred rm [alias]            remove a cred entry
#
# Active-cred behavior: `tgt cred new` and `tgt cred switch` set
# the per-scenario `.active-cred` marker and load env vars.
# Scenario switch restores whichever cred was last active in the
# scenario being entered.
function _tgt_cred_cli
    if not set -q TGT_SCENARIO
        echo "tgt cred: no active scenario — run `tgt scenario new <name>` or `tgt scenario switch <name>` first" >&2
        return 1
    end
    set -l scenario $TGT_SCENARIO

    if not _tgt_scenario_exists $scenario
        echo "tgt cred: active scenario '$scenario' is missing from the registry" >&2
        return 1
    end

    set -l verb $argv[1]
    set -l rest $argv[2..]

    switch $verb
        case list
            set -l aliases (_tgt_cred_list $scenario)
            if test (count $aliases) -eq 0
                echo "(no credentials recorded for $scenario)"
                return 0
            end
            for a in $aliases
                set -l line (_tgt_cred_inspect $scenario $a)
                set -l fields (string split \t -- $line)
                # alias  username  has_password  domain  notes
                printf '  %-12s %-20s  pw:%s  %-20s %s\n' \
                    $fields[1] $fields[2] $fields[3] $fields[4] $fields[5]
            end
            return 0

        case ''
            # No verb → drop into the switch picker. `tgt cred list`
            # is the "just show me" path.
            set -l aliases (_tgt_cred_list $scenario)
            if test (count $aliases) -eq 0
                echo "(no credentials recorded for $scenario — `tgt cred new` to add one)"
                return 0
            end
            _tgt_cred_cli switch
            return $status

        case show
            argparse --name='tgt cred show' 'show-password' -- $rest
            or return 1
            set -l alias $argv[1]
            if test -z "$alias"
                set -l aliases (_tgt_cred_list $scenario)
                if test (count $aliases) -eq 0
                    echo "tgt cred show: no credentials in scenario '$scenario'" >&2
                    return 1
                end
                set alias (_tgt_pick "credential" $aliases)
                test -z "$alias"; and return 1
            end
            if not _tgt_cred_exists $scenario $alias
                echo "tgt cred show: credential '$alias' does not exist in scenario '$scenario'" >&2
                return 1
            end
            # Re-read raw fields for the detailed display.
            set -l file (_tgt_cred_file $scenario $alias)
            set -l username ""
            set -l password ""
            set -l domain ""
            set -l notes ""
            while read -l ln
                set -l m (string match -r '^_tgt_export\s+(\S+)\s+(.*)$' -- $ln)
                test (count $m) -lt 3; and continue
                # `_tgt_cred_save` runs the value through `string escape`,
                # which adds single-quote wrapping iff the value isn't
                # bare-token-safe — reverse it on read.
                set -l val (string unescape -- $m[3])
                switch $m[2]
                    case TGT_CRED_USERNAME
                        set username $val
                    case TGT_CRED_PASSWORD
                        set password $val
                    case TGT_CRED_DOMAIN
                        set domain $val
                    case TGT_CRED_NOTES
                        set notes $val
                end
            end < $file
            set_color brblack; printf '  alias:    '; set_color normal; echo $alias
            set_color brblack; printf '  username: '; set_color normal; echo $username
            set_color brblack; printf '  password: '; set_color normal
            if test -z "$password"
                set_color brblack; echo "(not set)"; set_color normal
            else if set -q _flag_show_password
                set_color red; echo $password; set_color normal
            else
                set_color red; echo "(set — pass --show-password to reveal)"; set_color normal
            end
            set_color brblack; printf '  domain:   '; set_color normal
            test -n "$domain"; and echo $domain; or begin; set_color brblack; echo "(not set)"; set_color normal; end
            set_color brblack; printf '  notes:    '; set_color normal
            test -n "$notes"; and echo $notes; or begin; set_color brblack; echo "(none)"; set_color normal; end
            return 0

        case new
            argparse --name='tgt cred new' \
                'u/username=' 'p/password=' 'd/domain=' 'n/notes=' \
                -- $rest
            or return 1

            set -l alias $argv[1]

            set -l have_data_flags 0
            for f in _flag_username _flag_password _flag_domain _flag_notes
                set -q $f; and set have_data_flags 1
            end
            if test $have_data_flags -eq 0; and not set -q TGT_TEST_MODE
                _tgt_cred_wizard $scenario $alias
                return $status
            end

            # No positional alias? Default it to --username when the
             # username happens to be a valid alias. The username field
            # itself is opaque (UTF-8, Windows DOMAIN\user, whatever),
            # so this only kicks in for the common ASCII case.
            if test -z "$alias"; and set -q _flag_username
                and _tgt_cred_validate_name $_flag_username
                set alias $_flag_username
            end
            if test -z "$alias"
                echo "Usage: tgt cred new [alias] --username <u> [--password <p>] [--domain <d>] [--notes <n>]" >&2
                echo "  (alias defaults to --username when the username is a valid alias)" >&2
                return 1
            end
            if not _tgt_cred_validate_name $alias
                echo "tgt cred new: invalid alias '$alias' (allowed: A-Z a-z 0-9 _ - .; can't start with .)" >&2
                return 1
            end
            if _tgt_cred_exists $scenario $alias
                echo "tgt cred new: credential '$alias' already exists in scenario '$scenario'" >&2
                return 1
            end
            if not set -q _flag_username; or test -z "$_flag_username"
                echo "tgt cred new: --username is required" >&2
                return 1
            end

            _tgt_cred_clear_runtime
            set -gx TGT_CRED_USERNAME $_flag_username
            test -n "$_flag_password" ; and set -gx TGT_CRED_PASSWORD $_flag_password
            test -n "$_flag_domain"   ; and set -gx TGT_CRED_DOMAIN $_flag_domain
            test -n "$_flag_notes"    ; and set -gx TGT_CRED_NOTES $_flag_notes

            _tgt_cred_finalize_new $scenario $alias
            or return $status

            set_color green; echo "✓ credential '$alias' created in '$scenario' and activated"; set_color normal
            return 0

        case switch
            set -l alias $rest[1]
            if test -z "$alias"
                set -l aliases (_tgt_cred_list $scenario)
                if test (count $aliases) -eq 0
                    echo "tgt cred switch: no credentials in scenario '$scenario'" >&2
                    return 1
                end
                set alias (_tgt_pick "credential" $aliases)
                test -z "$alias"; and return 1
            end
            if not _tgt_cred_exists $scenario $alias
                echo "tgt cred switch: credential '$alias' does not exist in scenario '$scenario'" >&2
                return 1
            end
            _tgt_cred_clear_runtime
            _tgt_cred_load $scenario $alias
            _tgt_cred_set_active $scenario $alias
            set_color green; echo "✓ active credential: $scenario:$alias"; set_color normal
            return 0

        case unset
            if set -q TGT_CRED_NAME
                set -l prev $TGT_CRED_NAME
                _tgt_cred_clear_runtime
                _tgt_cred_clear_active $scenario
                set_color green; echo "✓ credential unset (was $prev)"; set_color normal
            else
                _tgt_cred_clear_active $scenario
                echo "- no credential was active"
            end
            return 0

        case edit
            set -l alias $rest[1]
            if test -z "$alias"
                set -l aliases (_tgt_cred_list $scenario)
                if test (count $aliases) -eq 0
                    echo "tgt cred edit: no credentials in scenario '$scenario'" >&2
                    return 1
                end
                set alias (_tgt_pick "credential to edit" $aliases)
                test -z "$alias"; and return 1
            end
            if not _tgt_cred_exists $scenario $alias
                echo "tgt cred edit: credential '$alias' does not exist in scenario '$scenario'" >&2
                return 1
            end
            _tgt_cred_edit_wizard $scenario $alias
            return $status

        case rename
            set -l old ""
            set -l new ""
            if test (count $rest) -ge 2
                set old $rest[1]
                set new $rest[2]
            else if test (count $rest) -ge 1
                set old (_tgt_cred_get_active $scenario 2>/dev/null)
                if test -z "$old"
                    echo "tgt cred rename: no active credential. Specify <old> <new>." >&2
                    return 1
                end
                set new $rest[1]
            else
                echo "Usage: tgt cred rename [<old>] <new>" >&2
                return 1
            end
            if test "$old" = "$new"
                echo "tgt cred rename: same name, nothing to do" >&2
                return 1
            end
            if not _tgt_cred_validate_name $new
                echo "tgt cred rename: invalid name '$new' (allowed: A-Z a-z 0-9 _ -)" >&2
                return 1
            end
            if not _tgt_cred_exists $scenario $old
                echo "tgt cred rename: credential '$old' does not exist" >&2
                return 1
            end
            if _tgt_cred_exists $scenario $new
                echo "tgt cred rename: credential '$new' already exists" >&2
                return 1
            end

            set -l old_file (_tgt_cred_file $scenario $old)
            set -l new_file (_tgt_cred_file $scenario $new)
            if not command mv -- $old_file $new_file
                echo "tgt cred rename: failed to move registry file" >&2
                return 1
            end

            set -l active (_tgt_cred_get_active $scenario 2>/dev/null)
            if test "$active" = "$old"
                _tgt_cred_set_active $scenario $new
                if set -q TGT_SCENARIO; and test "$TGT_SCENARIO" = "$scenario"
                    and set -q TGT_CRED_NAME; and test "$TGT_CRED_NAME" = "$old"
                    _tgt_export TGT_CRED_NAME $new
                end
            end

            set_color green; echo "✓ renamed credential '$old' → '$new'"; set_color normal
            return 0

        case rm
            set -l alias $rest[1]
            if test -z "$alias"
                set -l aliases (_tgt_cred_list $scenario)
                if test (count $aliases) -eq 0
                    echo "tgt cred rm: no credentials in scenario '$scenario'" >&2
                    return 1
                end
                set alias (_tgt_pick "credential to remove" $aliases)
                test -z "$alias"; and return 1
            end
            if not _tgt_cred_exists $scenario $alias
                echo "tgt cred rm: credential '$alias' does not exist in scenario '$scenario'" >&2
                return 1
            end
            _tgt_cred_destroy $scenario $alias
            # Clear active marker + current-shell runtime if this
            # was the active credential.
            set -l active (_tgt_cred_get_active $scenario 2>/dev/null)
            if test "$active" = "$alias"
                _tgt_cred_clear_active $scenario
                _tgt_cred_clear_runtime
            end
            set_color green; echo "✓ credential '$alias' removed from '$scenario'"; set_color normal
            return 0

        case '*'
            echo "tgt cred: unknown subcommand '$verb'" >&2
            return 1
    end
end
