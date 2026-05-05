# Filter krb5 content (read from stdin) to strip every tgt-managed
# realm block. A managed block has the shape:
#
#     # tgt:dc:<scenario>:<alias>
#     <REALM> = {
#         ...
#     }
#
# Both the comment line and the realm block (through the closing
# brace) are removed. Manual entries written by the user pass
# through untouched.
function _tgt_krb5_strip_tgt_blocks
    set -l in_tgt 0
    while read -l line
        if test $in_tgt -eq 0
            if string match -rq '^\s*#\s*tgt:dc:' -- $line
                set in_tgt 1
                continue
            end
            echo $line
        else
            string match -q '*}*' -- $line; and set in_tgt 0
        end
    end
end
