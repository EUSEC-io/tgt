# Print a multi-line summary of the active target's loaded state +
# the scenario's active cred and DC (both can apply across targets).
# Reads from the live env (assumed freshly loaded by `tgt switch`
# and the scenario-restore hooks).
function _tgt_target_state_summary
    set -l host_part "(not set)"
    set -q TGT; and set host_part $TGT

    set -l hosts_part "(none)"
    if set -q TGT_HOSTS; and test (count $TGT_HOSTS) -gt 0
        set hosts_part (string join ", " -- $TGT_HOSTS)
    end

    set -l cred_part "(not set)"
    if set -q TGT_CRED_NAME
        if set -q TGT_PASSWORD
            set cred_part "$TGT_CRED_NAME — $TGT_USERNAME / $TGT_PASSWORD"
        else
            set cred_part "$TGT_CRED_NAME — $TGT_USERNAME (no password)"
        end
    end

    set -l dc_part "(not set)"
    if set -q TGT_DC_NAME
        if set -q TGT_DC_DOMAIN
            set dc_part "$TGT_DC_NAME — $TGT_DC_DOMAIN"
        else
            set dc_part $TGT_DC_NAME
        end
    end

    set_color brblack; printf '  host:   '; set_color normal; echo $host_part
    set_color brblack; printf '  hosts:  '; set_color normal; echo $hosts_part
    set_color brblack; printf '  cred:   '; set_color normal
    if set -q TGT_CRED_NAME
        set_color red
    else
        set_color brblack
    end
    echo $cred_part
    set_color normal
    set_color brblack; printf '  dc:     '; set_color normal
    if set -q TGT_DC_NAME
        set_color yellow
    else
        set_color brblack
    end
    echo $dc_part
    set_color normal
end
