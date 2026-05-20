// ────────────────────────── state + cache ─────────────────────────────
const state = {
  selected: null,        // scenario name currently shown in detail pane
  filter: '',            // sidebar substring filter
  entitySearch: '',      // detail-pane substring filter (across t/c/d)
  showArchived: false,   // toggle for hiding archived scenarios
  scenariosHash: '',     // for skip-render-on-no-change
  detailHash: '',
  scenariosData: [],     // cache so filter/toggle don't refetch
  detailData: null,
  // True while the ports manager owns its slice of the screen. The
  // detail-pane re-render is suppressed in that case so SSE / poll
  // refreshes don't wipe the open form (and the user's in-flight
  // comment edits). Set by openPortsManager; cleared in close().
  managingPorts: false,
};

// ────────────────────────── helpers ───────────────────────────────────
async function api(path, opts) {
  const r = await fetch(path, opts);
  if (!r.ok) throw new Error(await r.text());
  return r.json();
}

function djb2(s) {
  let h = 5381;
  for (let i = 0; i < s.length; i++) h = ((h << 5) + h) ^ s.charCodeAt(i);
  return h.toString(16);
}

function toast(msg, kind) {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.className = 'toast show ' + (kind || '');
  setTimeout(() => { t.className = 'toast'; }, 2500);
}

// Write `text` to the system clipboard. Requires a secure context;
// localhost qualifies, so the browser exposes navigator.clipboard.
async function copyToClipboard(text, label) {
  if (!text) { toast('nothing to copy', 'error'); return; }
  try {
    await navigator.clipboard.writeText(text);
    toast(label ? `copied ${label}` : 'copied', 'success');
  } catch (e) {
    toast('copy failed: ' + e.message, 'error');
  }
}

// Substring-match predicate over a list of haystack fields. Empty
// needle matches everything (search-off is the default). All match
// is case-insensitive. Used by entity-search filters below.
function _entityMatch(needle) {
  if (!needle) return () => true;
  const n = needle.toLowerCase();
  return (fields) => fields.some(s => s && s.toLowerCase().includes(n));
}
// Per-entity field projections — kept tight (no password / cred-id /
// archive markers) so a search for "admin" returns entities whose
// human-visible content actually mentions "admin".
function _filterTargets(targets, needle) {
  const m = _entityMatch(needle);
  return targets.filter(t => m([t.alias, t.host, ...(t.hosts || [])]));
}
function _filterCreds(creds, needle) {
  const m = _entityMatch(needle);
  return creds.filter(c => m([c.alias, c.username, c.domain, c.notes]));
}
function _filterDCs(dcs, needle) {
  const m = _entityMatch(needle);
  return dcs.filter(dc => m([dc.alias, dc.domain, dc.realm,
                              dc.kdc_host, dc.kdc_ip,
                              dc.admin_host, dc.admin_ip]));
}

// Generic single-string value cell. Shows the value with a copy icon
// that appears on hover. Falls back to a plain em-dash for empties so
// dashes don't accidentally end up on the clipboard.
function valueCell(text, label) {
  if (!text) return document.createTextNode('—');
  return el('span', {class: 'vc'},
    el('span', {class: 'vc-text'}, text),
    el('button', {
      class: 'vc-copy', type: 'button', title: 'copy',
      onclick: (e) => { e.stopPropagation(); copyToClipboard(text, label || ''); },
    }, '⧉'));
}

function el(tag, attrs, ...children) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (k === 'onclick') e.onclick = v;
    else if (k === 'class') e.className = v;
    else e.setAttribute(k, v);
  }
  for (const c of children) {
    if (c == null || c === false) continue;
    e.append(typeof c === 'string' ? document.createTextNode(c) : c);
  }
  return e;
}

// Open the reusable confirm modal, then run `fn` on accept. Used to
// gate destructive operations (archive, rm, unset, revoke, unload).
// The Alpine store lives at $store.confirm — registered in alpine:init.
function confirmThen(opts, fn) {
  const c = window.Alpine?.store('confirm');
  if (!c) { fn(); return; }   // fail open if Alpine isn't ready
  c.open = true;
  c.title = opts.title || 'Are you sure?';
  c.message = opts.message || '';
  c.preview = opts.preview || '';
  c.confirmLabel = opts.confirmLabel || 'confirm';
  c._fn = fn;
}

// Format an argv as the user-facing `$ tgt arg1 'arg with space'`
// line. Single-quotes anything containing whitespace so the line
// stays paste-runnable as-is. Same shape the action-result panel
// shows post-execution, so pre / post views look consistent.
function _formatArgv(argv) {
  return '$ tgt ' + argv.map(a => /\s/.test(a) ? `'${a}'` : a).join(' ');
}

// Fetch the dry-run preview for `name`/`params`. Returns the
// formatted "$ tgt …" line, or '' on any failure — the modal must
// still open if the preview endpoint hiccups; missing preview is
// degraded UX, not a blocker.
async function _previewArgv(name, params) {
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
    return j.argv ? _formatArgv(j.argv) : '';
  } catch (e) {
    console.warn(`preview ${name}: ${e.message}`);
    return '';
  }
}

// Shorthand: fetch the action's argv preview, then open the confirm
// modal with that preview rendered alongside the message. On accept,
// dispatch the real action. The fetch is sub-50ms on localhost so
// the modal-open delay is imperceptible.
//
// Sequence-guard: two clicks fired back-to-back race on the preview
// fetch. Without the guard, an earlier-issued slower preview can
// overwrite a later-issued faster one — modal shows action A's
// confirm but the user clicked B last. The seq counter discards
// any result that's been superseded by a later confirmAct call.
let _confirmActSeq = 0;
async function confirmAct(opts, name, params) {
  const seq = ++_confirmActSeq;
  const preview = await _previewArgv(name, params);
  if (seq !== _confirmActSeq) return;
  confirmThen({...opts, preview}, () => act(name, params));
}

