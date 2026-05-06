source (status dirname)/helpers.fish

# `complete -C` emits "completion\tdescription" lines. Helper that
# returns just the names, one per line.
function _complete_names
    complete -C $argv | string replace -r '\t.*$' ''
end

#
# Top-level subcommands surface on a bare `tgt `.
#
set -l names (_complete_names 'tgt ')
@test "top-level: scenario offered" \
    (contains scenario $names; echo $status) -eq 0
@test "top-level: switch offered" \
    (contains switch $names; echo $status) -eq 0
@test "top-level: cd offered" \
    (contains cd $names; echo $status) -eq 0
@test "top-level: path offered" \
    (contains path $names; echo $status) -eq 0
@test "top-level: workspace offered" \
    (contains workspace $names; echo $status) -eq 0
@test "top-level: prompt offered" \
    (contains prompt $names; echo $status) -eq 0
@test "top-level: ports offered" \
    (contains ports $names; echo $status) -eq 0

#
# `tgt ports <TAB>` offers ports verbs.
#
set -l names_ports (_complete_names 'tgt ports ')
@test "ports: offers list" \
    (contains list $names_ports; echo $status) -eq 0
@test "ports: offers add" \
    (contains add $names_ports; echo $status) -eq 0
@test "ports: offers rm" \
    (contains rm $names_ports; echo $status) -eq 0
@test "ports: offers clear" \
    (contains clear $names_ports; echo $status) -eq 0
@test "ports: offers comment" \
    (contains comment $names_ports; echo $status) -eq 0
@test "ports: offers unset" \
    (contains unset $names_ports; echo $status) -eq 0

#
# `tgt dc <TAB>` offers dc verbs.
#
set -l names_dc (_complete_names 'tgt dc ')
@test "dc: offers list" \
    (contains list $names_dc; echo $status) -eq 0
@test "dc: offers show" \
    (contains show $names_dc; echo $status) -eq 0
@test "dc: offers rm" \
    (contains rm $names_dc; echo $status) -eq 0
@test "dc: offers new" \
    (contains new $names_dc; echo $status) -eq 0
@test "dc: offers switch" \
    (contains switch $names_dc; echo $status) -eq 0
@test "dc: offers unset" \
    (contains unset $names_dc; echo $status) -eq 0
@test "dc: offers edit" \
    (contains edit $names_dc; echo $status) -eq 0
@test "dc: offers rename" \
    (contains rename $names_dc; echo $status) -eq 0

#
# `tgt dc new -<TAB>` offers domain/realm/kdc/admin flags.
#
set -l names_dc_new (_complete_names 'tgt dc new -')
@test "dc new: --domain offered" \
    (contains -- --domain $names_dc_new; echo $status) -eq 0
@test "dc new: --realm offered" \
    (contains -- --realm $names_dc_new; echo $status) -eq 0
@test "dc new: --kdc-host offered" \
    (contains -- --kdc-host $names_dc_new; echo $status) -eq 0
@test "dc new: --kdc-ip offered" \
    (contains -- --kdc-ip $names_dc_new; echo $status) -eq 0
@test "dc new: --admin-host offered" \
    (contains -- --admin-host $names_dc_new; echo $status) -eq 0
@test "dc new: --admin-ip offered" \
    (contains -- --admin-ip $names_dc_new; echo $status) -eq 0

#
# Top-level offers `dc`.
#
@test "top-level: dc offered" \
    (contains dc $names; echo $status) -eq 0
@test "top-level: show offered" \
    (contains show $names; echo $status) -eq 0
@test "top-level: revoke offered" \
    (contains revoke $names; echo $status) -eq 0
set -l names_dash (_complete_names 'tgt -')
@test "top-level: --revoke offered after dash" \
    (contains -- --revoke $names_dash; echo $status) -eq 0
@test "top-level: --show offered after dash" \
    (contains -- --show $names_dash; echo $status) -eq 0

#
# After choosing a top-level subcommand, the same name shouldn't
# appear again as a candidate (no "tgt scenario scenario").
#
set -l names_after_scenario (_complete_names 'tgt scenario ')
@test "after 'tgt scenario': top-level commands not re-offered" \
    (contains scenario $names_after_scenario; echo $status) -ne 0

#
# `tgt scenario <TAB>` offers scenario verbs.
#
@test "scenario: offers new" \
    (contains new $names_after_scenario; echo $status) -eq 0
@test "scenario: offers list" \
    (contains list $names_after_scenario; echo $status) -eq 0
@test "scenario: offers switch" \
    (contains switch $names_after_scenario; echo $status) -eq 0
@test "scenario: offers rm" \
    (contains rm $names_after_scenario; echo $status) -eq 0

#
# `tgt prompt <TAB>` offers prompt verbs.
#
set -l names_prompt (_complete_names 'tgt prompt ')
@test "prompt: offers install" \
    (contains install $names_prompt; echo $status) -eq 0
