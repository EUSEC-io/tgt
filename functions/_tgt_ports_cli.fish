# Dispatch for `tgt ports …` — port records on a target.
#
#   tgt ports                                      list + pick → set TGT_PORT
#   tgt ports list  [--target <t>]                 list, no picker
#   tgt ports add   [--target <t>] <file>          import from nmap output
#   tgt ports add   [--target <t>] <port>[/<proto>] [svc] [comment]   manual add
#   tgt ports rm    [--target <t>] <port>[/<proto>]
#   tgt ports clear [--target <t>]
#   tgt ports unset                                clear $TGT_PORT (records kept)
#   tgt ports comment [--target <t>] <port>[/<proto>] <text>
#   tgt ports service [--target <t>] <port>[/<proto>] <name>   rename service
#
# `--target <alias>` lets you operate on a non-active target. Without
# it, `$TGT_ACTIVE` is used (the historical default). The interactive
# picker form (`tgt ports` with no args) stays active-target-only —
# it sets TGT_PORT in the current shell, which only makes sense for
# the active target.
function _tgt_ports_cli
    if not set -q TGT_SCENARIO
        echo "tgt ports: no active scenario — run `tgt scenario new <name>` or `tgt scenario switch <name>` first" >&2
        return 1
    end
    set -l scenario $TGT_SCENARIO
    # Default target = currently-active. Each subcommand can
    # override via --target.
    set -l default_target ""
    set -q TGT_ACTIVE; and set default_target $TGT_ACTIVE

    set -l verb $argv[1]
    set -l rest $argv[2..]

    # Helper: resolve the effective target for this invocation.
    # Sets the caller's $effective_target. Errors + returns non-zero
    # when neither --target nor TGT_ACTIVE provides one.
    # (fish doesn't have output-parameter idioms; this is a plain
    # function that prints the resolved alias or empty.)
    function _tgt_ports_cli__resolve_target --no-scope-shadowing
        # Args: verb, flag-target (may be empty), default
        set -l verb $argv[1]
        set -l flag_target $argv[2]
        set -l default_target $argv[3]
        set -l resolved $default_target
        test -n "$flag_target"; and set resolved $flag_target
        if test -z "$resolved"
            echo "tgt ports $verb: no active target — run `tgt switch <alias>` first or pass --target <alias>" >&2
            return 1
        end
        echo $resolved
    end

    switch $verb
        case list
            argparse --name='tgt ports list' 't/target=' -- $rest
            or return 1
            set -l flag_target ""
            set -q _flag_target; and set flag_target $_flag_target
            set -l target (_tgt_ports_cli__resolve_target list "$flag_target" "$default_target")
            or return $status
            if not _tgt_target_exists $scenario $target
                echo "tgt ports list: target '$target' does not exist in scenario '$scenario'" >&2
                return 1
            end
            _tgt_ports_print_list $scenario $target
            return 0

        case ''
            # Interactive picker stays active-target-only — sets
            # TGT_PORT in the current shell.
            if test -z "$default_target"
                echo "tgt ports: no active target — run `tgt switch <alias>` first" >&2
                return 1
            end
            set -l target $default_target
            set -l records (_tgt_ports_list $scenario $target)
            if test (count $records) -eq 0
                _tgt_ports_print_list $scenario $target
                return 0
            end
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
            argparse --name='tgt ports add' 't/target=' -- $rest
            or return 1
            set -l flag_target ""
            set -q _flag_target; and set flag_target $_flag_target
            set -l target (_tgt_ports_cli__resolve_target add "$flag_target" "$default_target")
            or return $status
            if not _tgt_target_exists $scenario $target
                echo "tgt ports add: target '$target' does not exist in scenario '$scenario'" >&2
                return 1
            end
            test (count $argv) -ge 1; or begin
                echo "Usage: tgt ports add [--target <t>] <file> | <port>[/<proto>] [service] [comment]" >&2
                return 1
            end
            # File path → import.
            if test -f $argv[1]
                set -l count (_tgt_ports_import $scenario $target $argv[1])
                or return $status
                set_color green
                echo "✓ imported $count port records into $scenario:$target"
                set_color normal
                return 0
            end
            # Manual add: port[/proto] [service] [comment].
            set -l spec $argv[1]
            set -l service ""
            set -l comment ""
            test (count $argv) -ge 2; and set service $argv[2]
            test (count $argv) -ge 3; and set comment $argv[3..]
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
            echo "✓ added $port/$proto to $scenario:$target"
            set_color normal
            return 0

        case rm
            argparse --name='tgt ports rm' 't/target=' -- $rest
            or return 1
            set -l flag_target ""
            set -q _flag_target; and set flag_target $_flag_target
            set -l target (_tgt_ports_cli__resolve_target rm "$flag_target" "$default_target")
            or return $status
            if not _tgt_target_exists $scenario $target
                echo "tgt ports rm: target '$target' does not exist in scenario '$scenario'" >&2
                return 1
            end
            test (count $argv) -ge 1; or begin
                echo "Usage: tgt ports rm [--target <t>] <port>[/<proto>]" >&2
                return 1
            end
            set -l spec $argv[1]
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
            echo "✓ removed $port/$proto from $scenario:$target"
            set_color normal
            return 0

        case clear
            argparse --name='tgt ports clear' 't/target=' -- $rest
            or return 1
            set -l flag_target ""
            set -q _flag_target; and set flag_target $_flag_target
            set -l target (_tgt_ports_cli__resolve_target clear "$flag_target" "$default_target")
            or return $status
            if not _tgt_target_exists $scenario $target
                echo "tgt ports clear: target '$target' does not exist in scenario '$scenario'" >&2
                return 1
            end
            _tgt_ports_clear $scenario $target
            set_color green
            echo "✓ cleared all port records for $scenario:$target"
            set_color normal
            return 0

        case unset
            if set -q TGT_PORT
                set -l prev $TGT_PORT
                _tgt_unexport TGT_PORT
                set_color green
                echo "✓ TGT_PORT unset (was $prev)"
                set_color normal
            else
                echo "- TGT_PORT was not set"
            end
            return 0

        case comment
            argparse --name='tgt ports comment' 't/target=' -- $rest
            or return 1
            set -l flag_target ""
            set -q _flag_target; and set flag_target $_flag_target
            set -l target (_tgt_ports_cli__resolve_target comment "$flag_target" "$default_target")
            or return $status
            if not _tgt_target_exists $scenario $target
                echo "tgt ports comment: target '$target' does not exist in scenario '$scenario'" >&2
                return 1
            end
            if test (count $argv) -lt 2
                echo "Usage: tgt ports comment [--target <t>] <port>[/<proto>] <text>" >&2
                return 1
            end
            set -l spec $argv[1]
            set -l text $argv[2..]
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
                echo "tgt ports comment: no record for $port/$proto in $scenario:$target (add it first with `tgt ports add $port/$proto`)" >&2
                return 1
            end
            set_color green
            echo "✓ comment set on $port/$proto in $scenario:$target"
            set_color normal
            return 0

        case service
            # Mirror of `comment` — update the service field of an
            # existing record, preserving the stored comment. Banner
            # grabs and nmap fingerprints aren't always right; this
            # gives the user a fix path without `rm` + `add` (which
            # would drop the comment).
            argparse --name='tgt ports service' 't/target=' -- $rest
            or return 1
            set -l flag_target ""
            set -q _flag_target; and set flag_target $_flag_target
            set -l target (_tgt_ports_cli__resolve_target service "$flag_target" "$default_target")
            or return $status
            if not _tgt_target_exists $scenario $target
                echo "tgt ports service: target '$target' does not exist in scenario '$scenario'" >&2
                return 1
            end
            if test (count $argv) -lt 2
                echo "Usage: tgt ports service [--target <t>] <port>[/<proto>] <name>" >&2
                return 1
            end
            set -l spec $argv[1]
            set -l text $argv[2..]
            set -l port $spec
            set -l proto tcp
            if string match -q '*/*' -- $spec
                set -l parts (string split / -- $spec)
                set port $parts[1]
                set proto $parts[2]
            end
            if not _tgt_ports_validate_port $port
                echo "tgt ports service: invalid port '$port'" >&2
                return 1
            end
            if not _tgt_ports_validate_proto $proto
                echo "tgt ports service: invalid proto '$proto' (use tcp or udp)" >&2
                return 1
            end
            if not _tgt_ports_service $scenario $target $port $proto $text
                echo "tgt ports service: no record for $port/$proto in $scenario:$target (add it first with `tgt ports add $port/$proto`)" >&2
                return 1
            end
            set_color green
            echo "✓ service set on $port/$proto in $scenario:$target"
            set_color normal
            return 0

        case '*'
            echo "tgt ports: unknown subcommand '$verb'" >&2
            return 1
    end
end