async function act(name, params) {
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

// Form-side dispatch. Differs from `act` in that the caller wants to
// branch on success/failure (close the form vs. surface an error in
// the form panel). Surfaces the action panel for both paths so the
// user sees what `tgt` actually said.
async function _submitForm(name, params) {
  const r = await fetch('/api/action', {
    method: 'POST', headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({ action: name, params: params || {} }),
  });
  const result = await r.json();
  actionResult(name, result);
  return { ok: r.ok && result.rc === 0, result };
}

// Whether the action-result panel renders in collapsed (status-pill)
// form. Toggled by the user via the −/+ button; persists in
// localStorage so it survives reloads — same pattern as the theme
// preference, consistent power-user expectation.
let _actionPanelCollapsed = (() => {
  try { return localStorage.getItem('tgt-ap-collapsed') === '1'; }
  catch (e) { return false; }
})();

// Render the sticky action-result panel. Headline always visible;
// "details" toggle reveals argv + full stdout + stderr. Replaced
// every time a new action fires; manual − minimizes, × dismisses.
function actionResult(name, r) {
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
  // localStorage) so the next action — and the next reload — land in
  // whichever state the user last chose.
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

// Password reveal — Alpine-driven via the `credPw` data factory
// (registered in alpine:init). Each cell owns its own state machine:
// fetch on demand, auto-hide after a timeout, pause while the user
// is hovering the revealed value, copy without revealing.
function passwordUrl(scenario, alias) {
  return `/api/scenarios/${encodeURIComponent(scenario)}/creds/${encodeURIComponent(alias)}/password`;
}

// How long a revealed password stays on screen before auto-re-masking.
// Tuned so a glance is enough; hover pauses the timer for longer reads.
const PW_AUTO_HIDE_MS = 10000;
const PW_AUTO_HIDE_MIN_RESUME_MS = 3000;

// ────────────────────────── render: startup banner ────────────────────
async function renderBanner() {
  try {
    const s = await api('/api/status');
    const msgs = [];
    if (s.version_mismatch) {
      msgs.push(`⚠ ${s.version_note} — install the matching tgt-web with: pipx install --force "git+https://github.com/EUSEC-io/tgt#subdirectory=web"`);
    }
    if (s.sudo && !s.sudo.askpass && !s.sudo.nopasswd) {
      msgs.push('⚠ sudo: ' + s.sudo.note.split('\n')[0] + ' (see startup log for install hints)');
    }
    const b = document.getElementById('banner');
    if (msgs.length) {
      b.textContent = msgs.join(' · ');
      b.hidden = false;
    } else {
      b.hidden = true;
    }
  } catch (e) {
    // /api/status is best-effort; never block the dashboard for this.
  }
}

// ────────────────────────── render: sidebar ───────────────────────────
function renderSidebar() {
  const list = document.getElementById('scenario-list');
  list.innerHTML = '';
  const filtered = state.scenariosData.filter(s => {
    if (!state.showArchived && s.archived) return false;
    if (state.filter && !s.name.toLowerCase().includes(state.filter.toLowerCase())) return false;
    return true;
  });
  if (filtered.length === 0) {
    list.append(el('li', {class: 'empty'}, '(no matches)'));
    return;
  }
  for (const s of filtered) {
    const li = el('li', {
      class: [
        s.active ? 'active' : '',
        s.archived ? 'archived' : '',
        s.name === state.selected ? 'selected' : '',
      ].filter(Boolean).join(' '),
      onclick: () => {
        state.selected = s.name;
        refresh(true);
      },
    },
      el('span', {class: 'name'}, s.name),
      el('span', {class: 'counts'},
         `${s.target_count}t · ${s.cred_count}c · ${s.dc_count}d`));
    list.append(li);
  }
}

function renderActiveInfo() {
  const el2 = document.getElementById('active-info');
  const active = state.scenariosData.find(s => s.active);
  if (active) {
    el2.innerHTML = '';
    el2.append(document.createTextNode('active: '));
    el2.append(el('span', {class: 'active-name'}, active.name));
  } else {
    el2.textContent = '(no active scenario)';
  }
}

// ────────────────────────── render: detail ────────────────────────────
function renderDetail() {
  const main = document.getElementById('detail');
  main.innerHTML = '';
  const d = state.detailData;
  const searchBar = document.getElementById('entity-search-bar');
  if (!d) {
    main.append(el('div', {class: 'placeholder'}, 'Select a scenario from the list.'));
    searchBar.hidden = true;
    return;
  }
  searchBar.hidden = false;

  // Title + meta
  main.append(el('div', {class: 'scen-title'}, d.name));
  const meta = el('div', {class: 'scen-meta'});
  if (d.active) meta.append(el('span', {class: 'badge active'}, 'ACTIVE'));
  if (d.archived) meta.append(el('span', {class: 'badge archived'}, 'ARCHIVED'));
  meta.append(document.createTextNode(
    `${d.targets.length} target(s), ${d.creds.length} cred(s), ${d.dcs.length} DC(s)`));
  main.append(meta);

  // Scenario-level actions
  const actions = el('div', {class: 'scen-actions'});
  if (d.active) {
    actions.append(el('button', {onclick: () => confirmAct({
      title: 'Unload active scenario?',
      message: `This clears the active scenario marker and all live TGT_* runtime in fish. The scenario itself stays on disk.`,
      confirmLabel: 'unload',
    }, 'scenario_unload')}, 'unload'));
  } else {
    actions.append(el('button', {class: 'primary',
      onclick: () => act('scenario_switch', {name: d.name})}, 'switch to'));
  }
  if (d.archived) {
    actions.append(el('button', {
      onclick: () => act('scenario_unarchive', {name: d.name}),
    }, 'unarchive'));
  } else {
    actions.append(el('button', {
      onclick: () => confirmAct({
        title: `Archive scenario "${d.name}"?`,
        message: 'Archived scenarios are hidden from the default list (toggle "show archived" to see them). Nothing on disk is deleted.',
        confirmLabel: 'archive',
      }, 'scenario_archive', {name: d.name}),
    }, 'archive'));
  }
  main.append(actions);

  // Entity-search filtering. Each section renders the filtered subset
  // but shows "N of M" in the header so the user can see what's hidden.
  const q = state.entitySearch;
  const targets = _filterTargets(d.targets, q);
  const creds = _filterCreds(d.creds, q);
  const dcs = _filterDCs(d.dcs, q);
  const sectionCount = (filtered, total) =>
    (q && filtered !== total) ? `${filtered} of ${total}` : `${total}`;
  const sectionEmpty = (total) =>
    el('div', {class: 'empty'}, q && total > 0 ? '(no matches)' : '(none)');
  // Aggregate counters for the search bar's "X results" tag.
  const totalMatches = targets.length + creds.length + dcs.length;
  const totalAll = d.targets.length + d.creds.length + d.dcs.length;
  const countEl = document.getElementById('entity-search-count');
  countEl.textContent = (q && totalMatches !== totalAll)
    ? `${totalMatches} of ${totalAll} match` : '';

  // Targets — wrapped in an Alpine scope for the edit form
  // (no `new` form on the web yet since fish-side `target new`
  // only accepts an alias without field flags).
  const targetSection = el('div', {
    'x-data': `targetEditForm(${JSON.stringify(d.name)})`,
    'data-edit-scope': 'target',
  });
  targetSection.append(el('h2', {},
    `targets (${sectionCount(targets.length, d.targets.length)})`));
  targetSection.append(buildTargetEditForm());
  // Ports manager — separate Alpine scope (same pattern as the
  // edit scopes). Opens prefilled when any target row's "ports"
  // button is clicked.
  const portsScope = el('div', {
    'x-data': `portsManager(${JSON.stringify(d.name)})`,
    'data-edit-scope': 'ports',
  });
  portsScope.append(buildPortsManagerForm());
  targetSection.append(portsScope);
  if (targets.length === 0) targetSection.append(sectionEmpty(d.targets.length));
  else targetSection.append(el('div', {class: 'table-scroll'}, el('table', {},
    el('thead', {}, el('tr', {}, el('th', {}, 'alias'), el('th', {}, 'host'),
                        el('th', {}, 'hostnames'), el('th', {}, 'ports'),
                        el('th', {}, ''))),
    el('tbody', {}, ...targets.map(t => el('tr', {},
      el('td', {class: t.active ? 'active' : ''}, t.alias),
      el('td', {}, valueCell(t.host, 'host')),
      el('td', {}, t.hosts.length
        ? el('span', {class: 'vc-chips'}, ...t.hosts.map(h => valueCell(h, 'hostname')))
        : document.createTextNode('—')),
      el('td', {},
        el('button', {
          class: 'ports-link',
          onclick: () => openPortsManager(d.name, t),
        }, t.ports && t.ports.length
            ? `${t.ports.length} port${t.ports.length === 1 ? '' : 's'}`
            : '+ add')),
      el('td', {class: 'row-actions'},
        d.active && !t.active
          ? el('button', {onclick: () => act('target_switch', {alias: t.alias})}, 'switch')
          : (t.active ? el('button', {onclick: () => confirmAct({
              title: 'Revoke active target?',
              message: `Clears the active-target marker and TGT / TGT_PORT / TGT_HOSTS / TGT_ACTIVE runtime in fish. Also removes "${t.alias}"'s entries from /etc/hosts. The target record stays on disk; creds + DC are unaffected.`,
              confirmLabel: 'revoke',
            }, 'target_revoke')}, 'revoke') : ''),
        el('button', {onclick: () => openTargetEdit(d.name, t)}, 'edit'))))))));
  main.append(targetSection);

  // Creds — wrapped in an Alpine scope so the "+ new" button can
  // open the inline create form (state: open / fields / submitting /
  // error). See `credNewForm` factory at the bottom of this file.
  //
  // JSON.stringify produces a valid JS string literal — handles the
  // single-quote / backslash cases that would otherwise break the
  // attribute. Current validators reject `'` in scenario / cred
  // names, but the template stays robust if that ever loosens.
  const credSection = el('div', { 'x-data': `credNewForm(${JSON.stringify(d.name)})` });
  credSection.append(el('h2', {},
    `credentials (${sectionCount(creds.length, d.creds.length)}) `,
    el('button', { 'class': 'add', 'type': 'button', '@click': 'open = true' },
      '+ new'),
  ));
  credSection.append(buildCredNewForm());
  // Edit form lives in its own nested Alpine scope. Triggered via
  // `openCredEdit(scenario, cred)` from row buttons — that helper
  // looks the scope up by `data-edit-scope` and pokes the state in.
  const credEditScope = el('div', {
    'x-data': `credEditForm(${JSON.stringify(d.name)})`,
    'data-edit-scope': 'cred',
  });
  credEditScope.append(buildCredEditForm());
  credSection.append(credEditScope);
  if (creds.length === 0) credSection.append(sectionEmpty(d.creds.length));
  else credSection.append(el('div', {class: 'table-scroll'}, el('table', {},
    el('thead', {}, el('tr', {}, el('th', {}, 'alias'), el('th', {}, 'username'),
                        el('th', {}, 'password'), el('th', {}, 'domain'),
                        el('th', {}, 'notes'), el('th', {}, ''))),
    el('tbody', {}, ...creds.map(c => {
      const pwCell = c.has_password
        ? el('span', { 'x-data': `credPw(${JSON.stringify(d.name)}, ${JSON.stringify(c.alias)})`, 'class': 'pw-cell' },
            el('span', {
              'class': 'reveal',
              'x-show': '!revealed',
              '@click': 'reveal()',
            }, 'reveal'),
            el('button', {
              'class': 'vc-copy pw-copy',
              'x-show': '!revealed',
              'type': 'button', 'title': 'copy password',
              '@click': 'copy()',
            }, '⧉'),
            el('span', {
              'class': 'pw-value',
              'x-show': 'revealed',
              'x-text': "value || '…'",
              '@mouseenter': 'pauseTimer()',
              '@mouseleave': 'resumeTimer()',
            }),
            el('span', {
              'class': 'reveal hide-link',
              'x-show': 'revealed',
              '@click': 'hide()',
            }, 'hide'),
            el('button', {
              'class': 'vc-copy pw-copy',
              'x-show': 'revealed',
              'type': 'button', 'title': 'copy password',
              '@click': 'copy()',
            }, '⧉'))
        : document.createTextNode('—');
      return el('tr', {},
        el('td', {class: c.active ? 'active' : ''}, c.alias),
        el('td', {}, valueCell(c.username, 'username')),
        el('td', {}, pwCell),
        el('td', {}, valueCell(c.domain, 'domain')),
        el('td', {}, c.notes || '—'),
        el('td', {class: 'row-actions'},
          d.active && !c.active
            ? el('button', {onclick: () => act('cred_switch', {alias: c.alias})}, 'switch')
            : (c.active ? el('button', {onclick: () => confirmAct({
                title: 'Unset active credential?',
                message: `Clears the active-cred marker in "${d.name}" and all TGT_CRED_* runtime in fish. The cred record stays on disk.`,
                confirmLabel: 'unset',
              }, 'cred_unset')}, 'unset') : ''),
          el('button', {onclick: () => openCredEdit(d.name, c)}, 'edit'),
          el('button', {onclick: () => {
            const next = window.prompt(`Rename "${c.alias}" to:`, c.alias);
            if (!next || next === c.alias) return;
            act('cred_rename', {old: c.alias, new: next});
          }}, 'rename'),
          el('button', {onclick: () => confirmAct({
            title: `Delete credential "${c.alias}"?`,
            message: `Removes the cred record from "${d.name}". If it's the active cred, the marker + TGT_CRED_* runtime are also cleared.`,
            confirmLabel: 'delete',
          }, 'cred_rm', {alias: c.alias})}, 'rm')));
    })))));
  main.append(credSection);

  // DCs — wrapped in an Alpine scope so the "+ new" button can
  // open the inline create form. Mirrors the credSection pattern.
  const dcSection = el('div', { 'x-data': `dcNewForm(${JSON.stringify(d.name)})` });
  dcSection.append(el('h2', {},
    `DCs (${sectionCount(dcs.length, d.dcs.length)}) `,
    el('button', { 'class': 'add', 'type': 'button', '@click': 'open = true' },
      '+ new'),
  ));
  dcSection.append(buildDcNewForm());
  const dcEditScope = el('div', {
    'x-data': `dcEditForm(${JSON.stringify(d.name)})`,
    'data-edit-scope': 'dc',
  });
  dcEditScope.append(buildDcEditForm());
  dcSection.append(dcEditScope);
  if (dcs.length === 0) dcSection.append(sectionEmpty(d.dcs.length));
  else dcSection.append(el('div', {class: 'table-scroll'}, el('table', {},
    el('thead', {}, el('tr', {}, el('th', {}, 'alias'), el('th', {}, 'domain'),
                        el('th', {}, 'realm'), el('th', {}, 'kdc'),
                        el('th', {}, 'admin'), el('th', {}, ''))),
    el('tbody', {}, ...dcs.map(dc => el('tr', {},
      el('td', {class: dc.active ? 'active' : ''}, dc.alias),
      el('td', {}, valueCell(dc.domain, 'domain')),
      el('td', {}, valueCell(dc.realm, 'realm')),
      el('td', {}, valueCell(dc.kdc_host || dc.kdc_ip, 'kdc')),
      el('td', {}, valueCell(dc.admin_host || dc.admin_ip, 'admin')),
      el('td', {class: 'row-actions'},
        d.active && !dc.active
          ? el('button', {onclick: () => act('dc_switch', {alias: dc.alias})}, 'switch')
          : (dc.active ? el('button', {onclick: () => confirmAct({
              title: 'Unset active DC?',
              message: `Clears the active-DC marker in "${d.name}" and all TGT_DC_* runtime. The DC record stays on disk.`,
              confirmLabel: 'unset',
            }, 'dc_unset')}, 'unset') : ''),
        el('button', {onclick: () => openDcEdit(d.name, dc)}, 'edit'))))))));
  main.append(dcSection);
}

// ────────────────────────── refresh orchestrator ──────────────────────
// `force=true` always re-renders. Without force, we hash the new data
// and skip the DOM rebuild when nothing changed — that kills the flicker
// during idle polling, while still picking up cross-shell state changes.
async function refresh(force) {
  try {
    const scenarios = await api('/api/scenarios');
    const sHash = djb2(JSON.stringify(scenarios));
    if (force || sHash !== state.scenariosHash) {
      state.scenariosData = scenarios;
      state.scenariosHash = sHash;
      renderSidebar();
      renderActiveInfo();
    }
    // If nothing's selected yet, fall back to the active scenario.
    const target = state.selected
      || (state.scenariosData.find(s => s.active) || {}).name;
    if (target) {
      const detail = await api(`/api/scenarios/${encodeURIComponent(target)}`);
      const dHash = djb2(JSON.stringify(detail));
      if (force || dHash !== state.detailHash) {
        state.detailData = detail;
        state.detailHash = dHash;
        state.selected = target;       // sync selection if it came from active
        // While the ports manager owns its slice of the screen,
        // skip the detail re-render — otherwise SSE / poll bumps
        // wipe the open form (and the user's in-flight comment
        // edits across multiple rows). `state.detailData` is still
        // updated, so the manager's `close()` can pull fresh data
        // and the next refresh after close picks it all up.
        if (!state.managingPorts) {
          renderDetail();
          // Re-render sidebar so the "selected" highlight tracks the detail pane.
          renderSidebar();
        }
      }
    }
  } catch (e) {
    toast('refresh failed: ' + e.message, 'error');
  }
}

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

// Theme toggle. Initial theme attribute is set by the inline script in
// index.html <head> before first paint (to avoid FOUC); this handler
// just flips and persists.
document.getElementById('theme-toggle').addEventListener('click', () => {
  const cur = document.documentElement.getAttribute('data-theme');
  const next = cur === 'light' ? 'dark' : 'light';
  document.documentElement.setAttribute('data-theme', next);
  try { localStorage.setItem('tgt-theme', next); } catch (e) {}
});

// Sidebar drawer (mobile only — desktop CSS keeps it always visible).
// Toggle on the ☰ button; close when the user clicks a scenario
// (so the drawer doesn't sit over the chosen scenario's detail) or
// taps the backdrop / hits Escape.
const _sidebarToggle = document.getElementById('sidebar-toggle');
_sidebarToggle.addEventListener('click', (e) => {
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

// ────────────────────────── forms: cred new ───────────────────────────
// Inline form for `tgt cred new`. Pattern to repeat for other forms:
//   - `buildXForm()` returns the DOM (Alpine binds via attributes)
//   - `xForm()` factory registered on `alpine:init` owns state + submit
function buildCredNewForm() {
  return el('div', { 'x-show': 'open', 'class': 'form-card' },
    el('div', {class: 'form-title'}, 'new credential'),
    el('div', {class: 'form-error', 'x-show': 'error', 'x-text': 'error'}),
    el('form', { '@submit.prevent': 'submit' },
      el('label', {},
        el('span', {class: 'form-label'}, 'alias'),
        el('input', {
          'x-model.trim': 'alias', 'required': '', 'autocomplete': 'off',
          'placeholder': 'e.g. admin',
        })),
      el('label', {},
        el('span', {class: 'form-label'}, 'username'),
        el('input', {
          'x-model.trim': 'username', 'required': '', 'autocomplete': 'off',
          'placeholder': "e.g. Administrator or DOMAIN\\user",
        })),
      el('label', {},
        el('span', {class: 'form-label'}, 'password'),
        el('div', {class: 'pw-input-row'},
          el('input', {
            'x-model': 'password',
            ':type': "showPassword ? 'text' : 'password'",
            'autocomplete': 'new-password',
          }),
          el('button', {
            'type': 'button', 'class': 'pw-toggle',
            '@click': 'showPassword = !showPassword',
            'x-text': "showPassword ? 'hide' : 'show'",
          }))),
      el('label', {},
        el('span', {class: 'form-label'}, 'domain'),
        el('input', {
          'x-model.trim': 'domain', 'autocomplete': 'off',
          'placeholder': 'optional',
        })),
      el('label', {},
        el('span', {class: 'form-label'}, 'notes'),
        el('textarea', { 'x-model': 'notes', 'rows': '2' })),
      el('div', {class: 'form-buttons'},
        el('button', {
          'type': 'button', '@click': 'cancel()',
        }, 'cancel'),
        el('button', {
          'type': 'submit', 'class': 'primary',
          ':disabled': 'submitting',
          'x-text': "submitting ? 'saving…' : 'create'",
        }))));
}

// ────────────────────────── forms: cred edit ─────────────────────────
// Same field set as `cred new` plus a read-only alias display. The
// password input prefills with the current stored value (fetched by
// `openCredEdit`); clearing it and submitting clears it on disk.
function buildCredEditForm() {
  return el('div', { 'x-show': 'open', 'class': 'form-card' },
    el('div', {class: 'form-title'}, 'edit credential'),
    el('div', {class: 'form-error', 'x-show': 'error', 'x-text': 'error'}),
    el('form', { '@submit.prevent': 'submit' },
      el('label', {},
        el('span', {class: 'form-label'}, 'alias'),
        el('input', {
          ':value': 'alias', 'readonly': '', 'tabindex': '-1',
        })),
      el('label', {},
        el('span', {class: 'form-label'}, 'username'),
        el('input', {
          'x-model.trim': 'username', 'required': '', 'autocomplete': 'off',
        })),
      el('label', {},
        el('span', {class: 'form-label'}, 'password'),
        el('div', {class: 'pw-input-row'},
          el('input', {
            'x-model': 'password',
            ':type': "showPassword ? 'text' : 'password'",
            'autocomplete': 'new-password',
          }),
          el('button', {
            'type': 'button', 'class': 'pw-toggle',
            '@click': 'showPassword = !showPassword',
            'x-text': "showPassword ? 'hide' : 'show'",
          }))),
      el('label', {},
        el('span', {class: 'form-label'}, 'domain'),
        el('input', { 'x-model.trim': 'domain', 'autocomplete': 'off' })),
      el('label', {},
        el('span', {class: 'form-label'}, 'notes'),
        el('textarea', { 'x-model': 'notes', 'rows': '2' })),
      el('div', {class: 'form-buttons'},
        el('button', { 'type': 'button', '@click': 'cancel()' }, 'cancel'),
        el('button', {
          'type': 'submit', 'class': 'primary',
          ':disabled': 'submitting',
          'x-text': "submitting ? 'saving…' : 'save'",
        }))));
}

// Triggered from each cred row's `edit` button. Fetches the
// current password (`has_password` only — saves a round-trip
// otherwise), then locates the credEditForm Alpine scope for
// this scenario and pokes its state in so the form opens
// already-prefilled.
async function openCredEdit(scenario, cred) {
  let password = '';
  if (cred.has_password) {
    try {
      const r = await fetch(passwordUrl(scenario, cred.alias));
      if (!r.ok) {
        toast('failed to load password: HTTP ' + r.status, 'error');
        return;
      }
      const j = await r.json();
      password = j.password || '';
    } catch (e) {
      toast('failed to load password: ' + e.message, 'error');
      return;
    }
  }
  const scope = document.querySelector('[data-edit-scope="cred"]');
  if (!scope || !window.Alpine) return;
  const data = window.Alpine.$data(scope);
  data.alias = cred.alias;
  data.username = cred.username || '';
  data.password = password;
  data.domain = cred.domain || '';
  data.notes = cred.notes || '';
  data.error = '';
  data.submitting = false;
  data.showPassword = true;
  data.open = true;
}

// ────────────────────────── forms: dc new ─────────────────────────────
// Inline form for `tgt dc new`. Every field except alias is optional —
// fish-side `argparse` accepts any subset and the argv builder drops
// empties. Most real DCs need at least domain + realm + kdc.
function buildDcNewForm() {
  const field = (label, model, placeholder) => el('label', {},
    el('span', {class: 'form-label'}, label),
    el('input', {
      'x-model.trim': model, 'autocomplete': 'off',
      'placeholder': placeholder || '',
    }));
  return el('div', { 'x-show': 'open', 'class': 'form-card' },
    el('div', {class: 'form-title'}, 'new DC'),
    el('div', {class: 'form-error', 'x-show': 'error', 'x-text': 'error'}),
    el('form', { '@submit.prevent': 'submit' },
      el('label', {},
        el('span', {class: 'form-label'}, 'alias'),
        el('input', {
          'x-model.trim': 'alias', 'required': '', 'autocomplete': 'off',
          'placeholder': 'e.g. dc01',
        })),
      field('domain',     'domain',    'e.g. acme.local'),
      field('realm',      'realm',     'e.g. ACME.LOCAL'),
      field('kdc host',   'kdcHost',   'e.g. dc01.acme.local'),
      field('kdc ip',     'kdcIp',     'e.g. 10.0.0.10'),
      field('admin host', 'adminHost', 'optional'),
      field('admin ip',   'adminIp',   'optional'),
      el('div', {class: 'form-buttons'},
        el('button', { 'type': 'button', '@click': 'cancel()' }, 'cancel'),
        el('button', {
          'type': 'submit', 'class': 'primary',
          ':disabled': 'submitting',
          'x-text': "submitting ? 'saving…' : 'create'",
        }))));
}

// ────────────────────────── forms: target edit ───────────────────────
// Targets store TGT (host) + TGT_HOSTS (space-separated extra
// hostnames). The form accepts both as scalar inputs; the backend
// `target_edit` action passes them through to `tgt edit --host /
// --hosts`.
function buildTargetEditForm() {
  return el('div', { 'x-show': 'open', 'class': 'form-card' },
    el('div', {class: 'form-title'}, 'edit target'),
    el('div', {class: 'form-error', 'x-show': 'error', 'x-text': 'error'}),
    el('form', { '@submit.prevent': 'submit' },
      el('label', {},
        el('span', {class: 'form-label'}, 'alias'),
        el('input', { ':value': 'alias', 'readonly': '', 'tabindex': '-1' })),
      el('label', {},
        el('span', {class: 'form-label'}, 'host'),
        el('input', {
          'x-model.trim': 'host', 'autocomplete': 'off',
          'placeholder': 'IP or hostname',
        })),
      el('label', {},
        el('span', {class: 'form-label'}, 'hostnames'),
        el('input', {
          'x-model.trim': 'hosts', 'autocomplete': 'off',
          'placeholder': 'space-separated, e.g. web.acme.local mail.acme.local',
        })),
      el('div', {class: 'form-buttons'},
        el('button', { 'type': 'button', '@click': 'cancel()' }, 'cancel'),
        el('button', {
          'type': 'submit', 'class': 'primary',
          ':disabled': 'submitting',
          'x-text': "submitting ? 'saving…' : 'save'",
        }))));
}

async function openTargetEdit(scenario, target) {
  const scope = document.querySelector('[data-edit-scope="target"]');
  if (!scope || !window.Alpine) return;
  const data = window.Alpine.$data(scope);
  data.alias = target.alias;
  data.host = target.host || '';
  data.hosts = (target.hosts || []).join(' ');
  data.error = '';
  data.submitting = false;
  data.open = true;
}

// ────────────────────────── forms: ports manager ─────────────────────
// One form-card per scenario; manages a single target's ports at a
// time. Triggered via `openPortsManager(scenario, target)` from each
// target row's ports button. Lists existing ports with rm buttons,
// plus an add-port sub-form. Comment changes happen via a per-row
// inline `save` (calls `tgt ports comment --target …`).
function buildPortsManagerForm() {
  return el('div', { 'x-show': 'open', 'class': 'form-card' },
    el('div', {class: 'form-title'},
      el('span', {}, 'ports for '),
      el('span', {'x-text': 'target', 'class': 'pm-target'})),
    el('div', {class: 'form-error', 'x-show': 'error', 'x-text': 'error'}),
    el('div', {'x-show': 'ports.length === 0', class: 'pm-empty'},
      '(no ports recorded)'),
    el('table', { 'x-show': 'ports.length > 0', class: 'pm-table' },
      el('thead', {}, el('tr', {},
        el('th', {}, 'port'), el('th', {}, 'service'),
        el('th', {}, 'comment'), el('th', {}, ''))),
      el('tbody', { 'x-html': '\'\'' /* tbody populated dynamically below */ })),
    // The tbody is built imperatively in `_renderPortsRows` to keep
    // per-row state simple (no Alpine x-for; mutation patterns are
    // confusing alongside the dynamic refresh).
    el('div', {class: 'pm-add'},
      el('div', {class: 'pm-label'}, 'add port'),
      el('form', { '@submit.prevent': 'submitAdd' },
        el('div', {class: 'pm-add-row'},
          el('input', {
            'x-model.trim': 'addPort', 'required': '',
            'placeholder': 'port', class: 'pm-port',
          }),
          el('select', { 'x-model': 'addProto', class: 'pm-proto' },
            el('option', {value: 'tcp'}, 'tcp'),
            el('option', {value: 'udp'}, 'udp')),
          el('input', {
            'x-model.trim': 'addService',
            'placeholder': 'service (optional)', class: 'pm-svc',
          }),
          el('input', {
            'x-model.trim': 'addComment',
            'placeholder': 'comment (optional)', class: 'pm-cmt',
          }),
          el('button', {
            'type': 'submit', 'class': 'primary',
            ':disabled': 'submitting',
            'x-text': "submitting ? 'adding…' : 'add'",
          }))),
    ),
    el('div', {class: 'form-buttons'},
      el('button', { 'type': 'button', '@click': 'close()' }, 'close')));
}

// Build a single port row's <tr>. Each row's inputs survive
// independently across add / rm operations — only the row that was
// added or removed touches the DOM. Other rows' (possibly unsaved)
// service / comment edits stay intact.
function _buildPortRow(scenario, target, p) {
  const serviceInput = el('input', {
    'value': p.service || '', 'data-port': p.port, 'data-proto': p.proto,
    class: 'pm-svc-edit',
  });
  const commentInput = el('input', {
    'value': p.comment || '', 'data-port': p.port, 'data-proto': p.proto,
    class: 'pm-cmt-edit',
  });
  // One save button per row — fires either the service or the
  // comment update (or both) depending on which fields actually
  // differ from the on-record value. Cheap to over-fire but we
  // skip no-op writes anyway.
  const saveBtn = el('button', {
    class: 'pm-row-save', type: 'button',
    onclick: () => _savePortRow(scenario, target, p,
                                 serviceInput.value, commentInput.value),
  }, 'save');
  const rmBtn = el('button', {
    class: 'pm-rm', type: 'button',
    onclick: () => _rmPort(scenario, target, p.port, p.proto),
  }, 'rm');
  return el('tr', {},
    el('td', {}, `${p.port}/${p.proto}`),
    el('td', {}, serviceInput),
    el('td', {}, commentInput),
    el('td', {class: 'row-actions'}, saveBtn, rmBtn));
}

// Render the initial per-port row list inside the manager's tbody.
// Called once from openPortsManager; add / rm operations append /
// remove specific rows without re-rendering the whole list (which
// would lose other rows' in-flight comment edits).
function _renderPortsRows(scopeEl, scenario, target, ports) {
  const tbody = scopeEl.querySelector('.pm-table tbody');
  if (!tbody) return;
  tbody.innerHTML = '';
  for (const p of ports) {
    tbody.append(_buildPortRow(scenario, target, p));
  }
}

function _appendPortRow(scopeEl, scenario, target, p) {
  const tbody = scopeEl.querySelector('.pm-table tbody');
  if (!tbody) return;
  tbody.append(_buildPortRow(scenario, target, p));
}

function _portsScope() {
  return document.querySelector('[data-edit-scope="ports"]');
}

async function openPortsManager(scenario, target) {
  const scope = _portsScope();
  if (!scope || !window.Alpine) return;
  const data = window.Alpine.$data(scope);
  data.target = target.alias;
  // Copy the array so our local mutations (add/rm) don't bleed back
  // into the source detail object reference held by state.detailData.
  data.ports = (target.ports || []).map(p => ({...p}));
  data.addPort = '';
  data.addProto = 'tcp';
  data.addService = '';
  data.addComment = '';
  data.error = '';
  data.submitting = false;
  data.open = true;
  // Claim the detail pane — refresh() will skip its renderDetail
  // call while this is true, preserving open form state across
  // SSE / poll updates.
  state.managingPorts = true;
  // Wait a tick so Alpine renders the table skeleton, then populate.
  setTimeout(() => _renderPortsRows(scope, scenario, target.alias, data.ports), 0);
}

async function _rmPort(scenario, target, port, proto) {
  const { ok, result } = await _submitForm('ports_rm', {
    target, port, proto,
  });
  if (!ok) {
    toast('rm failed: ' + (result.stderr || result.error || 'rc=' + result.rc).trim(), 'error');
    return;
  }
  // Patch state + DOM in place so other rows' unsaved edits survive.
  const scope = _portsScope();
  if (!scope) return;
  const data = window.Alpine.$data(scope);
  data.ports = data.ports.filter(p => !(p.port === port && p.proto === proto));
  const cell = scope.querySelector(
    `.pm-cmt-edit[data-port="${port}"][data-proto="${proto}"]`);
  if (cell) {
    const row = cell.closest('tr');
    if (row) row.remove();
  }
}

// Save whichever of service / comment changed on this row. We
// deliberately do NOT re-render the table so other rows' unsaved
// edits survive. Each successful write flashes the relevant input
// green for ~1.2 s so the user sees confirmation in place.
async function _savePortRow(scenario, target, p, newService, newComment) {
  const scope = _portsScope();
  if (!scope || !window.Alpine) return;
  const data = window.Alpine.$data(scope);
  const entry = data.ports.find(x => x.port === p.port && x.proto === p.proto);
  const flashInput = (cls) => {
    const inp = scope.querySelector(`.${cls}[data-port="${p.port}"][data-proto="${p.proto}"]`);
    if (!inp) return;
    inp.classList.add('pm-cmt-saved');
    setTimeout(() => inp.classList.remove('pm-cmt-saved'), 1500);
  };
  // Service: fish requires a matching record, so the record must
  // already exist on disk (it does — we're editing it).
  if ((p.service || '') !== newService) {
    const { ok, result } = await _submitForm('ports_service', {
      target, port: p.port, proto: p.proto, service: newService,
    });
    if (!ok) {
      toast('service save failed: ' + (result.stderr || result.error || 'rc=' + result.rc).trim(), 'error');
      return;
    }
    if (entry) entry.service = newService;
    flashInput('pm-svc-edit');
  }
  if ((p.comment || '') !== newComment) {
    const { ok, result } = await _submitForm('ports_comment', {
      target, port: p.port, proto: p.proto, comment: newComment,
    });
    if (!ok) {
      toast('comment save failed: ' + (result.stderr || result.error || 'rc=' + result.rc).trim(), 'error');
      return;
    }
    if (entry) entry.comment = newComment;
    flashInput('pm-cmt-edit');
  }
}

// ────────────────────────── forms: dc edit ────────────────────────────
// Same field set as `dc new` plus a readonly alias display.
function buildDcEditForm() {
  const field = (label, model, placeholder) => el('label', {},
    el('span', {class: 'form-label'}, label),
    el('input', {
      'x-model.trim': model, 'autocomplete': 'off',
      'placeholder': placeholder || '',
    }));
  return el('div', { 'x-show': 'open', 'class': 'form-card' },
    el('div', {class: 'form-title'}, 'edit DC'),
    el('div', {class: 'form-error', 'x-show': 'error', 'x-text': 'error'}),
    el('form', { '@submit.prevent': 'submit' },
      el('label', {},
        el('span', {class: 'form-label'}, 'alias'),
        el('input', { ':value': 'alias', 'readonly': '', 'tabindex': '-1' })),
      field('domain',     'domain',    'e.g. acme.local'),
      field('realm',      'realm',     'e.g. ACME.LOCAL'),
      field('kdc host',   'kdcHost',   'e.g. dc01.acme.local'),
      field('kdc ip',     'kdcIp',     'e.g. 10.0.0.10'),
      field('admin host', 'adminHost', 'optional'),
      field('admin ip',   'adminIp',   'optional'),
      el('div', {class: 'form-buttons'},
        el('button', { 'type': 'button', '@click': 'cancel()' }, 'cancel'),
        el('button', {
          'type': 'submit', 'class': 'primary',
          ':disabled': 'submitting',
          'x-text': "submitting ? 'saving…' : 'save'",
        }))));
}

async function openDcEdit(scenario, dc) {
  const scope = document.querySelector('[data-edit-scope="dc"]');
  if (!scope || !window.Alpine) return;
  const data = window.Alpine.$data(scope);
  data.alias = dc.alias;
  data.domain = dc.domain || '';
  data.realm = dc.realm || '';
  data.kdcHost = dc.kdc_host || '';
  data.kdcIp = dc.kdc_ip || '';
  data.adminHost = dc.admin_host || '';
  data.adminIp = dc.admin_ip || '';
  data.error = '';
  data.submitting = false;
  data.open = true;
}

document.addEventListener('alpine:init', () => {
  // Global confirm-modal state. `accept` invokes the stored callback;
  // `cancel` just closes. Both reset the callback so a stale fn
  // can't fire on a later open.
  window.Alpine.store('confirm', {
    open: false,
    title: '',
    message: '',
    preview: '',
    confirmLabel: 'confirm',
    _fn: null,
    accept() {
      const fn = this._fn;
      this.open = false;
      this._fn = null;
      this.preview = '';
      if (fn) fn();
    },
    cancel() {
      this.open = false;
      this._fn = null;
      this.preview = '';
    },
  });

  // Per-cred password state. Reveal fetches lazily; auto-hide fires
  // PW_AUTO_HIDE_MS after reveal. Hovering the revealed value pauses
  // the timer (so a long read won't snap shut mid-glance), with a
  // PW_AUTO_HIDE_MIN_RESUME_MS floor so the next mouseleave always
  // leaves a usable beat. Copy fetches but never sets `revealed`,
  // so a "just give me the value" gesture doesn't put the password
  // on screen at all.
  window.Alpine.data('credPw', (scenario, alias) => ({
    revealed: false,
    value: '',
    _hideAt: 0,
    _timer: null,
    _clearTimer() {
      if (this._timer) { clearTimeout(this._timer); this._timer = null; }
    },
    _scheduleHide(ms) {
      this._clearTimer();
      this._hideAt = Date.now() + ms;
      this._timer = setTimeout(() => this.hide(), ms);
    },
    pauseTimer() { this._clearTimer(); },
    resumeTimer() {
      if (!this.revealed) return;
      const remaining = Math.max(PW_AUTO_HIDE_MIN_RESUME_MS, this._hideAt - Date.now());
      this._scheduleHide(remaining);
    },
    // Returns the password string on success, or `null` on any
    // failure (HTTP error, network error, JSON parse). Callers branch
    // on `null` to skip the reveal/copy path so a deleted-between-
    // render cred doesn't show up as the literal "(empty)".
    async _fetch() {
      try {
        const r = await fetch(passwordUrl(scenario, alias));
        if (!r.ok) {
          const msg = r.status === 404
            ? 'credential no longer exists'
            : `HTTP ${r.status}`;
          toast('password fetch failed: ' + msg, 'error');
          return null;
        }
        const j = await r.json();
        return j.password || '';
      } catch (e) {
        toast('fetch failed: ' + e.message, 'error');
        return null;
      }
    },
    async reveal() {
      const v = await this._fetch();
      if (v === null) return;
      this.value = v || '(empty)';
      this.revealed = true;
      this._scheduleHide(PW_AUTO_HIDE_MS);
    },
    hide() {
      this.revealed = false;
      this.value = '';
      this._clearTimer();
    },
    async copy() {
      const v = await this._fetch();
      if (v === null) return;
      copyToClipboard(v, 'password');
    },
  }));

  window.Alpine.data('credNewForm', (scenario) => ({
    open: false,
    submitting: false,
    error: '',
    alias: '', username: '', password: '', domain: '', notes: '',
    // Default visible: a brand-new cred is being typed, not retrieved.
    // The masking dance only buys you something when an existing value
    // could be shoulder-surfed off the screen.
    showPassword: true,
    reset() {
      this.alias = ''; this.username = ''; this.password = '';
      this.domain = ''; this.notes = '';
      this.error = ''; this.submitting = false;
      this.showPassword = true;
    },
    cancel() { this.open = false; this.reset(); },
    async submit() {
      this.error = ''; this.submitting = true;
      try {
        const { ok, result } = await _submitForm('cred_new', {
          alias: this.alias, username: this.username,
          password: this.password, domain: this.domain, notes: this.notes,
        });
        if (ok) {
          this.open = false; this.reset();
          await refresh(true);
        } else {
          this.error = (result.stderr || result.error || `rc=${result.rc}`).trim();
          this.submitting = false;
        }
      } catch (e) {
        this.error = e.message;
        this.submitting = false;
      }
    },
  }));

  // Edit form for an existing cred. Pre-filled by `openCredEdit`
  // before opening; submit posts every field every time, so empty
  // fields here clear the corresponding TGT_CRED_* on disk —
  // matches the backend rule.
  window.Alpine.data('credEditForm', (scenario) => ({
    open: false, submitting: false, error: '',
    alias: '', username: '', password: '', domain: '', notes: '',
    showPassword: true,
    cancel() { this.open = false; },
    async submit() {
      this.error = ''; this.submitting = true;
      try {
        const { ok, result } = await _submitForm('cred_edit', {
          alias: this.alias, username: this.username,
          password: this.password, domain: this.domain, notes: this.notes,
        });
        if (ok) {
          this.open = false;
          await refresh(true);
        } else {
          this.error = (result.stderr || result.error || `rc=${result.rc}`).trim();
          this.submitting = false;
        }
      } catch (e) {
        this.error = e.message;
        this.submitting = false;
      }
    },
  }));

  // Ports manager state. Pre-filled by `openPortsManager`. The
  // ports[] array is read-only as far as Alpine bindings go — rows
  // are rendered imperatively via `_renderPortsRows` so we can
  // attach plain JS onclick handlers per row (the add form, by
  // contrast, uses Alpine for input binding + submit).
  window.Alpine.data('portsManager', (scenario) => ({
    open: false, submitting: false, error: '',
    target: '', ports: [],
    addPort: '', addProto: 'tcp', addService: '', addComment: '',
    close() {
      this.open = false;
      this.error = '';
      // Release the detail-pane lock and refresh to catch up on any
      // SSE updates suppressed while we were open.
      state.managingPorts = false;
      refresh(true);
    },
    async submitAdd() {
      this.error = ''; this.submitting = true;
      try {
        const { ok, result } = await _submitForm('ports_add', {
          target: this.target,
          port: this.addPort,
          proto: this.addProto,
          service: this.addService,
          comment: this.addComment,
        });
        if (!ok) {
          this.error = (result.stderr || result.error || `rc=${result.rc}`).trim();
          this.submitting = false;
          return;
        }
        // Append to local cache + DOM imperatively — re-rendering
        // the whole table would clobber other rows' in-flight
        // comment edits.
        const newEntry = {
          port: this.addPort, proto: this.addProto,
          service: this.addService, comment: this.addComment,
        };
        this.ports.push(newEntry);
        const scope = _portsScope();
        if (scope) _appendPortRow(scope, scenario, this.target, newEntry);
        // Clear the add form. Proto stays sticky — pentest flows
        // often add several ports of the same proto back-to-back.
        this.addPort = '';
        this.addService = '';
        this.addComment = '';
        this.submitting = false;
      } catch (e) {
        this.error = e.message;
        this.submitting = false;
      }
    },
  }));

  // Edit form for an existing target. Pre-filled by `openTargetEdit`.
  window.Alpine.data('targetEditForm', (scenario) => ({
    open: false, submitting: false, error: '',
    alias: '', host: '', hosts: '',
    cancel() { this.open = false; },
    async submit() {
      this.error = ''; this.submitting = true;
      try {
        const { ok, result } = await _submitForm('target_edit', {
          alias: this.alias, host: this.host, hosts: this.hosts,
        });
        if (ok) {
          this.open = false;
          await refresh(true);
        } else {
          this.error = (result.stderr || result.error || `rc=${result.rc}`).trim();
          this.submitting = false;
        }
      } catch (e) {
        this.error = e.message;
        this.submitting = false;
      }
    },
  }));

  // Edit form for an existing DC. Pre-filled by `openDcEdit`.
  // Submit posts every field every time; empty fields clear on
  // disk (modulo domain which is required and realm which
  // auto-derives from domain when empty).
  window.Alpine.data('dcEditForm', (scenario) => ({
    open: false, submitting: false, error: '',
    alias: '', domain: '', realm: '',
    kdcHost: '', kdcIp: '', adminHost: '', adminIp: '',
    cancel() { this.open = false; },
    async submit() {
      this.error = ''; this.submitting = true;
      try {
        const { ok, result } = await _submitForm('dc_edit', {
          alias: this.alias,
          domain: this.domain, realm: this.realm,
          kdc_host: this.kdcHost, kdc_ip: this.kdcIp,
          admin_host: this.adminHost, admin_ip: this.adminIp,
        });
        if (ok) {
          this.open = false;
          await refresh(true);
        } else {
          this.error = (result.stderr || result.error || `rc=${result.rc}`).trim();
          this.submitting = false;
        }
      } catch (e) {
        this.error = e.message;
        this.submitting = false;
      }
    },
  }));

  window.Alpine.data('dcNewForm', (scenario) => ({
    open: false, submitting: false, error: '',
    alias: '', domain: '', realm: '',
    kdcHost: '', kdcIp: '', adminHost: '', adminIp: '',
    reset() {
      this.alias = ''; this.domain = ''; this.realm = '';
      this.kdcHost = ''; this.kdcIp = ''; this.adminHost = ''; this.adminIp = '';
      this.error = ''; this.submitting = false;
    },
    cancel() { this.open = false; this.reset(); },
    async submit() {
      this.error = ''; this.submitting = true;
      try {
        const { ok, result } = await _submitForm('dc_new', {
          alias: this.alias,
          domain: this.domain, realm: this.realm,
          kdc_host: this.kdcHost, kdc_ip: this.kdcIp,
          admin_host: this.adminHost, admin_ip: this.adminIp,
        });
        if (ok) {
          this.open = false; this.reset();
          await refresh(true);
        } else {
          this.error = (result.stderr || result.error || `rc=${result.rc}`).trim();
          this.submitting = false;
        }
      } catch (e) {
        this.error = e.message;
        this.submitting = false;
      }
    },
  }));

  // Sidebar "+ new" scenario form. Lives in index.html under aside.
  window.Alpine.data('scenarioNewForm', () => ({
    open: false, submitting: false, error: '', name: '',
    reset() { this.name = ''; this.error = ''; this.submitting = false; },
    cancel() { this.open = false; this.reset(); },
    async submit() {
      this.error = ''; this.submitting = true;
      try {
        const { ok, result } = await _submitForm('scenario_new', {
          name: this.name,
        });
        if (ok) {
          // Auto-select the freshly-created scenario so the user
          // lands in its (empty) detail pane.
          state.selected = this.name;
          this.open = false; this.reset();
          await refresh(true);
        } else {
          this.error = (result.stderr || result.error || `rc=${result.rc}`).trim();
          this.submitting = false;
        }
      } catch (e) {
        this.error = e.message;
        this.submitting = false;
      }
    },
  }));
});

// ────────────────────────── input wiring ──────────────────────────────
// (re-attached at module load; alpine:init above runs at the same time
// because both Alpine and app.js are deferred-loaded.)
document.getElementById('filter').addEventListener('input', (e) => {
  state.filter = e.target.value;
  renderSidebar();
});
document.getElementById('show-archived').addEventListener('change', (e) => {
  state.showArchived = e.target.checked;
  renderSidebar();
});

// Initial load. Live updates come from the server's SSE stream
// below; a slow fallback poll runs alongside it as belt-and-braces
// in case the watcher thread silently dies or the EventSource
// reconnect heuristics misfire on a long sleep/wake. Hash dedup in
// refresh() makes the idle poll near-free.
renderBanner();
refresh(true);

// SSE: subscribe to `/api/events`. The server emits `change` whenever
// $TGT_HOME state or the active scenario flips; we re-fetch on each
// one. EventSource auto-reconnects on disconnect (`retry: 3000` from
// the server tightens that to ~3 s). No manual reconnect logic.
function _startEvents() {
  let es;
  try {
    es = new EventSource('/api/events');
  } catch (e) {
    // Browser without EventSource (none of our supported ones).
    // The fallback poll below still keeps the UI live.
    return;
  }
  es.addEventListener('change', () => refresh(false));
  // `ready` and `error` are useful in devtools; no UI side-effects.
  // (Errors fire on transient disconnects too — EventSource handles
  // the retry itself, so silence is correct here.)
}
_startEvents();

// Fallback poll. SSE is the primary signal; this catches the rare
// silent-failure case where the stream stays open but stops delivering.
setInterval(() => refresh(false), 60000);
