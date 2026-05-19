# Architecture & framework choices

This doc captures the load-bearing decisions for `tgt-web` so future
contributors (and future iterations of this session) don't drift.
It's prescriptive on purpose — the goal is a tool that ships as one
`pipx install` and stays diff-able by a human reader, not an SPA.

## What `tgt-web` is

A localhost-only dashboard for the `tgt` fish plugin. Single user,
no auth, same threat model as `fish_config`. Reads parse `$TGT_HOME`
directly; writes always shell out to `tgt`. The plugin owns the
business logic; this layer is presentation + dispatch.

## Architectural principles (do not break)

1. **stdlib-only Python.** No FastAPI, no Flask, no SQLAlchemy. The
   wheel must be installable on a fresh Parrot box with no network
   beyond the install itself.
2. **No build step, ever.** No npm, no Vite, no transpilation, no
   bundlers. Every JS/CSS file in `static/` is what gets served. If
   a future framework requires a build step, it's the wrong
   framework.
3. **Vendor everything.** Pentest hosts go offline. CDN script tags
   are forbidden. Third-party JS/CSS lives in `static/vendor/`
   pinned to a specific version and checked into git. A single
   `curl > vendor/foo-1.2.3.min.js` per dependency, attribution in
   `static/vendor/README.md`.
4. **Three layers, one direction.** `reader` (pure, parses disk) →
   `actions` (whitelisted dispatch to `tgt`) → `server` (HTTP). UI
   lives behind `server` and never reaches around it. Never the
   reverse — `reader` doesn't call `actions`, `actions` doesn't read
   files outside what `tgt` controls.
5. **`tgt` owns mutation.** Whitelisted actions only. Client never
   sends raw argv. New verbs land in `ACTIONS` + `tgt
   --list-mutating-verbs --json` in lock-step; the drift contract
   test fails CI otherwise.
6. **Localhost-only.** `127.0.0.1`. Don't add `--host`, don't add
   auth, don't add CORS. If multi-user remote ever becomes a real
   use case, that's a separate tool — not an option flag here.

## Framework strategy

| Layer | Today | When to add | Library | Why |
|---|---|---|---|---|
| Backend | `http.server` (stdlib) | Never | — | Tiny surface; routes are one regex each. |
| DOM rendering (read-only views) | Vanilla + `el()` helper | Never | — | The dashboard is a list + a detail pane. Doesn't justify a runtime. |
| Form state (open/closed, validated, draft values) | — | When the first form lands (Phase 2 step 3) | **Alpine.js**, vendored | ~10 kb, single `<script>`, attribute-driven (`x-data`, `x-model`, `x-show`). Adds state ergonomics without touching the existing render path. No virtual DOM, no JSX, no build. |
| Server-rendered form partials | — | When 3+ forms exist and validation duplicates across client + server | **htmx**, vendored | ~14 kb, single tag. Form posts return HTML fragments (`hx-target="#detail"`), keeping validation in Python. Pairs naturally with the stdlib backend. |
| Cross-shell live updates | 10 s polling | Phase 3, after forms stabilize | **SSE** via `http.server` + (if we have htmx) `hx-sse` | `text/event-stream` is stdlib. Kills the poll, no WebSocket complexity. |
| Styling | ~100 lines of vanilla CSS | When the design grows past ~3 entity types' worth of forms | Custom CSS variables, no framework | Tailwind/etc. force a build step. The current stylesheet scales fine for the entity count. |
| Icons | Unicode glyphs (★ ↻ ✓) | If we run out of glyphs that read clearly | Inline SVG, vendored | Icon fonts pull in MB of unused glyphs; SVGs are diffable. |

### Explicitly REJECTED

- **React / Vue / Svelte / Solid / any SPA framework.** Wrong tool;
  this is a 5-route admin UI, not an SPA. Brings npm, a bundler, and
  a runtime ≥30 kb. The Alpine + htmx pair covers the same use cases
  at a tenth the cost.
