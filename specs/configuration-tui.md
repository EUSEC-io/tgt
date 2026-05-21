# Spec: Configuration TUI + Workspace Folders

Status: backlog
Owner: stefan

## Goal

Give tgt a configuration layer that lets the user set workspace
preferences (report path, file conventions, default editor, etc.) via
an interactive TUI, and auto-creates the matching directory structure
for each scenario and target so scan output / loot / notes have a
predictable home.

## Why

Today this is all manual:
- User picks a directory like `~/HTB/forest/` and `cd`s there before
  starting work.
- Scan output, exploit scripts, loot files all go into ad-hoc
  subdirectories.
- No consistency between scenarios, no automated structure.

For Pro Labs and client engagements, the absence of structure becomes
expensive: at the end you're hunting through 30 different folders to
write the report.

## Workspace concept

A configurable **workspace root** (default: `~/work/tgt/` or similar)
under which tgt auto-mirrors the registry layout:

```
~/work/tgt/                              # workspace root, configurable
├── dante/                               # scenario folder
│   ├── _engagement.md                   # optional: notes, scope, dates
│   ├── web01/                           # target folder
│   │   ├── nmap/
│   │   ├── loot/
│   │   ├── notes.md
│   │   └── exploits/
│   ├── dc01/
│   │   └── ...
│   └── _report/                         # scenario-level report assets
│       ├── findings/
│       └── screenshots/
└── customer-acme/
    └── ...
```

Subfolder names (`nmap/`, `loot/`, `notes.md` etc.) come from a
configurable template — different users want different conventions.

## Operations

| Command | Behavior |
|---|---|
| `tgt config` | Open the configuration TUI |
| `tgt cd` | `cd` to the active target's folder |
| `tgt cd <alias>` | `cd` to a specific target's folder |
| `tgt cd --scenario` | `cd` to the active scenario's root |
| `tgt path` | Print the active target's folder path (no cd, useful for piping) |

`tgt new <alias>` and `tgt scenario new <name>` also create their
matching workspace folders from the template.

`tgt rm` and `tgt scenario rm` should NOT delete the workspace folders
by default — too dangerous. Add explicit `--purge-workspace` flag if
the user wants total wipe.

## Configuration TUI

Built with `gum` (with plain-`read` fallback). Single screen,
form-style:

```
─── tgt configuration ──────────────────────

  Workspace root:  [ ~/work/tgt/                  ]

  Per-target folders to create (one per line):
    ┌────────────────────────────────┐
    │ nmap/                          │
    │ loot/                          │
    │ exploits/                      │
    │ notes.md                       │
    │ screenshots/                   │
    └────────────────────────────────┘

  Per-scenario folders:
    ┌────────────────────────────────┐
    │ _report/findings/              │
    │ _report/screenshots/           │
    │ _engagement.md                 │
    └────────────────────────────────┘

  Editor (used by `tgt edit`):  [ vim         ]

  [ Save ]   [ Cancel ]
```

Storage: `~/.config/fish/tgt/config.fish` (sourced at shell startup
via the loader, sets `$TGT_WORKSPACE_ROOT` etc).

## Implementation notes

- New `_tgt_config_*` helpers for read/write of the config file.
- Auto-creation hooks added to `tgt scenario new` and `tgt new`.
- Workspace folders are user-owned (no sudo). Creation is idempotent.
- `tgt cd` is implemented as a fish function that calls `cd` (must be
  a function, not a command, since `cd` doesn't survive across child
  processes).
- gum dependency is optional — without it, fall back to a series of
  `read -P` prompts.

## Open questions

1. **Per-scenario template overrides?** A scenario might want its own
   folder layout (HTB single boxes vs. Pro Labs vs. client engagements
   have different needs). Default template + per-scenario override is
   probably the right shape, but adds complexity.
2. **Notes file convention.** Should `notes.md` be auto-created with a
   template (date, target IP, etc.)? Or just touched empty?
3. **Multi-user paths.** If user has multiple machines, sync via git
   would be nice. Maybe `.git` ignore by default but not enforced.

## Out of scope

- Cloud sync.
- Report rendering (markdown → PDF, etc.) — separate tool's concern.
- File templates beyond simple touch-empty / mkdir.
