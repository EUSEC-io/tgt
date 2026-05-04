# Auto-detect an nmap file's format and dispatch to the right parser.
# Currently gnmap is the only supported format; xml/nmap return a
# "format detected but not yet supported" error pointing at the
# expected next-step command.
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
            echo "tgt ports add: xml import not implemented yet — pass the .gnmap output instead" >&2
            return 1
        case nmap
            echo "tgt ports add: normal nmap text format isn't supported — pass the .gnmap output instead" >&2
            return 1
        case '*'
            echo "tgt ports add: unknown format '$fmt'" >&2
            return 1
    end
end