- **TypeScript build pipelines.** Type-check `app.js` with editor
  tooling if you want, but no transpilation step is shipped. JSDoc
  type comments are fine; `.ts` files are not.
- **CSS frameworks (Tailwind / Bootstrap / Bulma).** Tailwind needs a
  build step. Bootstrap/Bulma bring jQuery-era baggage. Vanilla CSS
  variables solve our actual problem (consistent palette + spacing).
- **State management libraries (Redux, Zustand, MobX).** The state
  fits in a `const state = {…}` object. If it ever doesn't, that's a
  signal the UI grew too much, not that we need Redux.
- **Routing libraries.** We have one route: `/`. The current
  master/detail is selection-driven, not URL-driven. If shareable
  URLs become a requirement, do it with `history.pushState` + a
  20-line dispatcher, not a router package.

## Vendoring rules

When Phase 2 first reaches for Alpine:

```bash
mkdir -p web/tgt_web/static/vendor
curl -L https://unpkg.com/alpinejs@3.x.x/dist/cdn.min.js \
  -o web/tgt_web/static/vendor/alpine-3.x.x.min.js
# also fetch the .map if available; pin both
```

Then:

- Reference with `<script src="/static/vendor/alpine-3.x.x.min.js" defer>`.
- Pin to a specific patch version in the filename. Bumping = an
  explicit PR with a diff of the vendored file.
- Add to `static/vendor/README.md`: source URL, version, license,
  SHA-256 of the fetched file.
- Update `pyproject.toml`'s `package-data` to include `vendor/*`.

The same rules apply to htmx when its turn comes.

## What the three modules guarantee

- **`reader.py`** — Pure I/O over `$TGT_HOME`. Never imports from
  `actions` or `server`. Adding a new field type means adding a
  parser here and surfacing it in `scenario_detail`. Cached values
  (`_active_cache`) are an implementation detail and tests
  monkeypatch around them.
- **`actions.py`** — The whitelist. Every entry is `(argv builder,
  required params)`. Adding a new verb means: entry here + row in
  `tgt --list-mutating-verbs --json` (fish-side) + UI button. The
  drift test enforces the first two; you'll know about the third
  the moment you try to use the feature.
- **`server.py`** — Routes only. Should be the file you touch *least*
  often. New endpoints fit in 5–10 lines (regex + handler call); if
  one needs more, the logic belongs in `reader` or `actions`.

## Testing surface

- `tests/test_reader.py` — fixtures under `tests/fixtures/scenarios/`
  capture every escape form fish emits, including the
  corrupted-single-quote (`"'"`) regression. New parsers MUST get a
  fixture + test.
- `tests/test_actions.py` — `subprocess.run` is mocked. The argv
  builder is the thing under test, plus the env/stdin guarantees
  (`TGT_NO_GUM=1`, `stdin=DEVNULL`, `SUDO_ASKPASS` injection).
- `tests/test_sudo.py` — askpass probe strategies with
  `shutil.which` mocked. Never touches the user's real `~/.cache`.
- `tests/test_http.py` — Spins up a real server in a thread + hits
  endpoints. Slowest but exercises the full path.
- `tests/test_drift.py` — Auto-sources every `*.fish` in
  `../functions/` so it works on a clean checkout without `make
  dev`. Skips gracefully when fish isn't on PATH.

When in doubt, prefer adding a test under `test_reader` (cheap,
hermetic) over `test_http` (slow, full-stack).

## When to revisit this doc

Update or extend whenever:

- A framework decision in the table changes (e.g. we actually pull
  in htmx — note when, why, and what shape the integration took).
- A new module joins the three-layer model.
- The "explicitly REJECTED" list grows or shrinks.
- A `tgt` capability ships that needs structural support here
  (e.g. workspace file browser would justify a real `/api/files/`
  subtree; that's an architectural addition worth documenting).

Don't rewrite this doc for tactical PRs. It's the load-bearing
intent; PR descriptions are for tactical changes.
