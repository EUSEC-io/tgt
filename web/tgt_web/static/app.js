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
  c.confirmLabel = opts.confirmLabel || 'confirm';
  c._fn = fn;
}

// Shorthand: confirm then dispatch a single web action.
function confirmAct(opts, name, params) {
  confirmThen(opts, () => act(name, params));
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

// Whether the action-result panel renders in collapsed (status-pill)
// form. Toggled by the user via the −/+ button; persists across
// subsequent actions so a quick power-user flow ("fire ten actions,
// only peek if I see red") works without re-collapsing every time.
let _actionPanelCollapsed = false;

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

  // Collapse/expand toggle. Persists in _actionPanelCollapsed so the
  // next action lands in whichever state the user last chose.
  const collapse = el('button', {
    class: 'ap-collapse', type: 'button',
    title: _actionPanelCollapsed ? 'expand' : 'minimize',
  }, _actionPanelCollapsed ? '+' : '−');
  collapse.onclick = () => {
    _actionPanelCollapsed = !_actionPanelCollapsed;
    panel.classList.toggle('collapsed', _actionPanelCollapsed);
    collapse.textContent = _actionPanelCollapsed ? '+' : '−';
    collapse.title = _actionPanelCollapsed ? 'expand' : 'minimize';
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

  // Targets
  main.append(el('h2', {}, `targets (${sectionCount(targets.length, d.targets.length)})`));
  if (targets.length === 0) main.append(sectionEmpty(d.targets.length));
  else main.append(el('div', {class: 'table-scroll'}, el('table', {},
    el('thead', {}, el('tr', {}, el('th', {}, 'alias'), el('th', {}, 'host'),
                        el('th', {}, 'hostnames'), el('th', {}, ''))),
    el('tbody', {}, ...targets.map(t => el('tr', {},
      el('td', {}, t.alias),
      el('td', {}, valueCell(t.host, 'host')),
      el('td', {}, t.hosts.length
        ? el('span', {class: 'vc-chips'}, ...t.hosts.map(h => valueCell(h, 'hostname')))
        : document.createTextNode('—')),
      el('td', {}, d.active
        ? el('button', {onclick: () => act('target_switch', {alias: t.alias})}, 'switch')
        : '')))))));
  // (target_revoke is exposed elsewhere — there's no per-target
  // revoke today; the scenario-level "unload" subsumes it.)

  // Creds — wrapped in an Alpine scope so the "+ new" button can
  // open the inline create form (state: open / fields / submitting /
  // error). See `credNewForm` factory at the bottom of this file.
  const credSection = el('div', { 'x-data': `credNewForm('${d.name}')` });
  credSection.append(el('h2', {},
    `credentials (${sectionCount(creds.length, d.creds.length)}) `,
    el('button', { 'class': 'add', 'type': 'button', '@click': 'open = true' },
      '+ new'),
  ));
  credSection.append(buildCredNewForm());
  if (creds.length === 0) credSection.append(sectionEmpty(d.creds.length));
  else credSection.append(el('div', {class: 'table-scroll'}, el('table', {},
    el('thead', {}, el('tr', {}, el('th', {}, 'alias'), el('th', {}, 'username'),
                        el('th', {}, 'password'), el('th', {}, 'domain'),
                        el('th', {}, 'notes'), el('th', {}, ''))),
    el('tbody', {}, ...creds.map(c => {
      const pwCell = c.has_password
        ? el('span', { 'x-data': `credPw('${d.name}', '${c.alias}')`, 'class': 'pw-cell' },
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

  // DCs
  main.append(el('h2', {}, `DCs (${sectionCount(dcs.length, d.dcs.length)})`));
  if (dcs.length === 0) main.append(sectionEmpty(d.dcs.length));
  else main.append(el('div', {class: 'table-scroll'}, el('table', {},
    el('thead', {}, el('tr', {}, el('th', {}, 'alias'), el('th', {}, 'domain'),
                        el('th', {}, 'realm'), el('th', {}, 'kdc'),
                        el('th', {}, 'admin'), el('th', {}, ''))),
    el('tbody', {}, ...dcs.map(dc => el('tr', {},
      el('td', {class: dc.active ? 'active' : ''}, dc.alias),
      el('td', {}, valueCell(dc.domain, 'domain')),
      el('td', {}, valueCell(dc.realm, 'realm')),
      el('td', {}, valueCell(dc.kdc_host || dc.kdc_ip, 'kdc')),
      el('td', {}, valueCell(dc.admin_host || dc.admin_ip, 'admin')),
      el('td', {}, d.active && !dc.active
        ? el('button', {onclick: () => act('dc_switch', {alias: dc.alias})}, 'switch')
        : (dc.active ? el('button', {onclick: () => confirmAct({
            title: 'Unset active DC?',
            message: `Clears the active-DC marker in "${d.name}" and all TGT_DC_* runtime. The DC record stays on disk.`,
            confirmLabel: 'unset',
          }, 'dc_unset')}, 'unset') : ''))))))));
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
        renderDetail();
        // Re-render sidebar so the "selected" highlight tracks the detail pane.
        renderSidebar();
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
        el('input', {
          'x-model': 'password', 'type': 'password',
          'autocomplete': 'new-password',
        })),
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

document.addEventListener('alpine:init', () => {
  // Global confirm-modal state. `accept` invokes the stored callback;
  // `cancel` just closes. Both reset the callback so a stale fn
  // can't fire on a later open.
  window.Alpine.store('confirm', {
    open: false,
    title: '',
    message: '',
    confirmLabel: 'confirm',
    _fn: null,
    accept() {
      const fn = this._fn;
      this.open = false;
      this._fn = null;
      if (fn) fn();
    },
    cancel() {
      this.open = false;
      this._fn = null;
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
    async _fetch() {
      try {
        const r = await fetch(passwordUrl(scenario, alias));
        const j = await r.json();
        return j.password || '';
      } catch (e) {
        toast('fetch failed: ' + e.message, 'error');
        return '';
      }
    },
    async reveal() {
      const v = await this._fetch();
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
      copyToClipboard(v, 'password');
    },
  }));

  window.Alpine.data('credNewForm', (scenario) => ({
    open: false,
    submitting: false,
    error: '',
    alias: '', username: '', password: '', domain: '', notes: '',
    reset() {
      this.alias = ''; this.username = ''; this.password = '';
      this.domain = ''; this.notes = '';
      this.error = ''; this.submitting = false;
    },
    cancel() { this.open = false; this.reset(); },
    async submit() {
      this.error = ''; this.submitting = true;
      try {
        const r = await fetch('/api/action', {
          method: 'POST', headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({
            action: 'cred_new',
            params: {
              alias: this.alias, username: this.username,
              password: this.password, domain: this.domain, notes: this.notes,
            },
          }),
        });
        const result = await r.json();
        actionResult('cred_new', result);
        if (r.ok && result.rc === 0) {
          this.open = false;
          this.reset();
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

// Initial load + polite poll (every 10s, no DOM churn unless data changed).
renderBanner();
refresh(true);
setInterval(() => refresh(false), 10000);
