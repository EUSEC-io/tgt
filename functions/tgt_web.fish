# Launch the tgt web UI. The actual server is a separate Python
# package (`tgt-web`) installed via pipx; this wrapper just dispatches
# to it and prints a helpful install hint when it's missing.
#
# Usage:
#   tgt web                # auto-picks a port, opens the browser
#   tgt web --port 8080    # bind to a specific port
#   tgt web --no-open      # don't auto-open browser (useful for SSH)
function tgt_web --description 'Launch the tgt web UI (local, browser-based)'
    if not command -q tgt-web
        echo "tgt web: tgt-web not installed." >&2
        echo "  Install: pipx install \"git+https://github.com/EUSEC-io/tgt#subdirectory=web\"" >&2
        echo "  (or: cd <repo>/web && pipx install -e .)" >&2
        return 1
    end
    command tgt-web $argv
end
