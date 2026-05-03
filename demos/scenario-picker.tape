# Demo: `tgt scenario` (no args) — the gum-driven action picker.

Output assets/scenario-picker.gif

Set Shell "fish"
Set FontSize 18
Set Width 960
Set Height 540
Set Padding 20
Set Theme "Dracula"

Source demos/_vhs_setup.tape

Hide
# Build a scenario with three targets so `show` has something rich
Type "tgt scenario new dante >/dev/null"
Enter
Sleep 80ms
Type "set -gx TGT 10.10.10.5; tgt new web01 --no-edit >/dev/null; tgt scenario new dante >/dev/null 2>&1; set -gx TGT 10.10.10.10; set -gx TGT_PORT 445; set -gx TGT_USERNAME admin; set -gx TGT_PASSWORD secret; set -gx TGT_AD_DOMAIN dante.local; set -gx TGT_HOSTS dc01.dante.local; tgt new dc01 --no-edit >/dev/null; _tgt_target_save dante dc01"
Enter
Sleep 80ms
Type "set -e TGT TGT_PORT TGT_USERNAME TGT_PASSWORD TGT_AD_DOMAIN TGT_HOSTS"
Enter
Sleep 80ms
Type "set -gx TGT_SCENARIO dante; set -gx TGT_ACTIVE dc01"
Enter
Sleep 80ms
Type "clear"
Enter
Sleep 200ms
Show

Type "tgt scenario"
Sleep 500ms
Enter
Sleep 2.5s

# Pick 'show' (down twice from default 'new')
Down
Sleep 400ms
Down
Sleep 400ms
Enter
Sleep 5s
