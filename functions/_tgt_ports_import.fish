# Auto-detect an nmap file's format and dispatch to the right parser.
# gnmap and xml are supported; normal nmap text returns a "use the
# .gnmap output instead" error since that format is too brittle to
# parse reliably (column alignment shifts with terminal width).
#
# Echoes the imported-record count on success; writes a one-line
# error to stderr on failure.
function _tgt_ports_import --argument-names scenario target file
    if not test -f $file
        echo "tgt ports add: '$file' is not a file" >&2
        return 1
    end

    set -l fmt (_tgt_ports_detect_format $file)
    if test -z "$fmt"
        echo "tgt ports add: could not detect nmap format for '$file' (expected gnmap, xml, or nmap)" >&2
        return 1
    end

    switch $fmt
        case gnmap
            _tgt_ports_import_gnmap $scenario $target $file
        case xml
            _tgt_ports_import_xml $scenario $target $file
        case nmap
            echo "tgt ports add: normal nmap text format isn't supported — pass the .gnmap or .xml output instead" >&2
            return 1
        case '*'
            echo "tgt ports add: unknown format '$fmt'" >&2
            return 1
    end
end
