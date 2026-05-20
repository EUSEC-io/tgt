// Entry point. Wires DOM inputs to state + the render pipeline,
// kicks off the initial fetch, opens the SSE stream for cross-shell
// updates, and starts the belt-and-braces fallback poll.
//
// The actual UI logic lives in the modules this file imports:
//   - state.js   — shared mutable state + timing constants
//   - helpers.js — DOM construction, fetch, toast, clipboard
//   - actions.js — `act()` / `submitForm()` + the action-result panel
//   - render.js  — sidebar / detail / refresh orchestrator
//   - forms.js   — every inline form + Alpine factories
//
// We use native `<script type="module">` (one script tag in
// index.html); the browser resolves the import tree. No bundler,
// no build step — see web/ARCHITECTURE.md for the rationale.

import { state } from './state.js';
import { renderBanner, renderSidebar, renderDetail, refresh } from './render.js';

// ────────────────────────── input wiring ──────────────────────────────
document.getElementById('filter').addEventListener('input', (e) => {
  state.filter = e.target.value;
  renderSidebar();
});
document.getElementById('show-archived').addEventListener('change', (e) => {
  state.showArchived = e.target.checked;
  renderSidebar();
});
document.getElementById('entity-search').addEventListener('input', (e) => {
  state.entitySearch = e.target.value;
  renderDetail();
});

// Theme toggle. The initial theme attribute is set by the inline
// script in index.html <head> before first paint (to avoid FOUC);
// this handler just flips and persists.
document.getElementById('theme-toggle').addEventListener('click', () => {
  const cur = document.documentElement.getAttribute('data-theme');
  const next = cur === 'light' ? 'dark' : 'light';
  document.documentElement.setAttribute('data-theme', next);
  try { localStorage.setItem('tgt-theme', next); } catch (e) {}
});

// Sidebar drawer (mobile only — desktop CSS keeps it always
// visible). Toggle on the ☰ button; close when the user clicks a
// scenario (so the drawer doesn't sit over the chosen scenario's
// detail) or taps the backdrop / hits Escape.
document.getElementById('sidebar-toggle').addEventListener('click', (e) => {
  e.stopPropagation();
  document.body.classList.toggle('sidebar-open');
});
document.addEventListener('click', (e) => {
  if (!document.body.classList.contains('sidebar-open')) return;
  if (e.target.closest('aside') || e.target.closest('#sidebar-toggle')) return;
  document.body.classList.remove('sidebar-open');
});
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') document.body.classList.remove('sidebar-open');
});
document.getElementById('scenario-list').addEventListener('click', (e) => {
  if (e.target.closest('li')) document.body.classList.remove('sidebar-open');
});

// ────────────────────────── initial load + live updates ──────────────
renderBanner();
refresh(true);

// SSE: subscribe to `/api/events`. The server emits `change`
// whenever $TGT_HOME state or the active scenario flips; we
// re-fetch on each one. EventSource auto-reconnects on disconnect
// (`retry: 3000` from the server tightens that to ~3 s). No manual
// reconnect logic.
function startEvents() {
  let es;
  try {
    es = new EventSource('/api/events');
  } catch (e) {
    // Browser without EventSource (none of our supported ones).
    // The fallback poll below still keeps the UI live.
    return;
  }
  es.addEventListener('change', () => refresh(false));
  // `ready` and `error` are useful in devtools; no UI
  // side-effects. (Errors fire on transient disconnects too —
  // EventSource handles the retry itself, so silence is correct
  // here.)
}
startEvents();

// Fallback poll. SSE is the primary signal; this catches the rare
// silent-failure case where the stream stays open but stops
// delivering. Hash dedup in refresh() makes the idle poll
// near-free.
setInterval(() => refresh(false), 60000);

// (forms.js — the module that registers all Alpine `data(…)`
// factories on alpine:init — is pulled in transitively via render.js.
// Module load order is depth-first, so the factory registrations
// land before Alpine fires alpine:init on DOMContentLoaded.)
