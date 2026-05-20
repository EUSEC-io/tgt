// DOM + I/O + small data utilities. Stateless — every function
// operates on its arguments or on a global like `document` /
// `fetch` / `navigator.clipboard`.

export async function api(path, opts) {
  const r = await fetch(path, opts);
  if (!r.ok) throw new Error(await r.text());
  return r.json();
}

export function djb2(s) {
  let h = 5381;
  for (let i = 0; i < s.length; i++) h = ((h << 5) + h) ^ s.charCodeAt(i);
  return h.toString(16);
}

export function toast(msg, kind) {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.className = 'toast show ' + (kind || '');
  setTimeout(() => { t.className = 'toast'; }, 2500);
}

// Write `text` to the system clipboard. Requires a secure context;
// localhost qualifies, so the browser exposes navigator.clipboard.
export async function copyToClipboard(text, label) {
  if (!text) { toast('nothing to copy', 'error'); return; }
  try {
    await navigator.clipboard.writeText(text);
    toast(label ? `copied ${label}` : 'copied', 'success');
  } catch (e) {
    toast('copy failed: ' + e.message, 'error');
  }
}

// Substring-match predicate over a list of haystack fields. Empty
// needle matches everything (search-off is the default). Match is
// case-insensitive. Used by the per-entity filters below.
function _entityMatch(needle) {
  if (!needle) return () => true;
  const n = needle.toLowerCase();
  return (fields) => fields.some(s => s && s.toLowerCase().includes(n));
}

// Per-entity field projections — kept tight (no password / cred-id /
// archive markers) so a search for "admin" returns entities whose
// human-visible content actually mentions "admin".
export function filterTargets(targets, needle) {
  const m = _entityMatch(needle);
  return targets.filter(t => m([t.alias, t.host, ...(t.hosts || [])]));
}
export function filterCreds(creds, needle) {
  const m = _entityMatch(needle);
  return creds.filter(c => m([c.alias, c.username, c.domain, c.notes]));
}
export function filterDCs(dcs, needle) {
  const m = _entityMatch(needle);
  return dcs.filter(dc => m([dc.alias, dc.domain, dc.realm,
                              dc.kdc_host, dc.kdc_ip,
                              dc.admin_host, dc.admin_ip]));
}

// Tiny DOM constructor used everywhere instead of innerHTML +
// template strings (which would force us to HTML-escape every
// user-supplied value individually). `class` is special-cased to
// the className property; `onclick` to the property too; everything
// else goes through setAttribute.
export function el(tag, attrs, ...children) {
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

// Generic single-string value cell. Shows the value with a copy
// icon that appears on hover. Falls back to a plain em-dash for
// empties so dashes don't accidentally end up on the clipboard.
export function valueCell(text, label) {
  if (!text) return document.createTextNode('—');
  return el('span', {class: 'vc'},
    el('span', {class: 'vc-text'}, text),
    el('button', {
      class: 'vc-copy', type: 'button', title: 'copy',
      onclick: (e) => { e.stopPropagation(); copyToClipboard(text, label || ''); },
    }, '⧉'));
}

// Format an argv as the user-facing `$ tgt arg1 'arg with space'`
// line. Single-quotes anything containing whitespace so the line
// stays paste-runnable as-is. Same shape the action-result panel
// shows post-execution, so pre / post views look consistent.
export function formatArgv(argv) {
  return '$ tgt ' + argv.map(a => /\s/.test(a) ? `'${a}'` : a).join(' ');
}

// URL of the cred-password endpoint. Used by Alpine `credPw` and by
// `openCredEdit` to prefill the cred-edit form with the stored value.
export function passwordUrl(scenario, alias) {
  return `/api/scenarios/${encodeURIComponent(scenario)}/creds/${encodeURIComponent(alias)}/password`;
}
