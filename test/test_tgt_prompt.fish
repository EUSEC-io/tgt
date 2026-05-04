source (status dirname)/helpers.fish

#
# No scenario → empty output.
#
@test "tgt_prompt: empty output when no scenario active" \
    -z (tgt_prompt)

#
# Scenario only → contains [scenario] (no colon).
#
set -gx TGT_SCENARIO dante
set -l raw (tgt_prompt | string collect)
@test "tgt_prompt: contains [scenario] when only scenario set" \
    (string match -rq '\[dante\]' -- $raw; echo $status) -eq 0
@test "tgt_prompt: doesn't include : when target unset" \
    (string match -rq ':' -- $raw; echo $status) -ne 0
_test_teardown

#
# Scenario + target → contains [scenario:target].
#
set -gx TGT_SCENARIO dante
set -gx TGT_ACTIVE web01
set -l raw (tgt_prompt | string collect)
@test "tgt_prompt: contains [scenario:target]" \
    (string match -rq '\[dante:web01\]' -- $raw; echo $status) -eq 0
_test_teardown

#
# With password set → red SGR (\e[31m) present.
#
set -gx TGT_SCENARIO dante
set -gx TGT_ACTIVE web01
set -gx TGT_PASSWORD secret
set -l raw (tgt_prompt | string collect)
@test "tgt_prompt: emits red SGR when creds loaded" \
    (string match -rq '\e\[31m' -- $raw; echo $status) -eq 0
@test "tgt_prompt: still includes [dante:web01] when red" \
    (string match -rq '\[dante:web01\]' -- $raw; echo $status) -eq 0
_test_teardown

#
# TGT set, no creds → yellow SGR (\e[33m) present.
#
set -gx TGT_SCENARIO dante
set -gx TGT_ACTIVE web01
set -gx TGT 10.10.10.5
set -l raw (tgt_prompt | string collect)
@test "tgt_prompt: emits yellow SGR when TGT set, no creds" \
    (string match -rq '\e\[33m' -- $raw; echo $status) -eq 0
_test_teardown

#
# Color reset at the end (\e[m) so the prompt isn't tinted afterward.
#
set -gx TGT_SCENARIO dante
set -l raw (tgt_prompt | string collect)
@test "tgt_prompt: ends with \e[m reset" \
    (string match -rq '\e\[m$' -- $raw; echo $status) -eq 0
_test_teardown

#
# TGT_PORT appended to the label as :<port>.
#
set -gx TGT_SCENARIO dante
set -gx TGT_ACTIVE web01
set -gx TGT 10.10.10.5
set -gx TGT_PORT 445
set -l raw (tgt_prompt | string collect)
@test "tgt_prompt: appends :port when TGT_PORT set" \
    (string match -rq '\[dante:web01:445\]' -- $raw; echo $status) -eq 0
_test_teardown

#
# TGT_PORT alone (no TGT) still triggers yellow.
#
set -gx TGT_SCENARIO dante
set -gx TGT_ACTIVE web01
set -gx TGT_PORT 8080
set -l raw (tgt_prompt | string collect)
@test "tgt_prompt: yellow SGR when only TGT_PORT set" \
    (string match -rq '\e\[33m' -- $raw; echo $status) -eq 0
@test "tgt_prompt: label shows :8080" \
    (string match -rq ':8080\]' -- $raw; echo $status) -eq 0
_test_teardown
