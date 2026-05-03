source (status dirname)/helpers.fish

#
# _tgt_config_file: returns a path under $TGT_HOME.
#
_test_setup_home
@test "config_file: sits under TGT_HOME" \
    (_tgt_config_file) = "$TGT_HOME/config.fish"
_test_teardown

#
# _tgt_config_load: no-op when file is missing.
#
_test_setup_home
set -l rc (_tgt_config_load 2>/dev/null; echo $status)
@test "config_load (missing): exits 0" $rc -eq 0
@test "config_load (missing): doesn't create the file" \
    ! -e (_tgt_config_file)
_test_teardown

#
# _tgt_config_save round-trips with _tgt_config_load: write the
# current globals, clear them, source the file, see them back.
#
_test_setup_home
set -gx TGT_WORKSPACE_ROOT /tmp/saved
set -gx TGT_WORKSPACE_LAYOUT nested
set -gx TGT_WORKSPACE_AUTOCREATE 1
set -gx TGT_WORKSPACE_TARGET_TEMPLATE recon/ creds.txt
set -gx TGT_WORKSPACE_SCENARIO_TEMPLATE timeline.md

_tgt_config_save

# Erase the live globals so we're sure load is what restores them.
for v in TGT_WORKSPACE_ROOT TGT_WORKSPACE_LAYOUT TGT_WORKSPACE_AUTOCREATE TGT_WORKSPACE_TARGET_TEMPLATE TGT_WORKSPACE_SCENARIO_TEMPLATE
    set -eg $v
end

_tgt_config_load

@test "config_save+load: TGT_WORKSPACE_ROOT round-trips" \
    "$TGT_WORKSPACE_ROOT" = /tmp/saved
@test "config_save+load: TGT_WORKSPACE_LAYOUT round-trips" \
    "$TGT_WORKSPACE_LAYOUT" = nested
@test "config_save+load: TGT_WORKSPACE_AUTOCREATE round-trips" \
    "$TGT_WORKSPACE_AUTOCREATE" = 1
@test "config_save+load: TGT_WORKSPACE_TARGET_TEMPLATE has 2 entries" \
    (count $TGT_WORKSPACE_TARGET_TEMPLATE) -eq 2
@test "config_save+load: target template includes recon/" \
    (contains recon/ $TGT_WORKSPACE_TARGET_TEMPLATE; echo $status) -eq 0
@test "config_save+load: TGT_WORKSPACE_SCENARIO_TEMPLATE has 1 entry" \
    (count $TGT_WORKSPACE_SCENARIO_TEMPLATE) -eq 1
_test_teardown

#
# _tgt_config_save only writes vars that are currently set —
# unset vars don't appear in the file.
#
_test_setup_home
set -gx TGT_WORKSPACE_ROOT /tmp/only_root
# layout / autocreate / templates intentionally left unset

_tgt_config_save

set -l content (cat (_tgt_config_file) | string collect)
@test "config_save: writes TGT_WORKSPACE_ROOT" \
    (string match -rq 'TGT_WORKSPACE_ROOT' -- $content; echo $status) -eq 0
@test "config_save: omits unset TGT_WORKSPACE_LAYOUT" \
    (string match -rq 'TGT_WORKSPACE_LAYOUT' -- $content; echo $status) -ne 0
_test_teardown

#
# _tgt_config_migrate: no-op when file already exists.
#
_test_setup_home
echo "# placeholder" > (_tgt_config_file)
set -l mtime_before (stat -c %Y (_tgt_config_file))
sleep 1
_tgt_config_migrate
set -l mtime_after (stat -c %Y (_tgt_config_file))
@test "config_migrate (file exists): leaves the file untouched" \
    $mtime_before -eq $mtime_after
_test_teardown

#
# _tgt_config_migrate: no-op when no universals AND no file.
# (No safe way to test the actual migration path — that requires
# real universals which would pollute the user's fish_variables.)
#
_test_setup_home
_tgt_config_migrate
@test "config_migrate (no universals, no file): no file created" \
    ! -e (_tgt_config_file)
_test_teardown

#
# tgt config reset: deletes the config file when it exists.
#
_test_setup_home
echo "set -gx TGT_WORKSPACE_ROOT /tmp/x" > (_tgt_config_file)
@test "reset setup: file present" -e (_tgt_config_file)
_tgt_config_cli reset >/dev/null
@test "reset: file removed" ! -e (_tgt_config_file)
_test_teardown
