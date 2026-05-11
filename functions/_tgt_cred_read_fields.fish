# Read a credential entry's raw fields (including the password
# value) and emit them tab-separated, one line:
#
#   username\tpassword\tdomain\tnotes
#
# Unlike `_tgt_cred_inspect` (which redacts the password to Y/N for
# the listing view), this returns the actual stored value — used by
# `tgt cred show` and by `tgt cred list --show-passwords`. Call
# sites are responsible for not leaking the value where it doesn't
# belong.
function _tgt_cred_read_fields --argument-names scenario alias
    set -l file (_tgt_cred_file $scenario $alias)
    test -f $file; or return 1

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

    printf '%s\t%s\t%s\t%s\n' $username $password $domain $notes
end
