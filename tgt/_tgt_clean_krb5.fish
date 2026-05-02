# Remove the named realm's block from /etc/krb5.conf.
function _tgt_clean_krb5
    set -l realm $argv[1]
    if grep -q "$realm" /etc/krb5.conf 2>/dev/null
        sudo python3 -c '
import re, sys
realm = sys.argv[1]
with open("/etc/krb5.conf", "r") as f:
    content = f.read()
content = re.sub(r"\n?\s*" + re.escape(realm) + r"\s*=\s*\{[^}]*\}", "", content)
with open("/etc/krb5.conf", "w") as f:
    f.write(content)
' "$realm"
    end
end
