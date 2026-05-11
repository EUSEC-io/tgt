# Interactive wizard for `tgt cred new`. Asks for the username
# first so the alias prompt can default to it when the username
# happens to be a valid alias (the common ASCII case). After
# collection, stages TGT_CRED_* env vars and delegates to
# `_tgt_cred_finalize_new` (save → auto-activate).
function _tgt_cred_wizard --argument-names scenario init_alias
    set -l username (_tgt_ask_text "Username (required)" "")
    if test -z "$username"
        echo "tgt cred new: username is required" >&2
        return 1
    end

    set -l alias $init_alias
    if test -z "$alias"
        # Suggest the username as the alias when it's filename-safe;
        # otherwise leave the suggestion blank (Chinese / UTF-16
        # Windows usernames still work as the username field, but the
        # alias has to be ASCII-safe because it becomes a filename).
        set -l default_alias ""
        _tgt_cred_validate_name $username; and set default_alias $username
        set alias (_tgt_ask_text "Credential alias (e.g. admin, svc-sql)" $default_alias)
        if test $status -ne 0; or test -z "$alias"
            set_color brblack; echo "  cancelled."; set_color normal
            return 1
        end
    end
    if not _tgt_cred_validate_name $alias
        echo "tgt cred new: invalid alias '$alias' (allowed: A-Z a-z 0-9 _ - .; can't start with .)" >&2
        return 1
    end
    if _tgt_cred_exists $scenario $alias
        echo "tgt cred new: credential '$alias' already exists in scenario '$scenario'" >&2
        return 1
    end

    # Password — plaintext OR a hash like aad3b...:31d6c... in the
    # same field. The `_tgt_ask_password` helper handles the
    # "Enter to skip" semantics for has_current=no (skip = empty).
    set -l password (_tgt_ask_password "Password / hash (optional)" no)
    if test $status -ne 0
        set_color brblack; echo "  cancelled."; set_color normal
        return 1
    end
    test "$password" = "<KEEP>"; and set password ""

    set -l domain (_tgt_ask_text "Domain (optional)" "")
    set -l notes  (_tgt_ask_text "Notes (optional)" "")

    _tgt_cred_clear_runtime
    set -gx TGT_CRED_USERNAME $username
    test -n "$password" ; and set -gx TGT_CRED_PASSWORD $password
    test -n "$domain"   ; and set -gx TGT_CRED_DOMAIN $domain
    test -n "$notes"    ; and set -gx TGT_CRED_NOTES $notes

    _tgt_cred_finalize_new $scenario $alias
    or return $status

    set_color green; echo "✓ credential '$alias' created in '$scenario' and activated"; set_color normal
end
