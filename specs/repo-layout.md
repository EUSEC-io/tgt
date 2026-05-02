# Spec: Per-Project Subfolders in `functions/`

Status: agreed
Owner: stefan

## Goal

Group each tool's files into its own subfolder of `functions/` so the
repo tree stays legible as it expands, and so `.gitignore` can allow
whole folders instead of listing each file individually.

## Current pain

`.gitignore` is allowlist-based — every shareable file needs an explicit
`!entry`:

```
*
README.md
!.gitignore
!tgt.fish
!tun0ip.fish
```

Once `tgt` grows to four helpers + completions + tests + fixtures, this
list has 15+ entries. Adding a new tool means editing the gitignore
every time. Visually scanning `functions/` for "what belongs to tgt"
gets harder as files accumulate flat.

## Constraint: fish doesn't recurse

`$fish_function_path` doesn't descend into subdirectories.
`functions/tgt/tgt.fish` won't autoload unless we extend the path.

Same for completions: `$fish_complete_path` only looks at top-level.

## Layout

```
functions/                              # git repo root (= ~/.config/fish/functions/)
├── .gitignore
├── README.md
├── CLAUDE.md
├── Makefile                            # optional: make install / make test
├── conf.d/                             # symlinked → ~/.config/fish/conf.d/
│   └── tgt-loader.fish                 # the loader (sourced at shell startup)
├── bin/                                # one-shot scripts (NOT autoloaded)
│   ├── install.fish
│   └── uninstall.fish
├── specs/                              # cross-cutting design notes
│   ├── helpers-file-organization.md
│   ├── testing.md
│   └── repo-layout.md                  # this file
├── tgt/                                # tool folder: has tgt/tgt.fish → loaded
│   ├── tgt.fish
│   ├── _tgt_clean_krb5.fish
│   ├── _tgt_update_krb5.fish
│   ├── _tgt_run_bloodhound.fish
│   ├── _tgt_hosts_write.fish
│   ├── _tgt_export.fish
│   ├── completions/
│   │   └── tgt.fish
│   ├── test/
│   │   ├── helpers.fish
│   │   ├── test_tgt.fish
│   │   ├── test__tgt_clean_krb5.fish
│   │   └── fixtures/
│   │       ├── hosts/
│   │       └── krb5/
│   └── specs/                          # tgt-specific designs
│       ├── multi-target.md
│       └── etc-hosts-management.md
├── showip/
│   ├── showip.fish
│   └── test/
│       └── test_showip.fish
├── tun0ip/
│   └── tun0ip.fish
└── machines/
    └── machines.fish
```

The repo's `conf.d/` mirrors fish's `~/.config/fish/conf.d/`. Install
symlinks one file across.

### Critical: keep top-level non-tool folders out of fish autoload

