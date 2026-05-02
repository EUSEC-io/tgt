# Remove the named realm's block from the krb5 config file.
function _tgt_clean_krb5
    set -l realm $argv[1]
    set -l krb5 (_tgt_krb5_file)
    if grep -q "$realm" $krb5 2>/dev/null
        _tgt_sudo python3 -c '
import re, sys
realm = sys.argv[1]
path = sys.argv[2]
with open(path, "r") as f:
    content = f.read()
content = re.sub(r"\n?\s*" + re.escape(realm) + r"\s*=\s*\{[^}]*\}", "", content)
with open(path, "w") as f:
    f.write(content)
' "$realm" "$krb5"
    end
end
