# Dispatch for `tgt cred …` — per-scenario credential entries.
#
#   tgt cred                       list + pick → set active (switch)
#   tgt cred list [--show-passwords]
#                                  list — by default the password column
#                                  reads `pw:Y/N`; with the flag the actual
#                                  value is rendered (handy when you want
#                                  to copy-paste, dangerous when others can
#                                  see your screen).
#   tgt cred show [alias]          detailed view (no arg → fzf picker). The
#                                  password is shown — you asked for it.
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
            argparse --name='tgt cred list' 'show-passwords' -- $rest
            or return 1
            set -l aliases (_tgt_cred_list $scenario)
            if test (count $aliases) -eq 0
                echo "(no credentials recorded for $scenario)"
                return 0
            end
            set_color --bold
            printf '  %-12s %-20s  %-20s  %-20s %s\n' \
                alias username password domain notes
            set_color normal
            set -l active (_tgt_cred_get_active $scenario 2>/dev/null)
            for a in $aliases
                set -l line (_tgt_cred_inspect $scenario $a)
                set -l fields (string split \t -- $line)
                # alias  username  has_password(Y/N)  domain  notes
                set -l pw_cell "pw:$fields[3]"
                if set -q _flag_show_passwords
                    set pw_cell (_tgt_cred_read_password $scenario $a)
                    test -z "$pw_cell"; and set pw_cell "—"
                end
                set -l marker "  "
                test "$a" = "$active"; and set marker "* "
                printf '%s' $marker
                test "$a" = "$active"; and set_color --bold green
                printf '%-12s %-20s  %-20s  %-20s %s\n' \
                    $fields[1] $fields[2] $pw_cell $fields[4] $fields[5]
                test "$a" = "$active"; and set_color normal
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
            set -l alias $rest[1]
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
            set -l line (_tgt_cred_read_fields $scenario $alias)
            set -l fields (string split \t -- $line)
            set -l username $fields[1]
            set -l password $fields[2]
            set -l domain   $fields[3]
            set -l notes    $fields[4]
            set_color brblack; printf '  alias:    '; set_color normal; echo $alias
            set_color brblack; printf '  username: '; set_color normal; echo $username
            set_color brblack; printf '  password: '; set_color normal
            if test -z "$password"
                set_color brblack; echo "(not set)"; set_color normal
            else
                set_color red; echo $password; set_color normal
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
            # Flag-driven non-interactive edit when ANY of --username
            # --password --domain --notes is given; falls through to
            # the wizard when none is. Empty flag value clears that
            # field; absent flag preserves the current value.
            argparse --name='tgt cred edit' \
                'u/username=' 'p/password=' 'd/domain=' 'n/notes=' \
                -- $rest
            or return 1

            set -l alias ""
            test (count $argv) -ge 1; and set alias $argv[1]
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

            set -l any_flag 0
            for f in _flag_username _flag_password _flag_domain _flag_notes
                set -q $f; and set any_flag 1; and break
            end
            if test $any_flag -eq 0
                _tgt_cred_edit_wizard $scenario $alias
                return $status
            end

            # Read current values via the canonical helper.
            set -l line (_tgt_cred_read_fields $scenario $alias)
            set -l fields (string split \t -- $line)
            set -l new_username $fields[1]
            set -l new_password $fields[2]
            set -l new_domain   $fields[3]
            set -l new_notes    $fields[4]
            set -q _flag_username; and set new_username $_flag_username
            set -q _flag_password; and set new_password $_flag_password
            set -q _flag_domain;   and set new_domain   $_flag_domain
            set -q _flag_notes;    and set new_notes    $_flag_notes

            if test -z "$new_username"
                echo "tgt cred edit: username cannot be empty" >&2
                return 1
            end

            # Stage into env vars then save — same dance the wizard
            # does so empty values actually drop the corresponding
            # _tgt_export line on disk.
            for v in TGT_CRED_USERNAME TGT_CRED_PASSWORD TGT_CRED_DOMAIN TGT_CRED_NOTES
                set -q $v; and _tgt_unexport $v
            end
            set -gx TGT_CRED_USERNAME $new_username
            test -n "$new_password"; and set -gx TGT_CRED_PASSWORD $new_password
            test -n "$new_domain"  ; and set -gx TGT_CRED_DOMAIN $new_domain
            test -n "$new_notes"   ; and set -gx TGT_CRED_NOTES $new_notes

            _tgt_cred_save $scenario $alias
            or return $status

            # Restore runtime around whichever cred is currently
            # active — staging above wiped TGT_CRED_*.
            set -l active (_tgt_cred_get_active $scenario 2>/dev/null)
            _tgt_cred_clear_runtime
            if test -n "$active"
                _tgt_cred_load $scenario $active
            end

            set_color green; echo "✓ credential '$alias' updated in '$scenario'"; set_color normal
            return 0

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
