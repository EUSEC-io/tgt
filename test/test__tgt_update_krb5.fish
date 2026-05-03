source (status dirname)/helpers.fish

#
# Adds a realm block when [realms] section exists.
#
_test_setup_krb5 one_realm.conf
set -gx TGT_AD_DOMAIN dante.local
set -gx TGT_DC DC01.dante.local
_tgt_update_krb5 >/dev/null
set -l after (cat $TGT_KRB5_FILE)
set -l has_dante (string match -rq "DANTE.LOCAL\s*=" -- $after; echo $status)
set -l has_kdc (string match -rq "kdc = DC01.dante.local" -- $after; echo $status)
@test "_tgt_update_krb5: adds new realm block to existing [realms]" $has_dante -eq 0
@test "_tgt_update_krb5: KDC line carries the right host" $has_kdc -eq 0
_test_teardown

#
# Creates the [realms] section when it doesn't exist.
#
_test_setup_krb5 empty.conf
set -gx TGT_AD_DOMAIN htb.local
set -gx TGT_DC DC01.htb.local
_tgt_update_krb5 >/dev/null
set -l after (cat $TGT_KRB5_FILE)
set -l has_realms_header (string match -rq "^\[realms\]" -- $after; echo $status)
set -l has_htb (string match -rq "HTB.LOCAL\s*=" -- $after; echo $status)
@test "_tgt_update_krb5: creates [realms] section when missing" $has_realms_header -eq 0
@test "_tgt_update_krb5: adds the realm block in the new [realms]" $has_htb -eq 0
_test_teardown

#
# default_realm follows the active target.
#
_test_setup_krb5 two_realms.conf
set -gx TGT_AD_DOMAIN switched.local
set -gx TGT_DC DC01.switched.local
_tgt_update_krb5 >/dev/null
set -l after (cat $TGT_KRB5_FILE)
set -l default_line (string match -r "default_realm\s*=\s*\S+" -- $after)
@test "_tgt_update_krb5: default_realm rewritten to the new realm" \
    "$default_line" = "default_realm = SWITCHED.LOCAL"
_test_teardown

#
# Replacing an existing realm: the old block is removed via _tgt_clean_krb5
# and the new one added — no duplicates.
#
_test_setup_krb5 two_realms.conf
set -gx TGT_AD_DOMAIN dante.local
set -gx TGT_DC DC02.dante.local      # changed from DC01
_tgt_update_krb5 >/dev/null
set -l after (cat $TGT_KRB5_FILE)
set -l dante_count (string match -ar "DANTE.LOCAL\s*=" -- $after | count)
set -l has_new_kdc (string match -rq "kdc = DC02.dante.local" -- $after; echo $status)
set -l has_old_kdc (string match -rq "kdc = DC01.DANTE.LOCAL" -- $after; echo $status)
@test "_tgt_update_krb5: no duplicate realm blocks after rewrite" $dante_count -eq 1
@test "_tgt_update_krb5: new KDC is present" $has_new_kdc -eq 0
@test "_tgt_update_krb5: old KDC is gone" $has_old_kdc -ne 0
_test_teardown

#
# Falls back to TGT as KDC when TGT_DC is not set.
#
_test_setup_krb5 empty.conf
set -gx TGT_AD_DOMAIN fallback.local
set -gx TGT 10.10.10.5
_tgt_update_krb5 >/dev/null
set -l after (cat $TGT_KRB5_FILE)
set -l has_ip_kdc (string match -rq "kdc = 10.10.10.5" -- $after; echo $status)
@test "_tgt_update_krb5: uses TGT as KDC when TGT_DC unset" $has_ip_kdc -eq 0
_test_teardown

#
# No-op when TGT_AD_DOMAIN is not set.
#
_test_setup_krb5 one_realm.conf
set -l before_md5 (md5sum $TGT_KRB5_FILE | string split " ")[1]
_tgt_update_krb5 >/dev/null
set -l after_md5 (md5sum $TGT_KRB5_FILE | string split " ")[1]
@test "_tgt_update_krb5: no-op when TGT_AD_DOMAIN unset" "$before_md5" = "$after_md5"
_test_teardown

#
# No-op when neither TGT nor TGT_DC is set.
#
_test_setup_krb5 one_realm.conf
set -gx TGT_AD_DOMAIN orphan.local
set -l before_md5 (md5sum $TGT_KRB5_FILE | string split " ")[1]
_tgt_update_krb5 >/dev/null
set -l after_md5 (md5sum $TGT_KRB5_FILE | string split " ")[1]
@test "_tgt_update_krb5: no-op when neither TGT nor TGT_DC set" "$before_md5" = "$after_md5"
_test_teardown
