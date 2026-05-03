# Bulk-import a directory of subdirs as scenarios. Default action:
# move each subdir into the workspace root and register a scenario
# of the same (sanitized) name. With --copy, the source stays
# intact. --prefix prepends a string to each scenario name.
# --dry-run prints the plan without touching anything.
function _tgt_scenario_import
    argparse --name='tgt scenario import' 'copy' 'dry-run' 'prefix=' -- $argv
    or return 1
    if test (count $argv) -lt 1
        echo "Usage: tgt scenario import <path> [--copy] [--dry-run] [--prefix <p>]" >&2
        return 1
    end
    set -l src $argv[1]
    if not test -d $src
        echo "tgt scenario import: '$src' is not a directory" >&2
        return 1
    end

    set -l prefix ""
    set -q _flag_prefix; and set prefix $_flag_prefix
    set -l do_copy 0
    set -q _flag_copy; and set do_copy 1
    set -l dry 0
    set -q _flag_dry_run; and set dry 1

    set -l workspace (_tgt_workspace_root)
    set -l created 0
    set -l skipped 0
    set -l errors 0

    if test $dry -eq 1
        set_color brblack
        echo "  (dry-run — nothing will be moved or registered)"
        set_color normal
    end

    for entry in $src/*
        set -l raw (basename $entry)
        if not test -d $entry
            set_color brblack
            echo "  skip (not a directory): $raw"
            set_color normal
            set skipped (math $skipped + 1)
            continue
        end

        set -l sanitized (_tgt_scenario_sanitize_name $raw)
        set -l name "$prefix$sanitized"

        if not _tgt_scenario_validate_name $name
            set_color red
            echo "  ✗ invalid scenario name '$name' (from '$raw') — skipping"
            set_color normal
            set errors (math $errors + 1)
            continue
        end
        if _tgt_scenario_exists $name
            set_color brblack
            echo "  skip (scenario exists): $name"
            set_color normal
            set skipped (math $skipped + 1)
            continue
        end
        set -l dest $workspace/$name
        if test -e $dest
            set_color red
            echo "  ✗ workspace dest exists, refusing to overwrite: $dest"
            set_color normal
            set errors (math $errors + 1)
            continue
        end

        set -l action move
        test $do_copy -eq 1; and set action copy

        if test $dry -eq 1
            echo "  would $action: $entry → $dest  (scenario: $name)"
            set created (math $created + 1)
            continue
        end

        if not _tgt_scenario_create $name
            set_color red
            echo "  ✗ failed to register scenario '$name'"
            set_color normal
            set errors (math $errors + 1)
            continue
        end
        mkdir -p -- $workspace
        set -l ok 1
        if test $do_copy -eq 1
            command cp -r -- $entry $dest; or set ok 0
        else
            command mv -- $entry $dest; or set ok 0
        end
        if test $ok -eq 0
            set_color red
            echo "  ✗ failed to $action $entry → $dest (rolling back scenario)"
            set_color normal
            _tgt_scenario_destroy $name
            set errors (math $errors + 1)
            continue
        end

        set_color green
        echo "  ✓ $action: $raw → $name  ($dest)"
        set_color normal
        set created (math $created + 1)
    end

    echo ""
    echo "  Summary: created $created, skipped $skipped, errors $errors"
    return 0
end
