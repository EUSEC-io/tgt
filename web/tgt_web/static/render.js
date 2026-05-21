// Renders the three regions of the page: startup banner, sidebar
// scenario list, and the per-scenario detail pane. `refresh()`
// orchestrates fetches + diffs + targeted re-renders.

import { state } from './state.js';
import { api, djb2, el, valueCell,
         filterTargets, filterCreds, filterDCs, toast } from './helpers.js';
import { act, confirmAct } from './actions.js';
import {
  buildCredNewForm, buildCredEditForm, openCredEdit,
  buildDcNewForm, buildDcEditForm, openDcEdit,
  buildTargetNewForm, buildTargetEditForm, openTargetEdit,
  buildPortsManagerForm, openPortsManager,
} from './forms.js';

// ────────────────────────── render: startup banner ────────────────────
export async function renderBanner() {
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
export function renderSidebar() {
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

export function renderActiveInfo() {
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
export function renderDetail() {
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
  // Rename / clone — use window.prompt for consistency with the
  // per-cred rename button. A modal form would be slightly nicer
  // but the input is a single string in both cases; the prompt
  // dialog is fine.
  actions.append(el('button', {
    onclick: () => {
      const next = window.prompt(`Rename scenario "${d.name}" to:`, d.name);
      if (!next || next === d.name) return;
      // Keep `state.selected` in lock-step with the rename so the
      // refresh() that act() runs picks the new name. Without
      // this, refresh would fetch `/api/scenarios/<old>`, 404,
      // and the detail pane would stop updating until the user
      // clicks something else.
      if (state.selected === d.name) state.selected = next;
      act('scenario_rename', {old: d.name, new: next});
    },
  }, 'rename'));
  actions.append(el('button', {
    onclick: () => {
      const target = window.prompt(
        `Clone scenario "${d.name}" as:`, `${d.name}-copy`);
      if (!target || target === d.name) return;
      // Carries over targets / creds / DCs; workspace files are NOT
      // copied (fish-side decision — clones carry config forward,
      // not engagement output). Auto-selects the clone afterwards
      // so the user lands in it.
      state.selected = target;
      act('scenario_clone', {src: d.name, new: target});
    },
  }, 'clone'));
  main.append(actions);

  // Entity-search filtering. Each section renders the filtered
  // subset but shows "N of M" in the header so the user can see
  // what's hidden.
  const q = state.entitySearch;
  const targets = filterTargets(d.targets, q);
  const creds = filterCreds(d.creds, q);
  const dcs = filterDCs(d.dcs, q);
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

  // Targets — wrapped in TWO Alpine scopes: an outer one for the
  // new form (drives the `+ new` button next to the section
  // header) and an inner sibling for the per-row edit form.
  const targetSection = el('div', {
    'x-data': `targetNewForm(${JSON.stringify(d.name)})`,
  });
  targetSection.append(el('h2', {},
    `targets (${sectionCount(targets.length, d.targets.length)}) `,
    el('button', { 'class': 'add', 'type': 'button', '@click': 'open = true' },
      '+ new'),
  ));
  targetSection.append(buildTargetNewForm());
  const targetEditScope = el('div', {
    'x-data': `targetEditForm(${JSON.stringify(d.name)})`,
    'data-edit-scope': 'target',
  });
  targetEditScope.append(buildTargetEditForm());
  targetSection.append(targetEditScope);
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
        el('button', {onclick: () => openTargetEdit(d.name, t)}, 'edit'),
        el('button', {onclick: () => confirmAct({
          title: `Delete target "${t.alias}"?`,
          message: `Removes the target record from "${d.name}" and revokes any "${t.alias}" entries from /etc/hosts. If it's the active target, TGT / TGT_PORT / TGT_HOSTS / TGT_ACTIVE are also cleared. Workspace folder is NOT deleted (pass --purge-workspace on the CLI for that).`,
          confirmLabel: 'delete',
        }, 'target_rm', {alias: t.alias})}, 'rm'))))))));
  main.append(targetSection);

  // Creds — wrapped in an Alpine scope so the "+ new" button can
  // open the inline create form (state: open / fields / submitting
  // / error). See `credNewForm` factory in forms.js.
  //
  // JSON.stringify produces a valid JS string literal — handles
  // the single-quote / backslash cases that would otherwise break
  // the attribute. Current validators reject `'` in scenario /
  // cred names, but the template stays robust if that ever loosens.
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
        el('button', {onclick: () => openDcEdit(d.name, dc)}, 'edit'),
        el('button', {onclick: () => confirmAct({
          title: `Delete DC "${dc.alias}"?`,
          message: `Removes the DC record from "${d.name}". Any /etc/hosts and /etc/krb5.conf entries scoped to this DC are revoked. If it's the active DC, TGT_DC_* runtime is also cleared.`,
          confirmLabel: 'delete',
        }, 'dc_rm', {alias: dc.alias})}, 'rm'))))))));
  main.append(dcSection);
}

// ────────────────────────── refresh orchestrator ──────────────────────
// `force=true` always re-renders. Without force, we hash the new
// data and skip the DOM rebuild when nothing changed — that kills
// the flicker during idle polling, while still picking up cross-
// shell state changes.
export async function refresh(force) {
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
          // Re-render sidebar so the "selected" highlight tracks
          // the detail pane.
          renderSidebar();
        }
      }
    }
  } catch (e) {
    toast('refresh failed: ' + e.message, 'error');
  }
}
