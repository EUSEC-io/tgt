# Read a target's registry file and echo the uppercase Kerberos realm
# (TGT_AD_DOMAIN, uppercased) without loading it into the current
# shell. Echoes nothing if the file has no AD domain. Returns 0 in
# all normal cases; non-zero only on a missing file.
function _tgt_target_ad_realm --argument-names scenario alias
    set -l file (_tgt_target_file $scenario $alias)
    test -f $file; or return 1
    while read -l line
        set -l m (string match -r '^_tgt_export\s+TGT_AD_DOMAIN\s+(.*)$' -- $line)
        test (count $m) -ge 2; or continue
        echo (string upper -- $m[2])
        return 0
    end < $file
    return 0
end
