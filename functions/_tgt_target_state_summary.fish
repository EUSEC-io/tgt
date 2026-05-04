# Print a compact one-liner summary of a target's persisted state
# (host[:port], creds Y/N, AD Y/N, hostnames count). Used by
# `tgt switch` to show what was just loaded. Reads from disk via
# _tgt_target_inspect; no env-var dependency.
function _tgt_target_state_summary --argument-names scenario alias
    set -l line (_tgt_target_inspect $scenario $alias)
    or return 1
    set -l fields (string split \t -- $line)
    # alias, host[:port], creds Y/N, AD Y/N, hosts_count
    set_color brblack; printf '  '; set_color normal
    printf '%s' $fields[2]
    set_color brblack; printf '   creds:'; set_color normal
    if test "$fields[3]" = Y
        set_color red; printf '%s' Y; set_color normal
    else
        set_color brblack; printf '%s' N; set_color normal
    end
    set_color brblack; printf '   AD:'; set_color normal
    if test "$fields[4]" = Y
        set_color yellow; printf '%s' Y; set_color normal
    else
        set_color brblack; printf '%s' N; set_color normal
    end
    set_color brblack; printf '   hosts:'; set_color normal
    if test "$fields[5]" -gt 0
        printf '%s' $fields[5]
    else
        set_color brblack; printf '%s' $fields[5]; set_color normal
    end
    echo ""
end
