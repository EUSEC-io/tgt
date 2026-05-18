# Sourced at the top of every demo. Sandboxes the script into tmp
# paths and erases any TGT_* globals that may have leaked in from the
# user's config.fish, so each demo controls its own state explicitly.

# Tmp paths — each demo gets its own, cleaned up at end.
set -gx TGT_TEST_MODE 1
set -gx TGT_HOME (mktemp -d)
set -gx TGT_WORKSPACE_ROOT (mktemp -d)
set -gx TGT_HOSTS_FILE (mktemp)
set -gx TGT_KRB5_FILE (mktemp)

# Erase any inherited TGT_* globals (the user's config.fish exports
# workspace settings; demos that don't explicitly want them should
# start clean).
for _v in TGT_WORKSPACE_LAYOUT TGT_WORKSPACE_AUTOCREATE \
          TGT_WORKSPACE_TARGET_TEMPLATE TGT_WORKSPACE_SCENARIO_TEMPLATE \
          TGT TGT_PORT TGT_HOSTS \
          TGT_USERNAME TGT_PASSWORD \
          TGT_CRED_NAME TGT_CRED_USERNAME TGT_CRED_PASSWORD \
          TGT_CRED_DOMAIN TGT_CRED_NOTES \
          TGT_DC TGT_DC_NAME TGT_DC_DOMAIN TGT_DC_REALM \
          TGT_DC_HOST TGT_DC_IP TGT_DC_IP_SOURCE \
          TGT_DC_ADMIN_HOST TGT_DC_ADMIN_IP TGT_DC_ADMIN_IP_SOURCE \
          TGT_SCENARIO TGT_ACTIVE
    set -qg $_v; and set -eg $_v
end
set -e _v

# Print a "command-being-typed" prompt line; small pause so the
# viewer reads the command before the output starts streaming.
function _p
    set_color cyan
    echo -n "smp86\$ "
    set_color normal
    echo $argv
    sleep 1.0
end

function _demo_cleanup
    set -q TGT_HOME; and command rm -rf -- $TGT_HOME
    set -q TGT_WORKSPACE_ROOT; and command rm -rf -- $TGT_WORKSPACE_ROOT
    set -q TGT_HOSTS_FILE; and command rm -f -- $TGT_HOSTS_FILE
    set -q TGT_KRB5_FILE; and command rm -f -- $TGT_KRB5_FILE
end
