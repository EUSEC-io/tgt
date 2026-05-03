# Contributing

Quick reference for working on `pentest-fish-functions`.

## Layout

```
.
├── functions/              all .fish functions, flat (Fisher convention)
│   ├── tgt.fish            main dispatcher
│   ├── _tgt_*.fish         private helpers (underscore-prefixed; fish hides them)
│   ├── tgt_prompt.fish     public prompt segment function
│   └── tun0ip.fish, showip.fish, machines.fish
├── conf.d/                 fish startup hooks (e.g. tgt-config.fish)
├── completions/            tab completions
├── test/                   fishtape tests + fixtures
├── specs/                  design notes
└── README.md  CHANGELOG.md  CLAUDE.md  Makefile
```

This is a standard Fisher plugin layout. `functions/` must be flat —
fish doesn't recurse into subfolders of `$fish_function_path`.
Per-tool grouping happens via filename prefix (`_tgt_*`).

## Adding a function

Drop a new file in `functions/`. With `make dev` active, a new shell
picks it up. Naming:

- Public functions: plain name (`mything`).
- Private helpers: underscore prefix (`_mything_helper`) so fish
  hides them from default tab completion and `functions` listings.

Each function file should have a `# description` comment on its
first line.

## Conventions

- One function per file, filename matches function name.
- 4-space indentation.
- `set -l` for all local variables — never unscoped `set`.
- `argparse` for any function that accepts flags.
- Prefer `string` builtins over external tools (`grep`, `sed`,
  `cut`, `tr`, `awk`).
- Use `command` prefix when calling external commands that might
  be shadowed.
- Errors to stderr: `echo "error: ..." >&2`.
- Meaningful exit codes (0 success, 1 error).
- Use `contains` for list membership, not `grep`.
- Quote variable expansions; use `--` before variable args.

## Test mode

The codebase uses a `TGT_TEST_MODE` env var to swap behavior:

| Helper | Production | Test mode |
|---|---|---|
| `_tgt_export` / `_tgt_unexport` | `set -Ux` / `set -Ue` (universal) | `set -gx` / `set -e` (global) |
| `_tgt_sudo` | runs `sudo $argv` | runs `$argv` directly |
| `_tgt_hosts_file` / `_tgt_krb5_file` | `/etc/hosts` / `/etc/krb5.conf` | `$TGT_HOSTS_FILE` / `$TGT_KRB5_FILE` |
| `_tgt_home` | `~/.config/fish/tgt/` | `$TGT_HOME` |

Tests set `TGT_TEST_MODE` (usually via `_test_setup_*` helpers) and
provide tmp paths so `make test` doesn't need `sudo` and never
touches the user's real files.

## Running tests

```bash
make test
```

To run a single test file:

```bash
fish -c 'fishtape test/test_tgt_rename.fish'
```

## Multiple plugins coexisting

This is a Fisher plugin. Other Fisher plugins coexist with it in
your `~/.config/fish/` — Fisher tracks which files came from which
plugin in `~/.config/fish/fish_plugins`. With `make dev`, the
symlinks are named after files in this repo and won't collide with
another plugin's files (assuming the other plugin doesn't ship the
same filenames).

## Demos

Recorded terminal demos live under `demos/<name>.fish` and are
rendered by `make demo` into SVGs under `assets/`. Each script
runs in a sandboxed `$TGT_HOME` / `$TGT_WORKSPACE_ROOT` so it
can't pollute the user's real state.

Tooling (one-time):

```bash
sudo apt install termtosvg      # or `pacman -S termtosvg` on Arch
```

That's it — pure Python, no node / Rust / cargo. Records the PTY
and renders an SVG animation in one step.

Add a new demo by dropping `demos/foo.fish` — `make demo` picks it
up automatically and produces `assets/foo.svg` at 80×25. Reference
it in the README via `![foo](assets/foo.svg)`.

`make demo-clean` removes the generated `.svg` files.


## Pre-commit checks

Before committing:

1. `make test` — must be green.
2. `grep -rn '\\`' functions/ completions/ test/` — must be empty.
   Fish doesn't escape backticks inside `""`, so `\` slips into
   echo'd strings if you write `\`x\`` out of bash habit.
