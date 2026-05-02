# CLAUDE.md

## Project Overview
This is a collection of Fish shell functions and scripts.
Functions live in `functions/` and are autoloadable.
Tests use Fishtape and live in `test/`.

## Conventions
- One function per file, filename matches function name
- 4-space indentation
- Every function starts with a `# description` comment
- Use `set -l` for all local variables — never unscoped `set`
- Use `argparse` for any function that accepts flags

## Fish-Specific Rules
- Always prefer `string` builtins over external tools (grep, sed, cut, tr, awk)
- Use `command` prefix when calling external commands that might be shadowed
- Write errors to stderr: `echo "error: ..." >&2`
- Return meaningful exit codes (0 success, 1 error)
- Use `contains` for list membership, not grep
- Quote variable expansions; use `--` before variable args

## Testing
- Every function must have a corresponding `test/test_<name>.fish`
- Tests use Fishtape (`@test` syntax, TAP output)
- Test both happy path and error cases

## Don't
- Don't use subshells where builtins work
- Don't use `echo $var | grep` — use `string match`
- Don't pipe between builtins when one command suffices
- Don't swallow errors silently

