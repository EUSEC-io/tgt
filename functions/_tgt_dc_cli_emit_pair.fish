# Render a host/ip pair for `tgt dc show`, with an optional source
# label for the IP. When both host and ip are known, show the
# mapping with an arrow ("dc01.dante.local  →  10.10.10.5"). The
# `ip_source` (one of "user" / "hosts" / "dns") is shown in dim
# parentheses when set, so the user can tell where the IP came
# from at create/edit time.
function _tgt_dc_cli_emit_pair --argument-names host ip ip_source
    set -l body
    if test -n "$host"; and test -n "$ip"
        set body "$host  →  $ip"
    else if test -n "$host"
        set body "$host"
    else if test -n "$ip"
        set body "$ip"
    else
        set_color brblack; echo "(not set)"; set_color normal
        return
    end

    echo -n $body
    if test -n "$ip_source"
        set -l label
        switch $ip_source
            case user
                set label "(user-provided)"
            case hosts
                set label "(from /etc/hosts)"
            case dns
                set label "(resolved via DNS)"
            case '*'
                set label "(source: $ip_source)"
        end
        set_color brblack
        echo -n "  $label"
        set_color normal
    end
    echo ""
end
