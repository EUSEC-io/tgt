# Print a multi-line summary of the active target's loaded state.
# Reads from the live env (assumed freshly loaded by `tgt switch`).
# Used to show "what just got pulled in" after a switch.
function _tgt_target_state_summary
    set -l host_part "(not set)"
    set -q TGT; and set host_part $TGT

    set -l creds_part "(not set)"
    if set -q TGT_USERNAME
        if set -q TGT_PASSWORD
            set creds_part "$TGT_USERNAME / $TGT_PASSWORD"
        else
            set creds_part "$TGT_USERNAME (no password)"
        end
    end

    set -l ad_part "(not set)"
    if set -q TGT_DC_NAME
        if set -q TGT_DC_DOMAIN
            set ad_part "$TGT_DC_DOMAIN  (DC: $TGT_DC_NAME)"
        else
            set ad_part "(DC: $TGT_DC_NAME)"
        end
    end

    set -l hosts_part "(none)"
    if set -q TGT_HOSTS; and test (count $TGT_HOSTS) -gt 0
        set hosts_part (string join ", " -- $TGT_HOSTS)
    end

    set_color brblack; printf '  host:   '; set_color normal; echo $host_part
    set_color brblack; printf '  creds:  '; set_color normal
    if set -q TGT_USERNAME
        set_color red
    else
        set_color brblack
    end
    echo $creds_part
    set_color normal
    set_color brblack; printf '  AD:     '; set_color normal
    if set -q TGT_DC_NAME
        set_color yellow
    else
        set_color brblack
    end
    echo $ad_part
    set_color normal
    set_color brblack; printf '  hosts:  '; set_color normal
    echo $hosts_part
end
