#!/usr/bin/env fish
# Demo: bulk-import a directory of existing HTB box notes as
# scenarios with a `htb-` prefix.
#
# Run via `make demo` (which records under asciinema). Standalone:
#   fish demos/import.fish

# ── Isolated sandbox ──
set -gx TGT_TEST_MODE 1
set -gx TGT_HOME (mktemp -d)
set -gx TGT_WORKSPACE_ROOT (mktemp -d)
set -gx TGT_HOSTS_FILE (mktemp)
set -gx TGT_KRB5_FILE (mktemp)

set -l fake (mktemp -d)
mkdir -p $fake/Forest $fake/Lame $fake/CCTV $fake/Active.htb

# Helper: print a fake prompt + sleep before output.
function _p
    set_color cyan
    echo -n "smp86\$ "
    set_color normal
    echo $argv
    sleep 0.6
end

_p "ls ~/HTB/machines/"
ls $fake
sleep 1.4

_p "tgt scenario import ~/HTB/machines --prefix htb- --dry-run"
tgt scenario import $fake --prefix htb- --dry-run
sleep 2

_p "tgt scenario import ~/HTB/machines --prefix htb-"
tgt scenario import $fake --prefix htb-
sleep 2

_p "tgt scenario list"
tgt scenario list
sleep 2.5

# ── Cleanup ──
command rm -rf -- $fake $TGT_HOME $TGT_WORKSPACE_ROOT
command rm -f -- $TGT_HOSTS_FILE $TGT_KRB5_FILE
