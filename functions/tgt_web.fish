# Launch the tgt web UI. Proof-of-concept; reads the registry directly
# and shells out to `tgt` for write actions. See web/server.py for the
# server implementation + design rules.
#
# Usage:
#   tgt web                # auto-picks a port, opens the browser
#   tgt web --port 8080    # bind to a specific port
#   tgt web --no-open      # don't auto-open browser (useful for SSH)
function tgt_web --description 'Launch the tgt web UI (local, browser-based)'
    # Locate the server script. In dev (make dev), this function is a
    # symlink into the repo so (status dirname) resolves there. In a
    # Fisher install, the .py file isn't copied (Fisher is .fish-only)
    # so we'd need a separate install step — out of scope for the PoC.
    set -l self (status filename)
    set -l self_real (realpath -- $self 2>/dev/null; or echo $self)
    set -l repo_root (dirname (dirname -- $self_real))
    set -l server $repo_root/web/server.py

    if not test -f $server
        echo "tgt web: server script not found at $server" >&2
        echo "  (this PoC requires the repo's web/ dir alongside functions/)" >&2
        return 1
    end

    if not command -q python3
        echo "tgt web: python3 not found" >&2
        return 1
    end

    command python3 $server $argv
end
