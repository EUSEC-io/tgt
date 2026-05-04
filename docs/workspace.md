# Workspace deep-dive

Workspace folders are the optional per-engagement directory tree
where scans / loot / exploits / notes live. Off by default; opt in
with `tgt config` or:

```fish
set -Ux TGT_WORKSPACE_AUTOCREATE 1
```

For the bare-bones command list, see
[commands.md → Workspace](commands.md#workspace).


## Layouts

`flat` — everything at scenario level. Best for HTB single boxes.

```
~/Documents/pentest/dante/
├── scans/  loot/  exploits/  screenshots/
└── notes.md
```

`nested` — per-target subfolders + scenario-level report assets.
Better for Pro Labs / client engagements with many targets.

```
~/Documents/pentest/dante/
├── _report/{findings,screenshots}/
├── _engagement.md
├── web01/
│   ├── scans/  loot/  exploits/  screenshots/
│   └── notes.md
└── dc01/
    └── ...
```


## Settings storage

`tgt config` writes to `~/.config/fish/tgt/config.fish` (or
`$TGT_HOME/config.fish`). The file is plain fish source — `set -gx VAR
value` lines — sourced by a `conf.d/` hook at shell startup. `cat` it,
edit by hand, commit to git, rsync between machines.

Env vars exported in your current shell still take precedence over the
file's values (handy for one-off overrides and tests).


## Templates

Configurable via `tgt config` or directly. Defaults shown:

```fish
set -Ux TGT_WORKSPACE_TARGET_TEMPLATE   scans/ loot/ exploits/ screenshots/ notes.md
set -Ux TGT_WORKSPACE_SCENARIO_TEMPLATE _report/findings/ _report/screenshots/ _engagement.md
```

In `flat` layout the per-target template is applied at scenario level
and the scenario template is unused. In `nested` layout, both apply
(scenario template at scenario root, target template under each target
dir). Trailing `/` on a template entry creates a directory; anything
else is `touch`-created as a file.
