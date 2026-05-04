#!/usr/bin/env fish
# Demo: `tgt ports` — import nmap output, list with common-port
# highlighting, add manual records, set a comment.
source (status dirname)/_baseline.fish

_tgt_scenario_cli new htb-Forest >/dev/null
set -gx TGT 10.10.10.161
_tgt_target_cli new forest --no-edit >/dev/null

# Stage a small gnmap fixture inline so the demo doesn't depend on
# the test/ tree.
set -l gnmap (mktemp).gnmap
echo '# Nmap 7.94SVN scan of 10.10.10.161
Host: 10.10.10.161 ()	Ports: 53/open/tcp//domain//, 88/open/tcp//kerberos-sec//, 389/open/tcp//ldap//, 445/open/tcp//microsoft-ds//, 8080/open/tcp//http-proxy//	Ignored State: closed (995)' > $gnmap

_p "tgt ports add $gnmap"
tgt ports add $gnmap
sleep 4

_p "tgt ports list"
tgt ports list
sleep 5

_p "tgt ports add 31337/tcp suspicious 'caught with manual recon'"
tgt ports add 31337/tcp suspicious 'caught with manual recon'
sleep 3

_p "tgt ports comment 445/tcp 'SMB - signing not required'"
tgt ports comment 445/tcp 'SMB - signing not required'
sleep 3

_p "tgt ports list"
tgt ports list
sleep 6

command rm -f -- $gnmap
_demo_cleanup
