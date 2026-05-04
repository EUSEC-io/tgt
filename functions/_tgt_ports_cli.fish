# Dispatch for `tgt ports …` — port records on the active target.
#
#   tgt ports                              list + pick → set TGT_PORT
#   tgt ports list                         list, no picker
#   tgt ports add <file>                   import from nmap output
#   tgt ports add <port>[/<proto>] [svc] [comment]   manual add
#   tgt ports rm  <port>[/<proto>]
#   tgt ports clear
#   tgt ports comment <port>[/<proto>] <text>
#
# All operations require an active scenario AND target (the records
# live per-target).
function _tgt_ports_cli
    if not set -q TGT_SCENARIO; or not set -q TGT_ACTIVE
        echo "tgt ports: no active target — run `tgt switch <alias>` or `tgt new <alias>` first" >&2
        return 1
    end
    set -l scenario $TGT_SCENARIO
    set -l target $TGT_ACTIVE

    set -l verb $argv[1]
    set -l rest $argv[2..]

    switch $verb
        case '' list
            _tgt_ports_print_list $scenario $target
            test "$verb" = list; and return 0
            # No-arg form also drops into the picker.
            set -l choice (_tgt_ports_pick $scenario $target)
            test -z "$choice"; and return 0
            set -l parts (string split / -- $choice)
            test (count $parts) -lt 2; and return 1
            _tgt_export TGT_PORT $parts[1]
            set_color green
            echo "✓ TGT_PORT=$parts[1]  ($parts[1]/$parts[2])"
            set_color normal
            return 0

        case add
            test (count $rest) -ge 1; or begin
                echo "Usage: tgt ports add <file> | <port>[/<proto>] [service] [comment]" >&2
                return 1
            end
            # File path → import.
            if test -f $rest[1]
                set -l count (_tgt_ports_import $scenario $target $rest[1])
                or return $status
                set_color green
                echo "✓ imported $count port records into $scenario:$target"
                set_color normal
                return 0
            end
            # Manual add: port[/proto] [service] [comment].
            set -l spec $rest[1]
            set -l service ""
            set -l comment ""
            test (count $rest) -ge 2; and set service $rest[2]
            test (count $rest) -ge 3; and set comment $rest[3..]
            set -l port $spec
            set -l proto tcp
            if string match -q '*/*' -- $spec
                set -l parts (string split / -- $spec)
                set port $parts[1]
                set proto $parts[2]
            end
            if not _tgt_ports_validate_port $port
                echo "tgt ports add: invalid port '$port'" >&2
                return 1
            end
            if not _tgt_ports_validate_proto $proto
                echo "tgt ports add: invalid proto '$proto' (use tcp or udp)" >&2
                return 1
            end
            _tgt_ports_add $scenario $target $port $proto $service $comment
            or return $status
            set_color green
            echo "✓ added $port/$proto"
            set_color normal
            return 0

        case rm
            test (count $rest) -ge 1; or begin
                echo "Usage: tgt ports rm <port>[/<proto>]" >&2
                return 1
            end
            set -l spec $rest[1]
            set -l port $spec
            set -l proto tcp
            if string match -q '*/*' -- $spec
                set -l parts (string split / -- $spec)
                set port $parts[1]
                set proto $parts[2]
            end
            if not _tgt_ports_validate_port $port
                echo "tgt ports rm: invalid port '$port'" >&2
                return 1
            end
            if not _tgt_ports_validate_proto $proto
                echo "tgt ports rm: invalid proto '$proto' (use tcp or udp)" >&2
                return 1
            end
            _tgt_ports_remove $scenario $target $port $proto
            set_color green
            echo "✓ removed $port/$proto"
            set_color normal
            return 0

        case clear
            _tgt_ports_clear $scenario $target
            set_color green
            echo "✓ cleared all port records for $scenario:$target"
            set_color normal
            return 0

        case comment
            if test (count $rest) -lt 2
                echo "Usage: tgt ports comment <port>[/<proto>] <text>" >&2
                return 1
            end
            set -l spec $rest[1]
            set -l text $rest[2..]
            set -l port $spec
            set -l proto tcp
            if string match -q '*/*' -- $spec
                set -l parts (string split / -- $spec)
                set port $parts[1]
                set proto $parts[2]
            end
            if not _tgt_ports_validate_port $port
                echo "tgt ports comment: invalid port '$port'" >&2
                return 1
            end
            if not _tgt_ports_validate_proto $proto
                echo "tgt ports comment: invalid proto '$proto' (use tcp or udp)" >&2
                return 1
            end
            if not _tgt_ports_comment $scenario $target $port $proto $text
                echo "tgt ports comment: no record for $port/$proto (add it first with `tgt ports add $port/$proto`)" >&2
                return 1
            end
            set_color green
            echo "✓ comment set on $port/$proto"
            set_color normal
            return 0

        case '*'
            echo "tgt ports: unknown subcommand '$verb'" >&2
            return 1
    end
end
