# Interactive editor for an existing credential entry. Prompts
# mirror the new wizard but each field's current value is the
# default — empty input keeps it, `!` clears it (on optional
# fields). For password, the helper's `<KEEP>` sentinel handles
# the "leave unchanged" case.
#
# After save: if the edited cred is the scenario's active one,
# reloads env vars. Otherwise restores whichever cred was active
# (preserves the runtime around the edit).
function _tgt_cred_edit_wizard --argument-names scenario alias
    if not _tgt_cred_exists $scenario $alias
        echo "tgt cred edit: credential '$alias' does not exist in scenario '$scenario'" >&2
        return 1
    end

    # Read current values without polluting the shell.
    set -l cur_username ""
    set -l cur_password ""
    set -l cur_domain ""
    set -l cur_notes ""
    set -l file (_tgt_cred_file $scenario $alias)
    while read -l line
        set -l m (string match -r '^_tgt_export\s+(\S+)\s+(.*)$' -- $line)
        test (count $m) -lt 3; and continue
        # `_tgt_cred_save` runs each value through `string escape`,
        # so reverse it here. Otherwise the wizard re-saves the
        # escaped form on every "keep" cycle, accumulating wrapping
        # layers until the value collapses to junk (e.g. a value
        # with a space gets wrapped in single quotes, those quotes
        # get re-escaped as `"'"` next cycle, and so on).
        set -l val (string unescape -- $m[3])
        switch $m[2]
            case TGT_CRED_USERNAME
                set cur_username $val
            case TGT_CRED_PASSWORD
                set cur_password $val
            case TGT_CRED_DOMAIN
                set cur_domain $val
            case TGT_CRED_NOTES
                set cur_notes $val
        end
    end < $file

    set -l username (_tgt_ask_text "Username (required)" $cur_username)
    if test -z "$username"
        echo "tgt cred edit: username is required" >&2
        return 1
    end

    set -l has_pw no
    test -n "$cur_password"; and set has_pw yes
    set -l pw_input (_tgt_ask_password "Password / hash" $has_pw)
    if test $status -ne 0
        set_color brblack; echo "  cancelled."; set_color normal
        return 1
    end
    set -l password
    switch $pw_input
        case "<KEEP>"
            set password $cur_password
        case ""
            # Either user has no password and typed nothing, or they
            # explicitly cleared with `!`. Either way, no password.
            set password ""
        case '*'
            set password $pw_input
    end

    set -l domain (_tgt_ask_text_optional "Domain (optional)" $cur_domain)
    set -l notes  (_tgt_ask_text_optional "Notes (optional)" $cur_notes)

    # Clear staging slots first so blanked answers actually drop
    # the corresponding TGT_CRED_* line instead of inheriting old
    # state from a previously-active credential.
    for v in TGT_CRED_USERNAME TGT_CRED_PASSWORD TGT_CRED_DOMAIN TGT_CRED_NOTES
        set -q $v; and _tgt_unexport $v
    end
    set -gx TGT_CRED_USERNAME $username
    test -n "$password"; and set -gx TGT_CRED_PASSWORD $password
    test -n "$domain"  ; and set -gx TGT_CRED_DOMAIN $domain
    test -n "$notes"   ; and set -gx TGT_CRED_NOTES $notes

    _tgt_cred_save $scenario $alias
    or return $status

    # Rebuild runtime around the active cred for the scenario.
    set -l active (_tgt_cred_get_active $scenario 2>/dev/null)
    _tgt_cred_clear_runtime
    if test -n "$active"
        _tgt_cred_load $scenario $active
    end

    set_color green; echo "✓ credential '$alias' updated in '$scenario'"; set_color normal
end
