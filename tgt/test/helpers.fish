# Shared setup/teardown helpers for tgt's test suite.
#
# Tests source this file at the top:
#   source (status dirname)/helpers.fish
#
# Then call _test_setup_krb5 / _test_setup_hosts / _test_teardown
# around each scenario.

set -g _test_dir (status dirname)

function _test_setup_krb5 --argument-names fixture
    set -gx TGT_TEST_MODE 1
    set -gx TGT_KRB5_FILE (mktemp)
    cat $_test_dir/fixtures/krb5/$fixture > $TGT_KRB5_FILE
end

function _test_setup_hosts --argument-names fixture
    set -gx TGT_TEST_MODE 1
    set -gx TGT_HOSTS_FILE (mktemp)
    cat $_test_dir/fixtures/hosts/$fixture > $TGT_HOSTS_FILE
end

function _test_setup_home
    set -gx TGT_TEST_MODE 1
    set -gx TGT_HOME (mktemp -d)
end

function _test_teardown
    set -q TGT_KRB5_FILE; and rm -f $TGT_KRB5_FILE
    set -q TGT_HOSTS_FILE; and rm -f $TGT_HOSTS_FILE
    set -q TGT_HOME; and rm -rf $TGT_HOME
    set -e TGT_TEST_MODE TGT_KRB5_FILE TGT_HOSTS_FILE TGT_HOME
    # Also clear any tgt env vars a test set, to keep cases independent.
    for v in TGT TGT_PORT TGT_USERNAME TGT_PASSWORD TGT_AD_DOMAIN TGT_DC TGT_HOSTS TGT_SCENARIO TGT_ACTIVE
        set -q $v; and set -e $v
    end
end
