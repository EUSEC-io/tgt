function tun0ip
    ip -4 addr show tun0 2>/dev/null | grep -oP "inet \K[^/]+"
    or echo "tun0 not active"
end
