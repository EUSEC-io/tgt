source (status dirname)/helpers.fish

# ── _tgt_scenario_sanitize_name ────────────────────────────────

@test "sanitize: already-clean name passes through" \
    (_tgt_scenario_sanitize_name lame) = lame

@test "sanitize: uppercase → lowercase" \
    (_tgt_scenario_sanitize_name FOREST) = forest

@test "sanitize: dots replaced with dashes" \
    (_tgt_scenario_sanitize_name "active.htb") = active-htb

@test "sanitize: spaces replaced" \
    (_tgt_scenario_sanitize_name "Box Name") = box-name

@test "sanitize: collapses multiple dashes" \
    (_tgt_scenario_sanitize_name "a..b") = a-b

@test "sanitize: trims leading/trailing dashes" \
    (_tgt_scenario_sanitize_name ".bashrc") = bashrc

@test "sanitize: returns 'unnamed' for nothing usable" \
    (_tgt_scenario_sanitize_name "...") = unnamed

@test "sanitize: empty input → unnamed" \
    (_tgt_scenario_sanitize_name "") = unnamed

@test "sanitize: preserves underscores" \
    (_tgt_scenario_sanitize_name "active_htb") = active_htb

# ── _tgt_scenario_import: dry-run ──────────────────────────────

#
# --dry-run: enumerates without touching anything.
#
_test_setup_home
_test_setup_workspace
set -l src (mktemp -d)
mkdir -p $src/lame $src/forest

_tgt_scenario_import --dry-run --prefix htb- $src >/dev/null

@test "import --dry-run: source still present" \
    -d "$src/lame"
@test "import --dry-run: workspace untouched" \
    ! -d "$TGT_WORKSPACE_ROOT/htb-lame"
@test "import --dry-run: no scenario registered" \
    (_tgt_scenario_exists htb-lame; echo $status) -ne 0

rm -rf $src
_test_teardown

# ── _tgt_scenario_import: real move ────────────────────────────

#
# Default action moves dirs and registers scenarios with the prefix.
#
_test_setup_home
_test_setup_workspace
set -l src2 (mktemp -d)
mkdir -p $src2/lame $src2/forest
echo placeholder > $src2/lame/notes.txt

_tgt_scenario_import --prefix htb- $src2 >/dev/null

@test "import: scenarios registered (htb-lame)" \
    (_tgt_scenario_exists htb-lame; echo $status) -eq 0
@test "import: scenarios registered (htb-forest)" \
    (_tgt_scenario_exists htb-forest; echo $status) -eq 0
@test "import: workspace dirs created" \
    -d "$TGT_WORKSPACE_ROOT/htb-lame"
@test "import: source dirs gone (moved)" \
    ! -d "$src2/lame"
@test "import: file content preserved across move" \
    (cat $TGT_WORKSPACE_ROOT/htb-lame/notes.txt) = placeholder

rm -rf $src2
_test_teardown

# ── _tgt_scenario_import: --copy ───────────────────────────────

#
# --copy keeps the source intact.
#
_test_setup_home
_test_setup_workspace
set -l src3 (mktemp -d)
mkdir -p $src3/lame
echo data > $src3/lame/file

_tgt_scenario_import --copy --prefix htb- $src3 >/dev/null

@test "import --copy: source still present" \
    -d "$src3/lame"
@test "import --copy: workspace populated" \
    -d "$TGT_WORKSPACE_ROOT/htb-lame"
@test "import --copy: file copied" \
    (cat $TGT_WORKSPACE_ROOT/htb-lame/file) = data

rm -rf $src3
_test_teardown

# ── _tgt_scenario_import: name sanitization ────────────────────

#
# Names with invalid chars are sanitized; conflicts are skipped.
#
_test_setup_home
_test_setup_workspace
set -l src4 (mktemp -d)
mkdir -p "$src4/Active.htb" $src4/Forest

_tgt_scenario_import --prefix htb- $src4 >/dev/null

@test "import: 'Active.htb' → 'htb-active-htb'" \
    (_tgt_scenario_exists htb-active-htb; echo $status) -eq 0
@test "import: workspace dir uses sanitized name" \
    -d "$TGT_WORKSPACE_ROOT/htb-active-htb"
@test "import: capitalized 'Forest' → 'htb-forest'" \
    (_tgt_scenario_exists htb-forest; echo $status) -eq 0

rm -rf $src4
_test_teardown

# ── _tgt_scenario_import: skip conflicts ───────────────────────

#
# When a scenario already exists, the directory is skipped (not
# clobbered).
#
_test_setup_home
_test_setup_workspace
_tgt_scenario_cli new htb-lame >/dev/null
set -l src5 (mktemp -d)
mkdir -p $src5/lame
echo new > $src5/lame/file

_tgt_scenario_import --prefix htb- $src5 >/dev/null

@test "import (conflict): source not moved" \
    -d "$src5/lame"
@test "import (conflict): workspace dest not created" \
    ! -d "$TGT_WORKSPACE_ROOT/htb-lame"

rm -rf $src5
_test_teardown

# ── _tgt_scenario_import: bad input ────────────────────────────

#
# Missing path argument → error.
#
_test_setup_home
_test_setup_workspace
set -l rc (_tgt_scenario_import 2>/dev/null; echo $status)
@test "import: no path → non-zero" $rc -ne 0
_test_teardown

#
# Path is not a directory → error.
#
_test_setup_home
_test_setup_workspace
set -l f (mktemp)
set -l rc2 (_tgt_scenario_import $f 2>/dev/null; echo $status)
@test "import: non-directory path → non-zero" $rc2 -ne 0
rm -f $f
_test_teardown
