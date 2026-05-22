# Spec: Per-Terminal Sessions

Status: draft / brainstorming
Owner: stefan
Sketched: 2026-05-21 (mid-v1.1.1 conversation, deferred for later)

## Problem

`tgt` today uses fish universal-exported variables (`set -Ux`). Universal
means "every fish shell on this user account sees the same value, kept
consistent by fishd." Effectively: there is exactly one active
`(scenario, target, cred, dc)` tuple, shared across every terminal.

That breaks down the moment Stefan wants parallel work:

- Terminal 1: scan target A in scenario `acme`.
- Terminal 2: enumerate target B in scenario `htb-rastalabs`.
- Terminal 3: tunnel into a third box.

Switching `tgt` in any one of them yanks the other terminals out from
under whatever they were doing. The web UI, which mirrors fish
universals, has the same single-truth problem.

## Goal

Let multiple terminals each hold their own `(scenario, target, cred, dc)`
state simultaneously, while keeping today's "one global state" behavior
as the default for users who don't care.

## Concept: named sessions

A **session** is the runtime tuple `(scenario, active target, active
cred, active DC, hosts/krb5 state, …)`. Sessions are named (`work`,
`lab-2`, `acme-engagement`, …). They're orthogonal to scenarios:

- **Scenario** = persistent registry (targets, creds, dcs). On disk under
  `$TGT_HOME/<scenario>/`. Same as today.
- **Session** = a *binding* of a terminal to a runtime context. On disk
  under `$TGT_HOME/sessions/<name>/`. New.

Multiple sessions can point at the same scenario but with different
active targets within it. Sessions never own scenarios — they reference
them by name.

### Lifecycle

```fish
tgt session new work              # creates ~/.tgt/sessions/work/
tgt session enter work            # binds *this* terminal to "work"
tgt scenario switch acme          # affects "work" only — other sessions untouched
tgt switch dc01                   # same — only "work" sees the new target

# Other terminal:
tgt session enter lab-2           # different binding
tgt scenario switch htb-rastalabs # "lab-2" only

tgt session ls                    # list sessions, show what's active in each
tgt session rm lab-2              # tear down
```

A terminal that hasn't entered a session uses the implicit `default`
session — that's the upgrade path for existing users. Today's behavior
becomes `default` automatically.

### How it lives in fish

The session name is held in a **per-shell** env var, `$TGT_SESSION`:

- `tgt session enter <name>` sets `set -gx TGT_SESSION <name>` (NOT
  universal — only this shell).
- All `tgt` reads dispatch on `$TGT_SESSION`. State lives under
  `$TGT_HOME/sessions/$TGT_SESSION/` (a small bundle of files: `target`,
  `cred`, `dc`, `hosts`, `krb5_realm`).
- Mutations write that file, then bump the SSE broker so other
  terminals + the web UI know to refresh.

The fish universal-var store is no longer the source of truth. It can
still mirror the `default` session for backward compatibility with
prompts / external tools that read `$TGT` / `$TGT_HOSTS` etc., or we
drop it.

### How it lives in the web UI

The "what's active" line at the top of the sidebar becomes a list:

```
session       scenario           target       cred       dc
─────────────────────────────────────────────────────────────
work          acme               dc01         admin      acme-dc
lab-2         htb-rastalabs      jumpbox      svc        —
default       (none)             —            —          —
```

Click a row to focus the detail pane on *that* session's scenario. Each
mutating form gains a session scope (defaults to the focused session,
overridable via a dropdown). The current "single active scenario" UI is
the degenerate case where only `default` exists.

File watcher gains `$TGT_HOME/sessions/` to its watch set; everything
else stays the same.

### Effect on /etc/hosts

Hairy. `/etc/hosts` is global to the box, not a per-process thing. So:

- Target *identity* (alias, host record, krb5 ccache via `KRB5CCNAME`)
  can be per-session.
- `/etc/hosts` rewriting cannot. Two sessions wanting two different
  short-name → IP mappings collide.
- Workaround A: hosts entries are namespaced by session (`work_dc01`
  instead of `dc01`). Ugly but workable; aliases just become longer.
- Workaround B: hosts entries are union — every session's entries
  coexist. Works as long as no two sessions claim the same short name.
- Workaround C: drop per-session /etc/hosts entirely; tools accept FQDNs.
  Cleanest semantics, breaks "smb://dc01" muscle memory.

Probably C with B as fallback. Worth a separate conversation.

### Effect on krb5

`KRB5CCNAME` is already per-process — every shell can have its own
ccache. The fish-side `_tgt_krb5_write` would write to
`~/.tgt/sessions/<name>/krb5.conf` and source it on `session enter`.
Cleaner than the global `/etc/krb5.conf.d/` write we do today (though
that still has a place for hosts-wide trust setup).

## Open questions

1. **Unit of separation.** Is the split `(scenario + target)` or just
   `target`? I.e., do you ever want one terminal on `acme/dc01` and
   another on `acme/web` (same scenario, different target)? Or is each
   parallel work-stream usually a different *scenario*? This decides
   whether sessions can share a scenario, and how the web UI groups them.

2. **Realistic concurrency.** 2-3 sessions (one client + a side-quest)
   vs 5-10 (juggling clients). The UI design for 3 differs from 10.

3. **`/etc/hosts` model.** See workarounds A / B / C above. Pick one.

4. **Cross-session ops from CLI.** Do you want `tgt --session lab-2 show`
   to peek at another session's state from yours? Useful but adds
   surface (`--session` on every command).

5. **Migration.** New users: `default` is fine, never see the concept.
   Existing users with universal vars set: do we auto-import them into
   `default` on first run, or leave them be?

## What's out of scope here

- Container / network-namespace isolation. Different problem (sandboxing,
  not parallel work). Save for a different spec.
- tmux/screen auto-derivation of session name. Cute but couples us to a
  multiplexer. Maybe a v2 ergonomics PR.
- Multi-user / team sync. Sessions are local-only.

## Estimated cost

Big. Not a small change. Touches:

- Every fish mutating verb (read/write a per-session file instead of a
  universal).
- Every fish helper that reads `$TGT*` (route via `$TGT_SESSION`).
- The web UI sidebar (sessions panel) + every form (session scope).
- The drift contract (action params gain `session`).
- The SSE broker (events tagged by session).
- The file watcher (watch `sessions/` too).
- Docs / README / CHANGELOG / migration notes.

Probably a v2.0 milestone, not a v1.x patch. Worth doing the design
honestly before any code lands.
