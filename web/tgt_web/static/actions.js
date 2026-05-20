// Server-action dispatch + the action-result panel that surfaces
// each one. Two entry points: `act()` for fire-and-forget user
// clicks (any failure surfaces in the panel) and `submitForm()`
// for form-driven calls where the caller wants to branch on
// success / failure (e.g. keep the form open and show an inline
// error). Both pipe through the same backend endpoint.

import { api, el, formatArgv } from './helpers.js';
import { refresh } from './render.js';

// Open the reusable confirm modal, then run `fn` on accept. Used
// to gate destructive operations (archive, rm, unset, revoke,
// unload). The Alpine store lives at $store.confirm — registered
// in alpine:init (see forms.js).
export function confirmThen(opts, fn) {
  const c = window.Alpine?.store('confirm');
  if (!c) { fn(); return; }   // fail open if Alpine isn't ready
  c.open = true;
  c.title = opts.title || 'Are you sure?';
  c.message = opts.message || '';
  c.preview = opts.preview || '';
  c.confirmLabel = opts.confirmLabel || 'confirm';
  c._fn = fn;
}

// Fetch the dry-run preview for `name`/`params`. Returns the
// formatted "$ tgt …" line, or '' on any failure — the modal must
// still open if the preview endpoint hiccups; missing preview is
// degraded UX, not a blocker.
async function previewArgv(name, params) {
  try {
    const r = await fetch('/api/action/preview', {
      method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({ action: name, params: params || {} }),
    });
    if (!r.ok) {
      console.warn(`preview ${name}: HTTP ${r.status}`);
      return '';
    }
    const j = await r.json();
    return j.argv ? formatArgv(j.argv) : '';
  } catch (e) {
    console.warn(`preview ${name}: ${e.message}`);
    return '';
  }
}

// Shorthand: fetch the action's argv preview, then open the
// confirm modal with that preview rendered alongside the message.
// On accept, dispatch the real action. The fetch is sub-50ms on
// localhost so the modal-open delay is imperceptible.
//
// Sequence-guard: two clicks fired back-to-back race on the
// preview fetch. Without the guard, an earlier-issued slower
// preview can overwrite a later-issued faster one — modal shows
// action A's confirm but the user clicked B last. The seq counter
// discards any result that's been superseded by a later
// confirmAct call.
let _confirmActSeq = 0;
export async function confirmAct(opts, name, params) {
  const seq = ++_confirmActSeq;
  const preview = await previewArgv(name, params);
  if (seq !== _confirmActSeq) return;
  confirmThen({...opts, preview}, () => act(name, params));
}

export async function act(name, params) {
  try {
    const r = await api('/api/action', {
      method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({ action: name, params: params || {} }),
    });
    actionResult(name, r);
    await refresh(true);
  } catch (e) {
    actionResult(name, { rc: -1, stdout: '', stderr: e.message, argv: [] });
  }
}

// Form-side dispatch. Differs from `act` in that the caller wants
// to branch on success / failure (close the form vs. surface an
// error in the form panel). Surfaces the action panel for both
// paths so the user sees what `tgt` actually said.
export async function submitForm(name, params) {
  const r = await fetch('/api/action', {
    method: 'POST', headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({ action: name, params: params || {} }),
  });
  const result = await r.json();
  actionResult(name, result);
  return { ok: r.ok && result.rc === 0, result };
}

// ────────────────────────── action panel ──────────────────────────────

// Whether the action-result panel renders in collapsed (status-
// pill) form. Toggled by the user via the −/+ button; persists in
// localStorage so it survives reloads — same pattern as the theme
// preference, consistent power-user expectation.
let _actionPanelCollapsed = (() => {
  try { return localStorage.getItem('tgt-ap-collapsed') === '1'; }
  catch (e) { return false; }
})();

