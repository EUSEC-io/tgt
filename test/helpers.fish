# Shared setup/teardown helpers for tgt's test suite.
#
# Tests source this file at the top:
#   source (status dirname)/helpers.fish
#
# Then call _test_setup_krb5 / _test_setup_hosts / _test_teardown
# around each scenario.

set -g _test_dir (status dirname)

# Vars the test suite expects to start unset. Any of these set in
# the calling shell (global or universal) would leak into tests
# that assert "default / unset" state.
set -g _tgt_test_isolated_vars \
    TGT TGT_PORT TGT_USERNAME TGT_PASSWORD TGT_HOSTS \
    TGT_DC TGT_DC_NAME TGT_DC_DOMAIN TGT_DC_REALM \
    TGT_DC_HOST TGT_DC_IP TGT_DC_ADMIN_HOST TGT_DC_ADMIN_IP \
    TGT_SCENARIO TGT_ACTIVE \
    TGT_WORKSPACE_ROOT TGT_WORKSPACE_LAYOUT TGT_WORKSPACE_AUTOCREATE \
    TGT_WORKSPACE_TARGET_TEMPLATE TGT_WORKSPACE_SCENARIO_TEMPLATE

# Per-test-file: erase any inherited globals.
for _v in $_tgt_test_isolated_vars
    set -qg $_v; and set -eg $_v
end
set -e _v

# One-shot per fishtape session: snapshot any universals that real
# `tgt` use leaves behind (TGT_SCENARIO / TGT_ACTIVE / etc.), erase
# them so tests see a clean shell, and register a fish_exit handler
# to restore them when the test process ends. The sentinel keeps
# repeated `source helpers.fish` from re-snapshotting an already-
# emptied state.
if not set -q __tgt_test_universals_isolated
    set -gx __tgt_test_universals_isolated 1
    set -g _tgt_test_snapshot_keys
    set -g _tgt_test_snapshot_vals
    for _v in $_tgt_test_isolated_vars
        set -qU $_v; or continue
        set -a _tgt_test_snapshot_keys $_v
        # Encode list values as space-joined for portability —
        # restore re-splits. Empty universals get an empty token.
        set -a _tgt_test_snapshot_vals (string join \x1f -- $$_v)
    end
    for _v in $_tgt_test_isolated_vars
        set -qU $_v; and set -eU $_v
    end
    set -e _v

    function __tgt_test_restore_universals --on-event fish_exit
        for i in (seq (count $_tgt_test_snapshot_keys))
            set -l items (string split \x1f -- $_tgt_test_snapshot_vals[$i])
            set -Ux $_tgt_test_snapshot_keys[$i] $items
        end
    end
end

function _test_setup_krb5 --argument-names fixture
    set -gx TGT_TEST_MODE 1
    # Free a previously-allocated tmpfile (e.g. from _test_setup_home)
    # before claiming a new one for this fixture.
    set -qg TGT_KRB5_FILE; and rm -f $TGT_KRB5_FILE
    set -gx TGT_KRB5_FILE (mktemp)
    cat $_test_dir/fixtures/krb5/$fixture > $TGT_KRB5_FILE
end

function _test_setup_hosts --argument-names fixture
    set -gx TGT_TEST_MODE 1
    # Free a previously-allocated tmpfile (e.g. from _test_setup_home)
    # before claiming a new one for this fixture.
    set -qg TGT_HOSTS_FILE; and rm -f $TGT_HOSTS_FILE
    set -gx TGT_HOSTS_FILE (mktemp)
    cat $_test_dir/fixtures/hosts/$fixture > $TGT_HOSTS_FILE
end

function _test_setup_home
    set -gx TGT_TEST_MODE 1
    set -gx TGT_HOME (mktemp -d)
    # `tgt scenario new`/`switch` now hot-swap /etc/hosts and
    # /etc/krb5.conf, so any test that creates a scenario implicitly
    # writes to whatever `_tgt_hosts_file` / `_tgt_krb5_file` resolve
    # to. Sandbox both unless the caller has already pinned a
    # fixture-backed file.
    set -qg TGT_HOSTS_FILE; or set -gx TGT_HOSTS_FILE (mktemp)
    set -qg TGT_KRB5_FILE;  or set -gx TGT_KRB5_FILE (mktemp)
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
             TGT TGT_PORT TGT_USERNAME TGT_PASSWORD TGT_HOSTS \
             TGT_DC TGT_DC_NAME TGT_DC_DOMAIN TGT_DC_REALM \
             TGT_DC_HOST TGT_DC_IP TGT_DC_ADMIN_HOST TGT_DC_ADMIN_IP \
             TGT_ASK_QUEUE \
             TGT_SCENARIO TGT_ACTIVE
        set -qg $v; and set -eg $v
    end
end
