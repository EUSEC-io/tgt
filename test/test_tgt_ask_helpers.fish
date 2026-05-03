source (status dirname)/helpers.fish

# These tests exercise the read fallback in each _tgt_ask_* helper by
# piping stdin in. Setting TGT_TEST_MODE forces the helpers to skip
# their gum branch even when gum is installed.
set -gx TGT_TEST_MODE 1

# ── _tgt_ask_text ──────────────────────────────────────────────

@test "ask_text: non-empty input returned verbatim" \
    (echo "10.10.10.5" | _tgt_ask_text "Host" "1.1.1.1") = "10.10.10.5"

@test "ask_text: empty input falls back to default" \
    (echo "" | _tgt_ask_text "Host" "1.1.1.1") = "1.1.1.1"

set -l empty_text_result (echo "" | _tgt_ask_text "Port" "")
@test "ask_text: empty default + empty input → empty output" \
    -z "$empty_text_result"

@test "ask_text: empty default + value → value" \
    (echo "8080" | _tgt_ask_text "Port" "") = "8080"

# ── _tgt_ask_choice ────────────────────────────────────────────

@test "ask_choice: valid input is returned" \
    (echo "nested" | _tgt_ask_choice "Layout" flat flat nested) = "nested"

@test "ask_choice: empty input falls back to default" \
    (echo "" | _tgt_ask_choice "Layout" flat flat nested) = "flat"

# Loops on invalid input until a valid one is read.
@test "ask_choice: invalid then valid → valid" \
    (printf "bogus\nnested\n" | _tgt_ask_choice "Layout" flat flat nested 2>/dev/null) = "nested"

# ── _tgt_ask_confirm ───────────────────────────────────────────

@test "ask_confirm: y → yes" \
    (echo "y" | _tgt_ask_confirm "Save?" n) = "yes"

@test "ask_confirm: yes → yes" \
    (echo "yes" | _tgt_ask_confirm "Save?" n) = "yes"

@test "ask_confirm: 1 → yes" \
    (echo "1" | _tgt_ask_confirm "Save?" n) = "yes"

@test "ask_confirm: n → no" \
    (echo "n" | _tgt_ask_confirm "Save?" y) = "no"

@test "ask_confirm: bogus → no (anything not yes)" \
    (echo "maybe" | _tgt_ask_confirm "Save?" y) = "no"

@test "ask_confirm: empty + default y → yes" \
    (echo "" | _tgt_ask_confirm "Save?" y) = "yes"

@test "ask_confirm: empty + default n → no" \
    (echo "" | _tgt_ask_confirm "Save?" n) = "no"

# ── _tgt_ask_password ──────────────────────────────────────────

@test "ask_password: non-empty input returned verbatim" \
    (echo "hunter2" | _tgt_ask_password "Password" no) = "hunter2"

# When has_current=yes and input is empty, return empty so the caller
# can interpret that as "keep current".
set -l empty_pw_keep (echo "" | _tgt_ask_password "Password" yes)
@test "ask_password: empty + has_current=yes → empty" \
    -z "$empty_pw_keep"

set -l empty_pw_no (echo "" | _tgt_ask_password "Password" no)
@test "ask_password: empty + has_current=no → empty" \
    -z "$empty_pw_no"

set -e TGT_TEST_MODE
