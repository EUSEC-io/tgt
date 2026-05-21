// Every inline form in the UI lives here, alongside the matching
// Alpine data factories. Conventions:
//   - `buildXForm()` returns the form's DOM (Alpine binds via
//     attributes the factory will resolve at render time).
//   - `openXEdit(scenario, entity)` pokes state into the form's
//     Alpine scope, then sets `open = true`.
//   - The factories themselves are registered at the bottom of
//     this file inside the `alpine:init` listener.

import { state, PW_AUTO_HIDE_MS, PW_AUTO_HIDE_MIN_RESUME_MS } from './state.js';
import { el, toast, copyToClipboard, passwordUrl } from './helpers.js';
import { submitForm } from './actions.js';
import { refresh } from './render.js';

// ────────────────────────── forms: cred new ───────────────────────────
// Inline form for `tgt cred new`. Pattern to repeat for other forms:
//   - `buildXForm()` returns the DOM (Alpine binds via attributes)
//   - `xForm()` factory registered on `alpine:init` owns state + submit
export function buildCredNewForm() {
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
export function buildCredEditForm() {
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
// current password (only when `has_password`), then locates the
// credEditForm Alpine scope for this scenario and pokes its state
// in so the form opens already-prefilled.
export async function openCredEdit(scenario, cred) {
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
// Inline form for `tgt dc new`. Every field except alias is
// optional — fish-side `argparse` accepts any subset and the argv
// builder drops empties. Most real DCs need at least domain +
// realm + kdc.
export function buildDcNewForm() {
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

// ────────────────────────── forms: dc edit ────────────────────────────
// Same field set as `dc new` plus a readonly alias display.
export function buildDcEditForm() {
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

export async function openDcEdit(scenario, dc) {
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

// ────────────────────────── forms: target new ────────────────────────
// `tgt new <alias> [--host …] [--hosts …]`. Web-side target
// creation lives at the target-file level only: alias is required;
// host + hosts are optional. Creds / DCs / ports are added via
// their own forms after the target exists (each lives in its own
// per-scenario registry, not in the target file).
export function buildTargetNewForm() {
  return el('div', { 'x-show': 'open', 'class': 'form-card' },
    el('div', {class: 'form-title'}, 'new target'),
    el('div', {class: 'form-error', 'x-show': 'error', 'x-text': 'error'}),
    el('form', { '@submit.prevent': 'submit' },
      el('label', {},
        el('span', {class: 'form-label'}, 'alias'),
        el('input', {
          'x-model.trim': 'alias', 'required': '', 'autocomplete': 'off',
          'placeholder': 'e.g. web01',
        })),
      el('label', {},
        el('span', {class: 'form-label'}, 'host'),
        el('input', {
          'x-model.trim': 'host', 'autocomplete': 'off',
          'placeholder': 'IP or hostname (optional)',
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
          'x-text': "submitting ? 'creating…' : 'create'",
        }))));
}

// ────────────────────────── forms: target edit ───────────────────────
// Targets store TGT (host) + TGT_HOSTS (space-separated extra
// hostnames). The form accepts both as scalar inputs; the backend
// `target_edit` action passes them through to `tgt edit --host /
// --hosts`.
export function buildTargetEditForm() {
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

export async function openTargetEdit(scenario, target) {
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
// time. Triggered via `openPortsManager(scenario, target)` from
// each target row's ports button. Lists existing ports with rm
// buttons and per-row editable service + comment, plus an add-port
// sub-form.
export function buildPortsManagerForm() {
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
      el('tbody', { 'x-html': '\'\'' /* populated by _renderPortsRows */ })),
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
// added or removed touches the DOM. Other rows' (possibly
// unsaved) service / comment edits stay intact.
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

// Render the initial per-port row list inside the manager's
// tbody. Called once from openPortsManager; add / rm operations
// append / remove specific rows without re-rendering the whole
// list (which would lose other rows' in-flight comment edits).
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

export async function openPortsManager(scenario, target) {
  const scope = _portsScope();
  if (!scope || !window.Alpine) return;
  const data = window.Alpine.$data(scope);
  data.target = target.alias;
  // Copy the array so our local mutations (add/rm) don't bleed
  // back into the source detail object reference held by
  // state.detailData.
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
  // Wait a tick so Alpine renders the table skeleton, then
  // populate.
  setTimeout(() => _renderPortsRows(scope, scenario, target.alias, data.ports), 0);
}

async function _rmPort(scenario, target, port, proto) {
  const { ok, result } = await submitForm('ports_rm', {
    target, port, proto,
  });
  if (!ok) {
    toast('rm failed: ' + (result.stderr || result.error || 'rc=' + result.rc).trim(), 'error');
    return;
  }
  // Patch state + DOM in place so other rows' unsaved edits
  // survive.
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
    const { ok, result } = await submitForm('ports_service', {
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
    const { ok, result } = await submitForm('ports_comment', {
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

// ────────────────────────── Alpine factories ──────────────────────────
// All Alpine `data(...)` registrations live here. The listener
// attaches at module load time; Alpine fires `alpine:init` later
// on DOMContentLoaded (defer + module scripts run before that).
document.addEventListener('alpine:init', () => {
  // Global confirm-modal state. `accept` invokes the stored
  // callback; `cancel` just closes. Both reset the callback so a
  // stale fn can't fire on a later open.
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

  // Per-cred password state. Reveal fetches lazily; auto-hide
  // fires PW_AUTO_HIDE_MS after reveal. Hovering the revealed
  // value pauses the timer (so a long read won't snap shut
  // mid-glance), with a PW_AUTO_HIDE_MIN_RESUME_MS floor so the
  // next mouseleave always leaves a usable beat. Copy fetches but
  // never sets `revealed`, so a "just give me the value" gesture
  // doesn't put the password on screen at all.
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
    // failure (HTTP error, network error, JSON parse). Callers
    // branch on `null` to skip the reveal/copy path so a
    // deleted-between-render cred doesn't show up as the literal
    // "(empty)".
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
    // Default visible: a brand-new cred is being typed, not
    // retrieved. The masking dance only buys you something when an
    // existing value could be shoulder-surfed off the screen.
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
        const { ok, result } = await submitForm('cred_new', {
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
        const { ok, result } = await submitForm('cred_edit', {
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
      // Release the detail-pane lock and refresh to catch up on
      // any SSE updates suppressed while we were open.
      state.managingPorts = false;
      refresh(true);
    },
    async submitAdd() {
      this.error = ''; this.submitting = true;
      try {
        const { ok, result } = await submitForm('ports_add', {
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

  // New-target form. Alias required; host + hosts optional and
  // map directly to TGT / TGT_HOSTS on disk. Per the design
  // discussion (2026-05-21): web-side target creation is target-
  // file scope only; creds / DCs / ports go through their own
  // forms after the target exists.
  window.Alpine.data('targetNewForm', (scenario) => ({
    open: false, submitting: false, error: '',
    alias: '', host: '', hosts: '',
    reset() {
      this.alias = ''; this.host = ''; this.hosts = '';
      this.error = ''; this.submitting = false;
    },
    cancel() { this.open = false; this.reset(); },
    async submit() {
      this.error = ''; this.submitting = true;
      try {
        const { ok, result } = await submitForm('target_new', {
          alias: this.alias, host: this.host, hosts: this.hosts,
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

  // Edit form for an existing target. Pre-filled by
  // `openTargetEdit`.
  window.Alpine.data('targetEditForm', (scenario) => ({
    open: false, submitting: false, error: '',
    alias: '', host: '', hosts: '',
    cancel() { this.open = false; },
    async submit() {
      this.error = ''; this.submitting = true;
      try {
        const { ok, result } = await submitForm('target_edit', {
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
        const { ok, result } = await submitForm('dc_edit', {
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
        const { ok, result } = await submitForm('dc_new', {
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

  // Sidebar "+ new" scenario form. Lives in index.html under
  // aside.
  window.Alpine.data('scenarioNewForm', () => ({
    open: false, submitting: false, error: '', name: '',
    reset() { this.name = ''; this.error = ''; this.submitting = false; },
    cancel() { this.open = false; this.reset(); },
    async submit() {
      this.error = ''; this.submitting = true;
      try {
        const { ok, result } = await submitForm('scenario_new', {
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
