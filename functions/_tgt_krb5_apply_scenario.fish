# Make /etc/krb5.conf reflect ALL DC entries in the named scenario:
# strip every tgt-managed realm block from the current file, then
# re-add one block per DC. Leaves manual user-written entries
# untouched. No-op when the resulting content matches what's on
# disk already.
#
# default_realm is intentionally NOT touched here — that's the job
# of `tgt dc switch` (the active-DC concept lands in a separate
# commit). Until then this just keeps [realms] coherent with the
# active scenario's DC entries.
function _tgt_krb5_apply_scenario --argument-names scenario
    set -l krb5 (_tgt_krb5_file)
    set -l current ""
    test -f $krb5; and set current (command cat -- $krb5 | string collect)

    # Strip tgt-tagged blocks from current content.
    set -l stripped (printf '%s' $current | _tgt_krb5_strip_tgt_blocks | string collect)

    # Render one block per DC in the scenario.
    set -l blocks ""
    for a in (_tgt_dc_list $scenario)
        set -l b (_tgt_krb5_render_dc $scenario $a 2>/dev/null | string collect)
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
