source (status dirname)/helpers.fish

#
# detect_format: extension wins.
#
_test_setup_home
@test "detect_format: .gnmap → gnmap" \
    (_tgt_ports_detect_format $_test_dir/fixtures/nmap/forest.gnmap) = gnmap
@test "detect_format: .xml → xml" \
    (_tgt_ports_detect_format $_test_dir/fixtures/nmap/sample.xml) = xml
_test_teardown

#
# detect_format: content sniff when extension is unknown.
#
_test_setup_home
set -l tmp (mktemp).out
cat $_test_dir/fixtures/nmap/forest.gnmap > $tmp
@test "detect_format: gnmap content sniffed via Host:/Ports:" \
    (_tgt_ports_detect_format $tmp) = gnmap
rm -f $tmp

set -l tmp (mktemp).out
cat $_test_dir/fixtures/nmap/sample.xml > $tmp
@test "detect_format: xml content sniffed via <?xml" \
    (_tgt_ports_detect_format $tmp) = xml
rm -f $tmp
_test_teardown

#
# detect_format: missing file → non-zero.
#
_test_setup_home
@test "detect_format: missing file → non-zero" \
    (_tgt_ports_detect_format /nonexistent/path; echo $status) -ne 0
_test_teardown

#
# detect_format: garbage file → non-zero.
#
_test_setup_home
set -l tmp (mktemp)
echo "this is just text" > $tmp
@test "detect_format: unrecognized content → non-zero" \
    (_tgt_ports_detect_format $tmp; echo $status) -ne 0
rm -f $tmp
_test_teardown

#
# import_gnmap: parses forest fixture into 12 records.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT 10.10.10.161
_tgt_target_save dante forest
set -l count (_tgt_ports_import_gnmap dante forest $_test_dir/fixtures/nmap/forest.gnmap)
@test "import_gnmap: returns 12 imported records" "$count" = 12
set -l lines (_tgt_ports_list dante forest)
@test "import_gnmap: 12 records on disk" (count $lines) -eq 12
@test "import_gnmap: 53/tcp present" \
    (string match -q '53*tcp*domain*' -- $lines[1]; echo $status) -eq 0
@test "import_gnmap: 445/tcp present" \
    (string match -q '*445*tcp*microsoft-ds*' -- (_tgt_ports_list dante forest); echo $status) -eq 0
@test "import_gnmap: 5985/tcp present" \
    (string match -q '*5985*tcp*http*' -- (_tgt_ports_list dante forest); echo $status) -eq 0
_test_teardown

#
# import_gnmap: skips closed ports, accepts open|filtered.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT 10.10.10.5
_tgt_target_save dante box
_tgt_ports_import_gnmap dante box $_test_dir/fixtures/nmap/udp-mixed.gnmap >/dev/null
set -l lines (_tgt_ports_list dante box)
@test "import_gnmap (udp): 4 records (closed dropped)" (count $lines) -eq 4
@test "import_gnmap (udp): 53/udp kept (state=open)" \
    (string match -q '*53*udp*domain*' -- (_tgt_ports_list dante box); echo $status) -eq 0
@test "import_gnmap (udp): 137/udp kept (state=open|filtered)" \
    (string match -q '*137*udp*netbios-ns*' -- (_tgt_ports_list dante box); echo $status) -eq 0
@test "import_gnmap (udp): 161/udp dropped (state=closed)" \
    (string match -q '*161*udp*' -- (_tgt_ports_list dante box); echo $status) -ne 0
_test_teardown

#
# import_gnmap: multi-host fixture — every entry imports (we don't
# filter by IP, we trust the user pointed the file at the right
# target).
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_save dante box
set -l count (_tgt_ports_import_gnmap dante box $_test_dir/fixtures/nmap/multihost.gnmap)
@test "import_gnmap (multi-host): 4 records" "$count" = 4
@test "import_gnmap (multi-host): 22/tcp present" \
    (string match -q '*22*tcp*ssh*' -- (_tgt_ports_list dante box); echo $status) -eq 0
