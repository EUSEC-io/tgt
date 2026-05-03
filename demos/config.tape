# Demo: walking through `tgt config` — the gum-driven workspace
# settings wizard. vhs drives interactive gum widgets via a real PTY.
#
# Run via: vhs demos/config.tape  →  produces assets/config.gif

Output assets/config.gif

Set Shell "fish"
Set FontSize 18
Set Width 960
Set Height 720
Set Padding 20
Set Theme "Dracula"

# Hidden setup: vhs/ttyd starts fish without autoloading the user's
# config, so the function path is bare and conf.d isn't sourced.
# Wire it up explicitly, plus sandbox tgt's state into tmp dirs.
Hide
Type "set -gx fish_function_path ~/.config/fish/functions /etc/fish/functions /usr/share/fish/functions"
Enter
Sleep 100ms
Type "set -gx fish_complete_path ~/.config/fish/completions /etc/fish/completions /usr/share/fish/completions"
Enter
Sleep 100ms
Type "set -gx TGT_HOME (mktemp -d); and mkdir -p $TGT_HOME"
Enter
Sleep 100ms
Type "set -gx TGT_WORKSPACE_ROOT (mktemp -d)"
Enter
Sleep 100ms
Type "set -gx TGT_HOSTS_FILE (mktemp); set -gx TGT_KRB5_FILE (mktemp)"
Enter
Sleep 100ms
Type "for f in ~/.config/fish/conf.d/*.fish; source $f; end"
Enter
Sleep 100ms
Type "for v in TGT_WORKSPACE_LAYOUT TGT_WORKSPACE_AUTOCREATE TGT_WORKSPACE_TARGET_TEMPLATE TGT_WORKSPACE_SCENARIO_TEMPLATE; set -qg $v; and set -eg $v; end"
Enter
Sleep 100ms
Type "clear"
Enter
Sleep 200ms
Show

# ── Demo starts ──
Type "tgt config"
Sleep 500ms
Enter
Sleep 2s

# 1. Workspace root
Type "/home/you/Documents/pentest"
Sleep 700ms
Enter
Sleep 1.2s

# 2. Layout — pick 'nested'
Down
Sleep 500ms
Enter
Sleep 1.2s

# 3. Auto-create folders — accept default (Yes)
Sleep 700ms
Enter
Sleep 1.2s

# 4. Per-target template — gum write opens; just save (Ctrl+D)
Sleep 1s
Ctrl+d
Sleep 1.2s

# 5. Per-scenario template — same
Sleep 1s
Ctrl+d
Sleep 1.2s

# 6. Save? — accept (Yes)
Sleep 1s
Enter
Sleep 4s

# Confirm the file was actually written
Type "cat $TGT_HOME/config.fish"
Enter
Sleep 6s
