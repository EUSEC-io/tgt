#!/usr/bin/env fish
# Demo: bulk-import a directory of existing HTB box notes as
# scenarios with a `htb-` prefix.
source (status dirname)/_baseline.fish

set -l fake (mktemp -d)
mkdir -p $fake/Forest $fake/Lame $fake/CCTV $fake/Active.htb

_p "ls ~/HTB/machines/"
ls $fake
sleep 3

_p "tgt scenario import ~/HTB/machines --prefix htb- --dry-run"
tgt scenario import $fake --prefix htb- --dry-run
sleep 4

_p "tgt scenario import ~/HTB/machines --prefix htb-"
tgt scenario import $fake --prefix htb-
sleep 4

_p "tgt scenario list"
tgt scenario list
sleep 5

command rm -rf -- $fake
_demo_cleanup
