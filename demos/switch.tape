# Demo: `tgt switch` (no arg) — fzf picker for jumping between
# targets in the active scenario.

Output assets/switch.gif

Set Shell "fish"
Set FontSize 18
Set Width 960
Set Height 540
Set Padding 20
Set Theme "Dracula"

Source demos/_vhs_setup.tape

Hide
Type "tgt scenario new dante >/dev/null"
Enter
Sleep 80ms
Type "tgt new web01 --no-edit >/dev/null"
Enter
Sleep 80ms
Type "tgt new dc01 --no-edit >/dev/null"
Enter
Sleep 80ms
Type "tgt new fileserver --no-edit >/dev/null"
Enter
Sleep 80ms
Type "clear"
Enter
Sleep 200ms
Show

Type "tgt switch"
Sleep 500ms
Enter
Sleep 2.5s

# fzf opens — pick the second-from-top
Down
Sleep 400ms
Enter
Sleep 4s
