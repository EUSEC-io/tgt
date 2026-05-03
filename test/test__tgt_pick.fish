source (status dirname)/helpers.fish

# Force the numbered fallback + read from stdin, so tests don't depend
# on fzf being installed or on having a real /dev/tty.
set -gx TGT_PICKER_NO_FZF 1
set -gx TGT_PICKER_USE_STDIN 1

#
# Empty list → no output, nonzero exit.
#
@test "pick: empty list returns nonzero" \
    (_tgt_pick "fruit" 2>/dev/null; echo $status) -ne 0

#
# Selecting by number returns the right item.
#
set -l result (echo 2 | _tgt_pick "fruit" apple banana cherry 2>/dev/null)
@test "pick: numbered choice 2 returns banana" "$result" = banana

set -l result (echo 1 | _tgt_pick "fruit" apple banana cherry 2>/dev/null)
@test "pick: numbered choice 1 returns apple" "$result" = apple

set -l result (echo 3 | _tgt_pick "fruit" apple banana cherry 2>/dev/null)
@test "pick: numbered choice 3 returns cherry" "$result" = cherry

#
# Out-of-range / invalid input returns nonzero, no stdout.
#
set -l result (echo 99 | _tgt_pick "fruit" apple banana cherry 2>/dev/null)
@test "pick: out-of-range index → empty stdout" -z "$result"

set -l result (echo abc | _tgt_pick "fruit" apple banana cherry 2>/dev/null)
@test "pick: non-numeric input → empty stdout" -z "$result"

set -l result (echo "" | _tgt_pick "fruit" apple banana cherry 2>/dev/null)
@test "pick: empty input → empty stdout" -z "$result"

#
# Single-item list still works (numbered fallback shows [1]).
#
set -l result (echo 1 | _tgt_pick "only" lonely 2>/dev/null)
@test "pick: single-item list, choice 1 returns the only item" "$result" = lonely

set -e TGT_PICKER_NO_FZF
set -e TGT_PICKER_USE_STDIN

#
# Test-result bypass: callers can short-circuit the picker entirely.
#
set -gx TGT_PICKER_TEST_RESULT banana
set -l result (_tgt_pick "fruit" apple banana cherry)
@test "pick: TGT_PICKER_TEST_RESULT bypasses to the supplied value" \
    "$result" = banana
set -e TGT_PICKER_TEST_RESULT
