# Parse an nmap greppable (`-oG`) file and upsert each open port into
# the target's records.
#
# gnmap line format (one host per line, tab-separated columns):
#   Host: <ip> (<hostname>)\tPorts: <entry>, <entry>, ...\tIgnored State: ...
#
# Each port entry is slash-separated:
#   <port>/<state>/<proto>/<owner>/<service>/<rpc>/<version>/<extra>
#
# We ingest entries whose state starts with "open" — that covers
# `open` and the common UDP `open|filtered`. Service is captured;
# the version field is ignored (often noisy and better written
# manually as a `tgt ports comment`).
#
# Echoes the count of imported records on stdout; non-zero exit on
# missing file or bad target.
function _tgt_ports_import_gnmap --argument-names scenario target file
    _tgt_target_exists $scenario $target; or return 1
    test -f $file; or return 1

    set -l count 0
    while read -l line
        string match -rq '^Host:.*Ports:' -- $line; or continue
        # Drop everything up to "Ports: " and trim a trailing
        # "\tIgnored State:..." segment if present.
        set -l section (string replace -r '^.*Ports: ' '' -- $line)
        set section (string replace -r '\tIgnored.*$' '' -- $section)

        for entry in (string split ', ' -- $section)
            set -l fields (string split '/' -- $entry)
            test (count $fields) -ge 5; or continue
            string match -rq '^open' -- $fields[2]; or continue
            set -l port $fields[1]
            set -l proto $fields[3]
            set -l service $fields[5]
            _tgt_ports_validate_port $port; or continue
            _tgt_ports_validate_proto $proto; or continue
            _tgt_ports_add $scenario $target $port $proto $service ""
            and set count (math $count + 1)
        end
    end < $file
    echo $count
end
