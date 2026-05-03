# Returns 0 when workspace folder auto-creation is enabled, 1 otherwise.
# Opt-in: set $TGT_WORKSPACE_AUTOCREATE to one of 1, true, yes, on.
function _tgt_workspace_autocreate
    set -q TGT_WORKSPACE_AUTOCREATE; or return 1
    switch (string lower -- $TGT_WORKSPACE_AUTOCREATE)
        case 1 true yes on
            return 0
    end
    return 1
end
