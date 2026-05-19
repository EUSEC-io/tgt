// ────────────────────────── state + cache ─────────────────────────────
const state = {
  selected: null,        // scenario name currently shown in detail pane
  filter: '',            // sidebar substring filter
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

// Render the sticky action-result panel. Headline always visible;
// "details" toggle reveals argv + full stdout + stderr. Replaced
// every time a new action fires; manual × to dismiss.
function actionResult(name, r) {
  const panel = document.getElementById('action-panel');
  const ok = r.rc === 0;
  const lastLine = (s) => (s || '').trim().split('\n').filter(Boolean).pop() || '';
  const headline = ok
    ? '✓ ' + (lastLine(r.stdout) || name)
    : '✗ ' + (lastLine(r.stderr) || lastLine(r.stdout) || `${name} (rc=${r.rc})`);

  panel.className = 'action-panel ' + (ok ? 'success' : 'error');
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

  const close = el('button', {class: 'ap-close', type: 'button', title: 'dismiss'}, '×');
  close.onclick = () => { panel.hidden = true; };
  head.append(close);

  panel.append(head);
  if (details) panel.append(details);
}

async function revealPassword(scenario, alias, span) {
  try {
    const r = await api(`/api/scenarios/${encodeURIComponent(scenario)}/creds/${encodeURIComponent(alias)}/password`);
    const replacement = el('span', {class: 'pw-value'}, r.password || '(empty)');
    span.replaceWith(replacement);
  } catch (e) { toast('reveal failed: ' + e.message, 'error'); }
}

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
  if (!d) {
    main.append(el('div', {class: 'placeholder'}, 'Select a scenario from the list.'));
    return;
  }

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
    actions.append(el('button', {onclick: () => act('scenario_unload')}, 'unload'));
  } else {
    actions.append(el('button', {class: 'primary',
      onclick: () => act('scenario_switch', {name: d.name})}, 'switch to'));
  }
  actions.append(el('button', {
    onclick: () => act(d.archived ? 'scenario_unarchive' : 'scenario_archive', {name: d.name})
  }, d.archived ? 'unarchive' : 'archive'));
  main.append(actions);

  // Targets
  main.append(el('h2', {}, `targets (${d.targets.length})`));
  if (d.targets.length === 0) main.append(el('div', {class: 'empty'}, '(none)'));
  else main.append(el('table', {},
    el('thead', {}, el('tr', {}, el('th', {}, 'alias'), el('th', {}, 'host'),
                        el('th', {}, 'hostnames'), el('th', {}, ''))),
    el('tbody', {}, ...d.targets.map(t => el('tr', {},
      el('td', {}, t.alias),
      el('td', {}, t.host || '—'),
      el('td', {}, t.hosts.join(', ') || '—'),
      el('td', {}, d.active
        ? el('button', {onclick: () => act('target_switch', {alias: t.alias})}, 'switch')
        : ''))))));

  // Creds
  main.append(el('h2', {}, `credentials (${d.creds.length})`));
  if (d.creds.length === 0) main.append(el('div', {class: 'empty'}, '(none)'));
  else main.append(el('table', {},
    el('thead', {}, el('tr', {}, el('th', {}, 'alias'), el('th', {}, 'username'),
                        el('th', {}, 'password'), el('th', {}, 'domain'),
                        el('th', {}, 'notes'), el('th', {}, ''))),
    el('tbody', {}, ...d.creds.map(c => {
      const pwCell = c.has_password
        ? el('span', {class: 'reveal', onclick: function() { revealPassword(d.name, c.alias, this); }}, 'reveal')
        : document.createTextNode('—');
      return el('tr', {},
        el('td', {class: c.active ? 'active' : ''}, c.alias),
        el('td', {}, c.username),
        el('td', {}, pwCell),
        el('td', {}, c.domain || '—'),
        el('td', {}, c.notes || '—'),
        el('td', {},
          d.active && !c.active
            ? el('button', {onclick: () => act('cred_switch', {alias: c.alias})}, 'switch')
            : (c.active ? el('button', {onclick: () => act('cred_unset')}, 'unset') : '')));
    }))));

  // DCs
  main.append(el('h2', {}, `DCs (${d.dcs.length})`));
  if (d.dcs.length === 0) main.append(el('div', {class: 'empty'}, '(none)'));
  else main.append(el('table', {},
    el('thead', {}, el('tr', {}, el('th', {}, 'alias'), el('th', {}, 'domain'),
                        el('th', {}, 'realm'), el('th', {}, 'kdc'),
                        el('th', {}, 'admin'), el('th', {}, ''))),
    el('tbody', {}, ...d.dcs.map(dc => el('tr', {},
      el('td', {class: dc.active ? 'active' : ''}, dc.alias),
      el('td', {}, dc.domain || '—'),
      el('td', {}, dc.realm || '—'),
      el('td', {}, dc.kdc_host || dc.kdc_ip || '—'),
      el('td', {}, dc.admin_host || dc.admin_ip || '—'),
      el('td', {}, d.active && !dc.active
        ? el('button', {onclick: () => act('dc_switch', {alias: dc.alias})}, 'switch')
        : (dc.active ? el('button', {onclick: () => act('dc_unset')}, 'unset') : '')))))));
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

// Initial load + polite poll (every 10s, no DOM churn unless data changed).
renderBanner();
refresh(true);
setInterval(() => refresh(false), 10000);
