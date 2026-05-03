# Demo: walking through `tgt config` — the gum-driven workspace
# settings wizard.

Output assets/config.gif

Set Shell "fish"
Set FontSize 18
Set Width 960
Set Height 720
Set Padding 20
Set Theme "Dracula"

Source demos/_vhs_setup.tape

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

Type "cat $TGT_HOME/config.fish"
Enter
Sleep 6s
