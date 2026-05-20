// Shared mutable state. Mutated by helpers across modules; reads
// drive every render.
export const state = {
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

// How long a revealed password stays on screen before auto-re-masking.
// Tuned so a glance is enough; hover pauses the timer for longer reads.
export const PW_AUTO_HIDE_MS = 10000;
export const PW_AUTO_HIDE_MIN_RESUME_MS = 3000;
