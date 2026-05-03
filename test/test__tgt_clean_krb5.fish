source (status dirname)/helpers.fish

#
# Removes only the named realm, leaves others intact.
#
_test_setup_krb5 two_realms.conf
_tgt_clean_krb5 DANTE.LOCAL
set -l after (cat $TGT_KRB5_FILE)
set -l has_dante (string match -rq "DANTE.LOCAL\s*=" -- $after; echo $status)
set -l has_other (string match -rq "OTHER.LOCAL\s*=" -- $after; echo $status)
@test "_tgt_clean_krb5: removes the named realm block" $has_dante -ne 0
@test "_tgt_clean_krb5: preserves other realm blocks" $has_other -eq 0
_test_teardown

#
# No-op when realm isn't present.
#
_test_setup_krb5 one_realm.conf
set -l before_md5 (md5sum $TGT_KRB5_FILE | string split " ")[1]
_tgt_clean_krb5 NEVER.SEEN
set -l after_md5 (md5sum $TGT_KRB5_FILE | string split " ")[1]
@test "_tgt_clean_krb5: is a no-op when realm absent" "$before_md5" = "$after_md5"
_test_teardown

#
# Removes the only realm cleanly when it's the named one.
#
_test_setup_krb5 one_realm.conf
_tgt_clean_krb5 HTB.LOCAL
set -l after (cat $TGT_KRB5_FILE)
set -l has_htb (string match -rq "HTB.LOCAL\s*=" -- $after; echo $status)
@test "_tgt_clean_krb5: removes the only realm block when it matches" $has_htb -ne 0
_test_teardown

#
# Preserves file structure: line count drops by exactly the realm-block size.
#
_test_setup_krb5 two_realms.conf
set -l before_lines (count (cat $TGT_KRB5_FILE))
_tgt_clean_krb5 DANTE.LOCAL
set -l after_lines (count (cat $TGT_KRB5_FILE))
# DANTE.LOCAL block is 3 lines (opener + kdc + closer), plus a leading newline.
@test "_tgt_clean_krb5: line count drops by 3 (realm block)" \
    (math $before_lines - $after_lines) -eq 3
@test "_tgt_clean_krb5: first line still [libdefaults]" \
    (cat $TGT_KRB5_FILE)[1] = "[libdefaults]"
_test_teardown

#
# Doesn't run sudo in test mode (verified by file ownership staying with the user).
#
_test_setup_krb5 two_realms.conf
set -l owner_before (stat -c '%U' $TGT_KRB5_FILE)
_tgt_clean_krb5 DANTE.LOCAL
set -l owner_after (stat -c '%U' $TGT_KRB5_FILE)
@test "_tgt_clean_krb5: runs sudoless in test mode (no ownership change)" "$owner_before" = "$owner_after"
_test_teardown
