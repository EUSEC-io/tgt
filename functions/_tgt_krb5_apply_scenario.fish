# Make /etc/krb5.conf reflect ALL DC entries in the named scenario:
# strip every tgt-managed realm block from the current file, then
# re-add one block per realm — DCs that share a realm name collapse
# into a single block with multiple `kdc =` lines (the canonical
# kerberos form). Leaves manual user-written entries untouched.
# No-op when the resulting content matches what's on disk already.
#
# default_realm is not touched here — `tgt dc switch` does that.
function _tgt_krb5_apply_scenario --argument-names scenario
    set -l krb5 (_tgt_krb5_file)
    set -l current ""
    test -f $krb5; and set current (command cat -- $krb5 | string collect)

    # Strip tgt-tagged blocks from current content.
    set -l stripped (printf '%s' $current | _tgt_krb5_strip_tgt_blocks | string collect)

    # Group DC aliases by their realm name (preserving insertion
    # order so the rendered output is deterministic). Two parallel
    # arrays — fish lacks associative arrays.
    set -l ordered_realms
    set -l aliases_by_realm
    for a in (_tgt_dc_list $scenario)
        set -l file (_tgt_dc_file $scenario $a)
        test -f $file; or continue
        set -l realm ""
        while read -l ln
            set -l m (string match -r '^_tgt_export\s+TGT_DC_REALM\s+(.*)$' -- $ln)
            test (count $m) -ge 2; and set realm (string unescape -- $m[2]); and break
        end < $file
        test -z "$realm"; and continue

        set -l idx 0
        for i in (seq (count $ordered_realms))
            test "$ordered_realms[$i]" = "$realm"; and set idx $i; and break
        end
        if test $idx -eq 0
            set -a ordered_realms $realm
            set -a aliases_by_realm $a
        else
            set aliases_by_realm[$idx] "$aliases_by_realm[$idx] $a"
        end
    end

    # Render one merged block per realm.
    set -l blocks ""
    for i in (seq (count $ordered_realms))
        set -l realm $ordered_realms[$i]
        set -l aliases (string split " " -- $aliases_by_realm[$i])
        set -l b (_tgt_krb5_render_realm $scenario $realm $aliases 2>/dev/null | string collect)
        test -z "$b"; and continue
        if test -z "$blocks"
            set blocks $b
        else
            set blocks "$blocks
$b"
        end
    end

    # Inject blocks under [realms] (or create the section). When the
    # scenario has no DCs, just keep the stripped content as-is — the
    # [realms] section may end up empty but that's harmless to krb5.
    set -l content $stripped
    if test -n "$blocks"
        if string match -rq '\[realms\]' -- $content
            set content (string replace -r -- '(\[realms\])' "\$1
$blocks" $content | string collect)
        else
            if not string match -rq '\n$' -- $content
                set content "$content"\n
            end
            set content "$content
[realms]
$blocks
"
        end
    end

    test "$content" = "$current"; and return 0
    printf '%s' $content | _tgt_krb5_write
end