**The risk**: fish autoloads any `<name>.fish` it finds in
`$fish_function_path`. If `install.fish` or `tgt-loader.fish` lived at
the top of `functions/` (which is in fish's default function path),
typing `install` or `tgt-loader` at any prompt would silently run them.

**The fix has two parts:**

1. **Non-function content goes in subfolders.** Fish doesn't recurse
   into subdirectories of `$fish_function_path`. So
   `bin/install.fish`, `conf.d/tgt-loader.fish`, `specs/*.md` are not
   visible to autoload.

2. **The loader only registers tool folders.** A folder counts as a
   tool folder if it contains `<foldername>.fish`. So `tgt/` is loaded
   (has `tgt/tgt.fish`), `showip/` is loaded (has `showip/showip.fish`).
   `bin/`, `conf.d/`, `specs/` are skipped — they have no matching
   primary file. Rule needs no maintenance — it's the
   one-function-per-file convention applied to folder discovery.

### Rules

- Each tool gets a folder named after its primary function.
- Helpers, completions, tests, and tool-specific specs live inside the
  tool's folder.
- One-shot scripts (anything you invoke explicitly, not as a fish
  command) go in `bin/`.
- Fish startup scripts go in `conf.d/` and are symlinked into
  `~/.config/fish/conf.d/` by install.
- Cross-cutting specs live at top-level `specs/`.
- **No `.fish` files at the top of `functions/`.** They'd autoload as
  commands. Top-level is `.md` docs, `Makefile`, `.gitignore`, and
  folders only.

## Loader

A single file at `conf.d/tgt-loader.fish` (symlinked into
`~/.config/fish/conf.d/`, sourced once per shell startup) adds every
project subfolder to fish's search paths. **Self-locating** — works
regardless of where the repo is cloned.

### `conf.d/tgt-loader.fish`

```fish
# Sourced at shell startup via a symlink in ~/.config/fish/conf.d/.
# Self-locates so the repo can live anywhere on disk.

set -l self (realpath (status filename))
set -l repo (dirname (dirname $self))   # conf.d/ → repo root

for dir in $repo/*/
    test -d $dir; or continue
    set -l name (basename $dir)
    test -f $dir/$name.fish; or continue   # only "tool folders"

    set -p fish_function_path $dir
    test -d $dir/completions; and set -p fish_complete_path $dir/completions
end
```

Why this works:
- `status filename` returns the path fish used to source the script —
  the symlink in `~/.config/fish/conf.d/`.
- `realpath` dereferences to the real `conf.d/tgt-loader.fish` in the
  repo.
- `dirname (dirname ...)` walks up two levels: out of `conf.d/`, to
  repo root.
- The `test -f $dir/$name.fish` filter skips `bin/`, `conf.d/`,
  `specs/`, and any future non-tool folder automatically.

### `bin/install.fish`

```fish
#!/usr/bin/env fish
# Symlink the loader into fish's conf.d. Idempotent, location-independent.

set -l self (realpath (status filename))
set -l repo (dirname (dirname $self))      # bin/ → repo root
set -l loader $repo/conf.d/tgt-loader.fish

if not test -f $loader
    echo "error: $loader not found" >&2
    exit 1
end

set -l fish_dir (test -n "$XDG_CONFIG_HOME"; and echo $XDG_CONFIG_HOME/fish; or echo $HOME/.config/fish)
set -l conf_d $fish_dir/conf.d
set -l target $conf_d/tgt-loader.fish

mkdir -p $conf_d

if test -L $target
    set -l existing (realpath $target)
    if test "$existing" = "$loader"
        echo "✓ already installed: $target"
        exit 0
    else
        echo "warning: $target → $existing, overwriting" >&2
    end
else if test -e $target
    echo "error: $target exists and is not a symlink — refusing to overwrite" >&2
    exit 1
end

ln -sf $loader $target
echo "✓ installed: $target → $loader"
echo "  open a new shell, or: source $target"
```

Idempotent. Honors `$XDG_CONFIG_HOME`. Refuses to clobber a non-symlink
at the target path.

### `bin/uninstall.fish`

```fish
#!/usr/bin/env fish
set -l fish_dir (test -n "$XDG_CONFIG_HOME"; and echo $XDG_CONFIG_HOME/fish; or echo $HOME/.config/fish)
rm -f $fish_dir/conf.d/tgt-loader.fish
echo "✓ removed loader (functions remain on disk)"
```

### Why `conf.d/` over editing `config.fish`

- `conf.d/*.fish` is fish's idiomatic plugin entry point.
- Doesn't require touching the user's `config.fish`.
- Easy to disable: delete the one symlink.

### Why symlink, not copy

- Updates to `tgt-loader.fish` propagate without re-running install.
- Repo can be moved; one re-install retargets everything.

## Where the repo can live

**A. Inside fish's config directory** (your setup):
`~/.config/fish/functions/`. The repo *is* fish's functions dir. During
migration, top-level `.fish` files keep autoloading via fish's default
behavior, so existing tools work uninterrupted while we move them into
subfolders one at a time.

**B. Anywhere else**, e.g. `~/repos/fish-functions/`,
`~/Code/fish-tools/`, `/opt/pentest-fish/`. The loader doesn't care.

Both work with the same `bin/install.fish`. The user picks where to
clone; install does the rest.

## Other users / contributors

```
git clone <repo-url> ~/wherever
cd ~/wherever
./bin/install.fish
```

That's it. Document this in `README.md` under "Installation".

For NixOS users or anyone managing `conf.d/` declaratively, the manual
equivalent:

```fish
ln -sf /path/to/repo/conf.d/tgt-loader.fish ~/.config/fish/conf.d/tgt-loader.fish
```

## `Makefile`

```makefile
.PHONY: install uninstall test

REPO       := $(shell pwd)
FISH_DIR   := $(or $(XDG_CONFIG_HOME),$(HOME)/.config)/fish
LOADER     := $(FISH_DIR)/conf.d/tgt-loader.fish

install:
	@mkdir -p $(FISH_DIR)/conf.d
	@ln -sf $(REPO)/conf.d/tgt-loader.fish $(LOADER)
	@echo "✓ installed: $(LOADER)"

uninstall:
	@rm -f $(LOADER)
	@echo "✓ removed $(LOADER)"

test:
	@fishtape */test/test_*.fish
```

Same mechanic as `bin/install.fish`, different entry point. Provide
both — they're cheap.

## `.gitignore`

```
# Ignore everything by default
*

# Repo infrastructure
!.gitignore
!README.md
!CLAUDE.md
!Makefile

# Runnable scripts and the fish loader
!bin/
!bin/**
!conf.d/
!conf.d/**

# Allow tool folders wholesale
!tgt/
!tgt/**
!showip/
!showip/**
!tun0ip/
!tun0ip/**
!machines/
!machines/**

# Cross-cutting docs
!specs/
!specs/**
```

Adding a new tool: one new `!folder/` + `!folder/**` pair. Adding a new
file inside an existing tool: zero gitignore edits.

If you ever want less maintenance, flip the default to allow-by-default
and block only secrets:

```
fish_variables
*.local.fish
**/.scratch/
**/*.tmp
```

The allowlist style stays defensive (won't accidentally commit a stray
credential file). Keep it for now — this is pentesting tooling and the
cost of a leaked file is high.

## Per-feature workflow after install

| Action | Steps |
|---|---|
| Add a new tool `webrecon` | Create `webrecon/webrecon.fish`. New shell. Done. |
| Add a helper to `tgt` | Create `tgt/_tgt_new_helper.fish`. Done (autoloaded). |
| Add completions for `tgt` | Create `tgt/completions/tgt.fish`. New shell. Done. |
| Add tests | Drop them in `<tool>/test/`. `make test`. |
| Move the repo elsewhere | Re-run `./bin/install.fish` (symlink retargets). |

The loader scans every shell startup. New folders matching the
"tool folder" rule are picked up automatically — no re-install for new
features.

## Migration steps

In rough order, smallest to largest impact. Each step is independently
revertable.

1. **Scaffold the loader infrastructure.** Create `conf.d/tgt-loader.fish`,
   `bin/install.fish`, `bin/uninstall.fish`, `Makefile`. Run
   `./bin/install.fish`. Verify a new shell still finds existing
   functions (it does — they're still at the top level).
2. **Move one tool to validate end-to-end.** Pick `tun0ip` (smallest).
   Create `tun0ip/tun0ip.fish`, remove the old `functions/tun0ip.fish`,
   open a new shell, confirm `tun0ip` still works. Update `.gitignore`.
3. **Move the rest.** `showip`, `machines`, then `tgt` last (most
   files).
4. **Relocate tgt-specific specs into `tgt/specs/`**: `multi-target.md`,
   `etc-hosts-management.md`. Cross-cutting specs (`testing.md`,
   `helpers-file-organization.md`, `repo-layout.md`) stay at top-level
   `specs/`.
5. **Simplify `.gitignore`** to the folder-level form.

## Why not flat-with-prefix-globs?

An alternative is keeping `functions/` flat but using globs in
`.gitignore`:

```
*
!tgt.fish
!_tgt_*.fish
!showip.fish
```

Pros: zero fish reconfiguration *for files at the top of `functions/`*.

Cons:
- Only works for users who clone into `~/.config/fish/functions/`.
  Other clone locations break — top-level `.fish` files aren't in
  fish's path. So compatibility is lost.
- Visual grouping disappears as projects grow.
- Tests and fixtures can't co-locate with the tool they belong to.
- Completions awkward — `~/.config/fish/completions/` is a separate
  path, so completion files inside the repo need either symlinking or
  a `$fish_complete_path` extension (which means the same loader we
  were trying to avoid).

Decision: subfolders + loader. The one-time install is the cost of
working uniformly across clone locations.

## Open questions

1. Should `bin/install.fish` also set up shellcheck / lint hooks, or
   stay minimal? Lean minimal.
2. If a tool has no helpers, is the subfolder still worth it? Yes for
   consistency — `tun0ip/tun0ip.fish` is no harder to read than
   `tun0ip.fish` and "one tool, one folder" is easier to enforce than
   "one tool, sometimes a folder."