@test "prompt: offers uninstall" \
    (contains uninstall $names_prompt; echo $status) -eq 0
@test "prompt: offers status" \
    (contains status $names_prompt; echo $status) -eq 0

#
# `tgt prompt install <TAB>` offers the slot/force flags.
#
set -l names_install (_complete_names 'tgt prompt install -')
@test "prompt install: --right offered" \
    (contains -- --right $names_install; echo $status) -eq 0
@test "prompt install: --left offered" \
    (contains -- --left $names_install; echo $status) -eq 0
@test "prompt install: --force offered" \
    (contains -- --force $names_install; echo $status) -eq 0

#
# `tgt rm -` (top-level rm) offers --purge-workspace.
#
set -l names_rm (_complete_names 'tgt rm -')
@test "rm: --purge-workspace offered" \
    (contains -- --purge-workspace $names_rm; echo $status) -eq 0

#
# `tgt cd -` offers --scenario.
#
set -l names_cd (_complete_names 'tgt cd -')
@test "cd: --scenario offered" \
    (contains -- --scenario $names_cd; echo $status) -eq 0

#
# Dynamic scenario list — `tgt scenario switch <TAB>` lists scenarios
# from the registry.
#
_test_setup_home
_tgt_scenario_cli new dante >/dev/null
_tgt_scenario_cli new acme  >/dev/null
set -l ssn_names (_complete_names 'tgt scenario switch ')
@test "scenario switch: lists 'dante'" \
    (contains dante $ssn_names; echo $status) -eq 0
@test "scenario switch: lists 'acme'" \
    (contains acme $ssn_names; echo $status) -eq 0
_test_teardown

#
# Dynamic target list — `tgt switch <TAB>` lists targets in active
# scenario only.
#
_test_setup_home
_test_setup_hosts empty.txt
_tgt_scenario_cli new dante >/dev/null
_tgt_target_cli new web01 >/dev/null
_tgt_target_cli new dc01  >/dev/null
_tgt_scenario_cli new acme >/dev/null
_tgt_target_cli new api    >/dev/null

# Active scenario is now 'acme' — only its targets should complete.
set -l switch_names (_complete_names 'tgt switch ')
@test "switch (acme active): lists 'api'" \
    (contains api $switch_names; echo $status) -eq 0
@test "switch (acme active): does NOT list 'web01' (other scenario)" \
    (contains web01 $switch_names; echo $status) -ne 0

# Switch to dante and verify isolation flips.
_tgt_export TGT_SCENARIO dante
set -l switch_names2 (_complete_names 'tgt switch ')
@test "switch (dante active): lists 'web01'" \
    (contains web01 $switch_names2; echo $status) -eq 0
@test "switch (dante active): lists 'dc01'" \
    (contains dc01 $switch_names2; echo $status) -eq 0
@test "switch (dante active): does NOT list 'api'" \
    (contains api $switch_names2; echo $status) -ne 0
_test_teardown

#
# `tgt dc rm <TAB>` lists only DC aliases — target aliases must NOT
# bleed in even though `rm` is also a target verb.
#
_test_setup_home
_test_setup_hosts empty.txt
_tgt_scenario_cli new dante >/dev/null
_tgt_target_cli new web01 --no-edit >/dev/null
tgt dc new dcX --domain dante.local --kdc-ip 10.10.10.5 >/dev/null
set -l dc_rm_names (_complete_names 'tgt dc rm ')
@test "dc rm completion: lists 'dcX' (DC alias)" \
    (contains dcX $dc_rm_names; echo $status) -eq 0
@test "dc rm completion: does NOT bleed in 'web01' (target alias)" \
    (contains web01 $dc_rm_names; echo $status) -ne 0
@test "dc switch completion: only DC aliases too" \
    (contains web01 (_complete_names 'tgt dc switch '); echo $status) -ne 0
@test "dc edit completion: only DC aliases too" \
    (contains web01 (_complete_names 'tgt dc edit '); echo $status) -ne 0

# Inverse: `tgt rm <TAB>` (top-level target rm) lists only targets,
# not DCs.
set -l tgt_rm_names (_complete_names 'tgt rm ')
@test "tgt rm completion: lists 'web01'" \
    (contains web01 $tgt_rm_names; echo $status) -eq 0
@test "tgt rm completion: does NOT include 'dcX' (DC alias)" \
    (contains dcX $tgt_rm_names; echo $status) -ne 0

# Same for `tgt ports rm <TAB>` — target aliases must not appear.
set -l ports_rm_names (_complete_names 'tgt ports rm ')
@test "ports rm completion: does NOT include 'web01'" \
    (contains web01 $ports_rm_names; echo $status) -ne 0
_test_teardown
