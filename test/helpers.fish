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

function _test_setup_fishfn_dir
    set -gx TGT_TEST_MODE 1
    set -gx TGT_FISH_FUNCTIONS_DIR (mktemp -d)
end

function _test_setup_workspace
    set -gx TGT_TEST_MODE 1
    set -gx TGT_WORKSPACE_ROOT (mktemp -d)
end

function _test_teardown
    # Clean up tempfiles / dirs (only check global; universals are
    # the user's real config and must not be touched).
    set -qg TGT_KRB5_FILE; and rm -f $TGT_KRB5_FILE
    set -qg TGT_HOSTS_FILE; and rm -f $TGT_HOSTS_FILE
    set -qg TGT_HOME; and rm -rf $TGT_HOME
    set -qg TGT_FISH_FUNCTIONS_DIR; and rm -rf $TGT_FISH_FUNCTIONS_DIR
    set -qg TGT_WORKSPACE_ROOT; and rm -rf $TGT_WORKSPACE_ROOT
    # Erase ONLY global-scope copies. `set -e` without a scope flag
    # would fall back to the universal scope when no global exists,
    # which would obliterate the user's `tgt config` settings.
    for v in TGT_TEST_MODE TGT_KRB5_FILE TGT_HOSTS_FILE TGT_HOME TGT_FISH_FUNCTIONS_DIR \
             TGT_WORKSPACE_ROOT TGT_WORKSPACE_LAYOUT TGT_WORKSPACE_AUTOCREATE \
             TGT_WORKSPACE_TARGET_TEMPLATE TGT_WORKSPACE_SCENARIO_TEMPLATE \
             TGT TGT_PORT TGT_USERNAME TGT_PASSWORD TGT_AD_DOMAIN TGT_DC TGT_HOSTS \
             TGT_SCENARIO TGT_ACTIVE
        set -qg $v; and set -eg $v
    end
end