@test "import_gnmap (multi-host): 3389/tcp present" \
    (string match -q '*3389*tcp*ms-wbt-server*' -- (_tgt_ports_list dante box); echo $status) -eq 0
_test_teardown

#
# import_gnmap: re-import upserts (no duplicates).
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT 10.10.10.161
_tgt_target_save dante forest
_tgt_ports_import_gnmap dante forest $_test_dir/fixtures/nmap/forest.gnmap >/dev/null
_tgt_ports_import_gnmap dante forest $_test_dir/fixtures/nmap/forest.gnmap >/dev/null
@test "import_gnmap: re-import keeps 12 (no dupes)" \
    (_tgt_ports_list dante forest | count) -eq 12
_test_teardown

#
# import_gnmap: existing manual record is preserved when the import
# doesn't touch the same port+proto.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT 10.10.10.5
_tgt_target_save dante box
_tgt_ports_add dante box 31337 tcp backdoor "found via manual recon"
_tgt_ports_import_gnmap dante box $_test_dir/fixtures/nmap/multihost.gnmap >/dev/null
@test "import_gnmap: manual 31337/tcp record preserved" \
    (string match -q '*31337*backdoor*found via manual recon*' -- (_tgt_ports_list dante box); echo $status) -eq 0
_test_teardown

#
# import (dispatcher): gnmap path returns the count.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT 10.10.10.5
_tgt_target_save dante box
set -l count (_tgt_ports_import dante box $_test_dir/fixtures/nmap/multihost.gnmap)
@test "import: dispatches gnmap correctly" "$count" = 4
_test_teardown

#
# import_xml: parses sample fixture (2 open tcp ports).
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_save dante box
set -l count (_tgt_ports_import_xml dante box $_test_dir/fixtures/nmap/sample.xml)
@test "import_xml: returns 2 imported records" "$count" = 2
@test "import_xml: 22/tcp present" \
    (string match -q '*22*tcp*ssh*' -- (_tgt_ports_list dante box); echo $status) -eq 0
@test "import_xml: 80/tcp present" \
    (string match -q '*80*tcp*http*' -- (_tgt_ports_list dante box); echo $status) -eq 0
_test_teardown

#
# import_xml: forest fixture — drops closed, accepts open|filtered,
# captures udp records.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT 10.10.10.161
_tgt_target_save dante forest
set -l count (_tgt_ports_import_xml dante forest $_test_dir/fixtures/nmap/forest.xml)
@test "import_xml (forest): 5 imported (closed dropped)" "$count" = 5
set -l recs (_tgt_ports_list dante forest)
@test "import_xml (forest): 6 records on disk would have included closed" \
    (count $recs) -eq 5
@test "import_xml (forest): 53/tcp domain captured" \
    (string match -q '*53*tcp*domain*' -- $recs; echo $status) -eq 0
@test "import_xml (forest): 137/udp open|filtered kept" \
    (string match -q '*137*udp*netbios-ns*' -- $recs; echo $status) -eq 0
@test "import_xml (forest): 999/tcp closed dropped" \
    (string match -q '*999*' -- $recs; echo $status) -ne 0
_test_teardown

#
# import (dispatcher): xml path now imports successfully.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_save dante box
set -l count (_tgt_ports_import dante box $_test_dir/fixtures/nmap/sample.xml)
@test "import: xml dispatch returns 2" "$count" = 2
_test_teardown

#
# import (dispatcher): missing file → non-zero.
#
_test_setup_home
_tgt_scenario_create dante >/dev/null
set -gx TGT 1.1.1.1
_tgt_target_save dante box
@test "import: missing file → non-zero" \
    (_tgt_ports_import dante box /nonexistent.gnmap 2>/dev/null; echo $status) -ne 0
_test_teardown
