source (status dirname)/helpers.fish

#
# install (default → right): creates fish_right_prompt.fish with marker.
#
_test_setup_fishfn_dir
_tgt_prompt_cli install >/dev/null
set -l file "$TGT_FISH_FUNCTIONS_DIR/fish_right_prompt.fish"

@test "install default: writes fish_right_prompt.fish" \
    -e $file
@test "install default: file contains the managed marker" \
    (string match -rq '# tgt-prompt:managed' -- (cat $file); echo $status) -eq 0
@test "install default: file calls tgt_prompt" \
    (string match -rq 'tgt_prompt' -- (cat $file); echo $status) -eq 0
@test "install default: defines fish_right_prompt" \
    (string match -rq 'function fish_right_prompt' -- (cat $file); echo $status) -eq 0
_test_teardown

#
# install --left: writes fish_prompt.fish.
#
_test_setup_fishfn_dir
_tgt_prompt_cli install --left >/dev/null

@test "install --left: writes fish_prompt.fish" \
    -e "$TGT_FISH_FUNCTIONS_DIR/fish_prompt.fish"
@test "install --left: does NOT write fish_right_prompt.fish" \
    ! -e "$TGT_FISH_FUNCTIONS_DIR/fish_right_prompt.fish"
@test "install --left: defines fish_prompt" \
    (string match -rq 'function fish_prompt' -- (cat $TGT_FISH_FUNCTIONS_DIR/fish_prompt.fish); echo $status) -eq 0
_test_teardown

#
# install --right: explicit flag works the same as default.
#
_test_setup_fishfn_dir
_tgt_prompt_cli install --right >/dev/null

@test "install --right: writes fish_right_prompt.fish" \
    -e "$TGT_FISH_FUNCTIONS_DIR/fish_right_prompt.fish"
_test_teardown

#
# install --left --right: mutually exclusive, errors out.
#
_test_setup_fishfn_dir
set -l rc (_tgt_prompt_cli install --left --right >/dev/null 2>&1; echo $status)

@test "install --left --right: returns non-zero" \
    $rc -ne 0
@test "install --left --right: no file written" \
    ! -e "$TGT_FISH_FUNCTIONS_DIR/fish_right_prompt.fish"
_test_teardown

#
# install when our managed file already exists: idempotent no-op.
#
_test_setup_fishfn_dir
_tgt_prompt_cli install >/dev/null
set -l file "$TGT_FISH_FUNCTIONS_DIR/fish_right_prompt.fish"
set -l mtime_before (stat -c %Y $file)
sleep 1
set -l rc2 (_tgt_prompt_cli install >/dev/null 2>&1; echo $status)
set -l mtime_after (stat -c %Y $file)

@test "install (already managed): exits 0" \
    $rc2 -eq 0
@test "install (already managed): leaves file untouched" \
    $mtime_before -eq $mtime_after
_test_teardown

#
# install when a custom (non-managed) file exists: refuse, file untouched.
#
_test_setup_fishfn_dir
set -l file "$TGT_FISH_FUNCTIONS_DIR/fish_right_prompt.fish"
echo 'function fish_right_prompt; echo CUSTOM; end' > $file
set -l rc3 (_tgt_prompt_cli install >/dev/null 2>&1; echo $status)
set -l content (cat $file | string collect)

@test "install (custom file present): returns non-zero" \
    $rc3 -ne 0
@test "install (custom file present): leaves user content intact" \
    (string match -rq CUSTOM -- $content; echo $status) -eq 0
@test "install (custom file present): does not create backup" \
    ! -e "$file.tgt-bak"
_test_teardown

#
# install --force when custom file exists: backs up, overwrites.
#
_test_setup_fishfn_dir
set -l file "$TGT_FISH_FUNCTIONS_DIR/fish_right_prompt.fish"
echo 'function fish_right_prompt; echo CUSTOM; end' > $file
_tgt_prompt_cli install --force >/dev/null

@test "install --force: backup file exists" \
    -e "$file.tgt-bak"
@test "install --force: backup contains the original CUSTOM line" \
    (string match -rq CUSTOM -- (cat "$file.tgt-bak"); echo $status) -eq 0
@test "install --force: new file is managed" \
    (string match -rq '# tgt-prompt:managed' -- (cat $file); echo $status) -eq 0
_test_teardown

#
# uninstall removes the managed file but leaves backups alone.
#
_test_setup_fishfn_dir
set -l file "$TGT_FISH_FUNCTIONS_DIR/fish_right_prompt.fish"
echo 'function fish_right_prompt; echo CUSTOM; end' > $file
_tgt_prompt_cli install --force >/dev/null
_tgt_prompt_cli uninstall >/dev/null

@test "uninstall: managed file removed" \
    ! -e $file
@test "uninstall: backup preserved" \
    -e "$file.tgt-bak"
_test_teardown

#
# uninstall does NOT touch a non-managed (custom) file.
#
_test_setup_fishfn_dir
set -l file "$TGT_FISH_FUNCTIONS_DIR/fish_right_prompt.fish"
echo 'function fish_right_prompt; echo CUSTOM; end' > $file
_tgt_prompt_cli uninstall >/dev/null

@test "uninstall (custom file present): leaves the user's file intact" \
    -e $file
@test "uninstall (custom file present): file content unchanged" \
    (string match -rq CUSTOM -- (cat $file); echo $status) -eq 0
_test_teardown

#
# uninstall when nothing installed: clean exit, message about nothing-to-do.
#
_test_setup_fishfn_dir
set -l rc4 (_tgt_prompt_cli uninstall >/dev/null 2>&1; echo $status)

@test "uninstall (nothing installed): exits 0" \
    $rc4 -eq 0
_test_teardown

#
# status: not installed.
#
_test_setup_fishfn_dir
set -l out (_tgt_prompt_cli status 2>&1 | string collect)

@test "status (clean): mentions not installed" \
    (string match -rq 'not installed' -- $out; echo $status) -eq 0
_test_teardown

#
# status: managed.
#
_test_setup_fishfn_dir
_tgt_prompt_cli install --left >/dev/null
set -l out2 (_tgt_prompt_cli status 2>&1 | string collect)

@test "status (managed): says 'managed by tgt'" \
    (string match -rq 'managed by tgt' -- $out2; echo $status) -eq 0
_test_teardown

#
# status: custom file (not ours).
#
_test_setup_fishfn_dir
echo 'function fish_prompt; echo X; end' > "$TGT_FISH_FUNCTIONS_DIR/fish_prompt.fish"
set -l out3 (_tgt_prompt_cli status 2>&1 | string collect)

@test "status (custom): notes custom, not managed" \
    (string match -rq 'not managed by tgt' -- $out3; echo $status) -eq 0
_test_teardown

#
# unknown subcommand: errors and points to --help.
#
_test_setup_fishfn_dir
set -l rc5 (_tgt_prompt_cli bogus >/dev/null 2>&1; echo $status)

@test "unknown subcommand: returns non-zero" \
    $rc5 -ne 0
_test_teardown

#
# Dispatcher integration: `tgt prompt install` reaches _tgt_prompt_cli.
#
_test_setup_fishfn_dir
_test_setup_home
tgt prompt install >/dev/null

@test "dispatcher: tgt prompt install creates fish_right_prompt.fish" \
    -e "$TGT_FISH_FUNCTIONS_DIR/fish_right_prompt.fish"
_test_teardown
