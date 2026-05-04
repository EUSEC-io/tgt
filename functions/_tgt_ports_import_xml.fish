# Parse an nmap XML (`-oX`) file and upsert each open port into the
# target's records. Pure-fish, no xmllint dependency.
#
# We walk line-by-line and accumulate state between <port …> and
# </port>. Single-line port elements work too: the same line carries
# the open tag, <state>, <service>, and </port>, and the state
# machine still flushes correctly on the same iteration.
#
# Recognized states: anything starting with "open" (covers `open` and
# the common `open|filtered` for UDP). Service is captured from the
# <service name="…"> attribute; product/version are ignored.
#
# Echoes the count of imported records on stdout; non-zero exit on
# missing file or bad target.
function _tgt_ports_import_xml --argument-names scenario target file
    _tgt_target_exists $scenario $target; or return 1
    test -f $file; or return 1

    set -l in_port 0
    set -l portid ""
    set -l proto ""
    set -l state ""
    set -l service ""
    set -l count 0

    while read -l line
        if string match -q '*<port *' -- $line
            set in_port 1
            set portid ""
            set proto ""
            set state ""
            set service ""
            set -l m (string match -r 'portid="([^"]+)"' -- $line)
            test (count $m) -ge 2; and set portid $m[2]
            set m (string match -r 'protocol="([^"]+)"' -- $line)
            test (count $m) -ge 2; and set proto $m[2]
        end
        test $in_port -eq 1; or continue

        if string match -q '*<state *' -- $line
            set -l m (string match -r 'state="([^"]+)"' -- $line)
            test (count $m) -ge 2; and set state $m[2]
        end
        if string match -q '*<service *' -- $line
            set -l m (string match -r 'name="([^"]+)"' -- $line)
            test (count $m) -ge 2; and set service $m[2]
        end

        if string match -q '*</port>*' -- $line
            if string match -rq '^open' -- $state
                and _tgt_ports_validate_port $portid
                and _tgt_ports_validate_proto $proto
                _tgt_ports_add $scenario $target $portid $proto $service ""
                and set count (math $count + 1)
            end
            set in_port 0
        end
    end < $file
    echo $count
end
