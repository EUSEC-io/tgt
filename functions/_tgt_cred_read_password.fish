# Read just the stored password for a credential. Thin convenience
# wrapper around `_tgt_cred_read_fields` for callers that only need
# that one field (e.g. `tgt cred list --show-passwords`).
function _tgt_cred_read_password --argument-names scenario alias
    set -l line (_tgt_cred_read_fields $scenario $alias)
    or return 1
    set -l fields (string split \t -- $line)
    echo $fields[2]
end
