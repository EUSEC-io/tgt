# Detect the format of an nmap output file. Echoes "gnmap", "xml",
# or "nmap" on stdout; non-zero exit + empty stdout on failure.
#
# Extension wins when unambiguous (.gnmap/.xml/.nmap); otherwise we
# sniff the first few lines. Sniff order: xml first (cheap to spot
# via "<?xml"), then gnmap (Host:/Ports: lines are unmistakable),
# then normal nmap as the loose fallback.
#
# Currently only gnmap parsing is implemented; xml + nmap detect
# returns the format name so callers can produce a "format detected
# but not yet supported" error.
function _tgt_ports_detect_format --argument-names file
    test -f $file; or return 1

    string match -q '*.gnmap' -- $file; and echo gnmap; and return 0
    string match -q '*.xml' -- $file; and echo xml; and return 0
    string match -q '*.nmap' -- $file; and echo nmap; and return 0

    # Read up to 30 lines so we still catch headers buried under
    # comments without slurping a huge xml file.
    set -l head
    set -l n 0
    while read -l line
        set -a head $line
        set n (math $n + 1)
        test $n -ge 30; and break
    end < $file

    for line in $head
        if string match -rq '^<\?xml' -- $line; or string match -rq '^<nmaprun' -- $line
            echo xml
            return 0
        end
    end
    for line in $head
        if string match -rq '^Host:.*Ports:' -- $line
            echo gnmap
            return 0
        end
    end
    for line in $head
        if string match -rq '^# Nmap' -- $line; or string match -rq '^Nmap scan report for' -- $line
            echo nmap
            return 0
        end
    end
    return 1
end
