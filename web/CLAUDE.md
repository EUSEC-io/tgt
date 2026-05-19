# web/CLAUDE.md — rules for sessions working under web/

This directory hosts the tgt web UI (Python, pipx-installable). Claude
auto-loads this file when the working directory is web/ or a subdir.
Read it before touching anything here.

## Non-negotiables

1. **Do not modify files outside web/.** No edits to functions/,
   completions/, conf.d/, test/test_*.fish, specs/, demos/, root
   README.md, CHANGELOG.md. If a feature seems to require such a
   change, STOP and ask the user. Adding a fish verb to support a
   web feature is a separate, deliberate conversation — not a
   silent enhancement.

2. **Use only existing tgt verbs.** Confirm with
   `tgt --list-mutating-verbs --json`. If a verb is missing, that's
   a stop-and-ask moment, not an invitation to add it.

3. **Writes always shell out to `tgt`.** `subprocess.run(["tgt", ...])`,
   never reimplement save/load/krb5-sync/hosts-sync.

4. **Reads parse registry files directly** under $TGT_HOME. Same
   shape fish writes. Mirror of what _tgt_*_inspect.fish does. Use
   the unescape helper — escape layering bit us before
   (see commit 5788e76).

5. **One commit per logical change.** No bundled "web+fish",
   "feature+cleanup", "feature+test-fixture-removal" commits.

6. **Don't delete test fixtures, generated assets, or anything in
   web/tests/fixtures/ without explicit user approval.**

7. **Every new ACTIONS entry needs a matching pytest in
   web/tests/test_actions.py**, and the drift contract test
   (`test_drift.py`) must stay green.

## When you genuinely need fish to change

Surface the question. Sample phrasing:

> "Implementing <feature> cleanly needs `tgt cred edit --field value`
>  flags on the fish side (currently it's wizard-only). Should I:
>    (a) drop the feature from this PR,
>    (b) implement it via delete+recreate using existing verbs,
>    (c) start a separate fish-side conversation to add the flags?"

Wait for the user's pick. Do not assume.

## Tests

- Python: `pytest web/tests/` or `make test-web`.
- Drift contract: `pytest web/tests/test_drift.py`. Confirms every
  tgt mutating verb has an ACTIONS entry, and every ACTIONS entry
  maps to an existing tgt verb.
- `make test-all` runs fishtape + pytest + drift.

## Don't reach for

- `string escape` / `string unescape` semantics — we already had a
  data-corruption bug from layered escaping (5788e76). Use
  `tgt_web/reader.py`'s helper, don't roll your own.
- Touching gum — it's a known sore point. If you find yourself
  thinking about CLI prompts, you're in the wrong layer.
