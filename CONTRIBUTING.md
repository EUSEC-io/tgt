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

Two pipelines, picked by file extension:

| File | Renders to | Tool | For |
|---|---|---|---|
| `demos/<name>.fish` | `assets/<name>.svg` | `termtosvg` | Non-interactive output (commands + their output) |
| `demos/<name>.tape` | `assets/<name>.gif` | `vhs` | Interactive flows that need keystroke driving (gum, fzf, the wizard) |

`make demo` runs both pipelines and picks up new files in `demos/`
automatically. Files prefixed with `_` are ignored (helpers, smoke
tests). `make demo-clean` removes the generated assets.

### termtosvg (non-interactive)

```bash
sudo apt install termtosvg      # or `pacman -S termtosvg` on Arch
```

Pure Python, in apt. Records the PTY and renders an SVG animation
in one step. Each script sources `demos/_baseline.fish` for tmp-dir
sandboxing + a `_p` prompt helper.

### vhs (interactive)

```bash
# vhs — Charm's official apt repo (one-time)
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
sudo apt update && sudo apt install vhs

# ttyd — vhs's runtime dep, single binary from upstream
sudo wget https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 -O /usr/local/bin/ttyd
sudo chmod +x /usr/local/bin/ttyd
```

vhs takes a declarative `.tape` file: `Type "..."`, `Down`, `Enter`,
`Sleep 1s`. It drives gum / fzf / the wizard via a real PTY.

**Sandboxing quirk:** vhs/ttyd starts fish without autoloading the
user's config (function path is bare, conf.d not sourced). Each
tape needs a `Hide` block at the top that sets
`fish_function_path` and sources `~/.config/fish/conf.d/*.fish`
manually. See `demos/config.tape` for the pattern.

Output dimensions: 960×720 at FontSize 18 — fits inside GitHub's
content area without scaling.


## Pre-commit checks

Before committing:

1. `make test` — must be green.
2. `grep -rn '\\`' functions/ completions/ test/` — must be empty.
   Fish doesn't escape backticks inside `""`, so `\` slips into
   echo'd strings if you write `\`x\`` out of bash habit.
