# Shared sandbox setup for vhs tapes. Sourced from each tape via:
#   Source demos/_vhs_setup.tape
#
# vhs/ttyd starts fish with a bare environment (no autoload, no
# conf.d) so we wire up the function path manually and source the
# user's conf.d so `tgt` is on the prompt. State is redirected
# into tmp dirs so the demo doesn't touch the user's real config.

Hide
Type "set -gx fish_function_path ~/.config/fish/functions /etc/fish/functions /usr/share/fish/functions"
Enter
Sleep 80ms
Type "set -gx fish_complete_path ~/.config/fish/completions /etc/fish/completions /usr/share/fish/completions"
Enter
Sleep 80ms
Type "set -gx TGT_HOME (mktemp -d); and mkdir -p $TGT_HOME"
Enter
Sleep 80ms
Type "set -gx TGT_WORKSPACE_ROOT (mktemp -d)"
Enter
Sleep 80ms
Type "set -gx TGT_HOSTS_FILE (mktemp); set -gx TGT_KRB5_FILE (mktemp)"
Enter
Sleep 80ms
Type "set -gx TGT_NO_SUDO 1; set -gx TGT_NO_UNIVERSALS 1"
Enter
Sleep 80ms
Type "for f in ~/.config/fish/conf.d/*.fish; source $f; end"
Enter
Sleep 80ms
Type "for v in TGT TGT_USERNAME TGT_PASSWORD TGT_AD_DOMAIN TGT_DC TGT_HOSTS TGT_SCENARIO TGT_ACTIVE TGT_WORKSPACE_LAYOUT TGT_WORKSPACE_AUTOCREATE TGT_WORKSPACE_TARGET_TEMPLATE TGT_WORKSPACE_SCENARIO_TEMPLATE; set -qg $v; and set -eg $v; end"
Enter
Sleep 80ms
Type "clear"
Enter
Sleep 200ms
Show