// Render the sticky action-result panel. Headline always visible;
// "details" toggle reveals argv + full stdout + stderr. Replaced
// every time a new action fires; manual − minimizes, × dismisses.
export function actionResult(name, r) {
  const panel = document.getElementById('action-panel');
  const ok = r.rc === 0;
  const lastLine = (s) => (s || '').trim().split('\n').filter(Boolean).pop() || '';
  const headline = ok
    ? '✓ ' + (lastLine(r.stdout) || name)
    : '✗ ' + (lastLine(r.stderr) || lastLine(r.stdout) || `${name} (rc=${r.rc})`);

  panel.className = 'action-panel ' + (ok ? 'success' : 'error')
                  + (_actionPanelCollapsed ? ' collapsed' : '');
  panel.hidden = false;
  panel.innerHTML = '';

  const head = el('div', {class: 'ap-head'});
  head.append(el('span', {class: 'ap-headline'}, headline));

  const hasBody = (r.stdout && r.stdout.trim())
              || (r.stderr && r.stderr.trim())
              || (r.argv && r.argv.length);

  let details = null;
  if (hasBody) {
    const toggle = el('button', {class: 'ap-toggle', type: 'button'}, 'details');
    head.append(toggle);
    details = el('div', {class: 'ap-details', hidden: ''});
    if (r.argv && r.argv.length) {
      const sec = el('div', {class: 'ap-section'});
      sec.append(el('div', {class: 'ap-label'}, 'command'));
      sec.append(el('pre', {class: 'ap-argv'},
                    '$ tgt ' + r.argv.map(a => /\s/.test(a) ? `'${a}'` : a).join(' ')));
      details.append(sec);
    }
    if (r.stdout && r.stdout.trim()) {
      const sec = el('div', {class: 'ap-section'});
      sec.append(el('div', {class: 'ap-label'}, 'stdout'));
      sec.append(el('pre', {class: 'stdout'}, r.stdout.replace(/\n+$/, '')));
      details.append(sec);
    }
    if (r.stderr && r.stderr.trim()) {
      const sec = el('div', {class: 'ap-section'});
      sec.append(el('div', {class: 'ap-label'}, 'stderr'));
      sec.append(el('pre', {class: 'stderr'}, r.stderr.replace(/\n+$/, '')));
      details.append(sec);
    }
    {
      const sec = el('div', {class: 'ap-section'});
      sec.append(el('div', {class: 'ap-label'}, 'exit code'));
      sec.append(el('pre', {}, String(r.rc)));
      details.append(sec);
    }
    toggle.onclick = () => {
      if (details.hasAttribute('hidden')) {
        details.removeAttribute('hidden');
        toggle.textContent = 'hide';
      } else {
        details.setAttribute('hidden', '');
        toggle.textContent = 'details';
      }
    };
  }

  // Collapse/expand toggle. Persists in _actionPanelCollapsed (and
  // localStorage) so the next action — and the next reload — land
  // in whichever state the user last chose.
  const apLabel = (c) => c ? 'expand action panel' : 'minimize action panel';
  const collapse = el('button', {
    class: 'ap-collapse', type: 'button',
    title: _actionPanelCollapsed ? 'expand' : 'minimize',
    'aria-label': apLabel(_actionPanelCollapsed),
  }, _actionPanelCollapsed ? '+' : '−');
  collapse.onclick = () => {
    _actionPanelCollapsed = !_actionPanelCollapsed;
    panel.classList.toggle('collapsed', _actionPanelCollapsed);
    collapse.textContent = _actionPanelCollapsed ? '+' : '−';
    collapse.title = _actionPanelCollapsed ? 'expand' : 'minimize';
    collapse.setAttribute('aria-label', apLabel(_actionPanelCollapsed));
    try { localStorage.setItem('tgt-ap-collapsed', _actionPanelCollapsed ? '1' : '0'); }
    catch (e) {}
  };
  head.append(collapse);

  const close = el('button', {class: 'ap-close', type: 'button', title: 'dismiss'}, '×');
  close.onclick = () => { panel.hidden = true; };
  head.append(close);

  panel.append(head);
  if (details) panel.append(details);
}
