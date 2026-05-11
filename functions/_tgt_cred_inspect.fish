# Read a credential entry and emit a tab-separated state line
# WITHOUT loading anything into the current shell:
#
#   alias\tusername\thas_password(Y/N)\tdomain\tnotes
#
# `notes` is truncated to 30 chars in this view (the show command
# renders the full text). `has_password` is "Y" when a password
# field is stored, regardless of its content (hashes also count).
function _tgt_cred_inspect --argument-names scenario alias
    set -l file (_tgt_cred_file $scenario $alias)
    test -f $file; or return 1

    set -l username ""
    set -l has_password N
    set -l domain ""
    set -l notes ""
    while read -l line
        set -l m (string match -r '^_tgt_export\s+(\S+)\s+(.*)$' -- $line)
        test (count $m) -lt 3; and continue
        switch $m[2]
            case TGT_CRED_USERNAME
                set username $m[3]
            case TGT_CRED_PASSWORD
                test -n "$m[3]"; and set has_password Y
            case TGT_CRED_DOMAIN
                set domain $m[3]
            case TGT_CRED_NOTES
                set notes $m[3]
        end
    end < $file

    # Truncate notes for the listing view.
    if test (string length -- $notes) -gt 30
        set notes (string sub --length 27 -- $notes)"..."
    end

    test -z "$username"; and set username "—"
    test -z "$domain"  ; and set domain "—"
    test -z "$notes"   ; and set notes "—"

    printf '%s\t%s\t%s\t%s\t%s\n' $alias $username $has_password $domain $notes
end
