// The pipeline view: the app's own pump path (`PumpDisplayCapture.classify`)
// on one image at a time, every stage drawn - decide, orientation, candidates,
// verify, assign, slice, classify, law - each checked against the hand
// annotation and the truth row. The trace comes from `pump-read --trace-serve`
// (server.py -> /api/trace), which records the run the app would make; the
// view only draws it. Models, deskew and the slow-path budget are the app's
// unless changed here, and every change is named in the header chip.
(() => {
'use strict';

const STAGES = [
  {key: 'decide', name: 'Display?', hint: 'is the frame a pump display: the fast path (detector rows alone) or the slow path (verifier, capped)'},
  {key: 'orient', name: 'Orientation', hint: 'the seed orientation, and the search the app runs when the seed reads nothing'},
  {key: 'cands', name: 'Candidates', hint: 'detector rows (with confidence) and the Vision + classical proposals'},
  {key: 'verify', name: 'Verify', hint: 'kept and dropped candidates with the verifier\'s reasons'},
  {key: 'assign', name: 'Assign', hint: 'the role each verified row was given'},
  {key: 'slice', name: 'Slice', hint: 'each assigned row warped to a strip and cut into cells'},
  {key: 'classify', name: 'Classify', hint: 'every cell: the classifier\'s top digits, margin and decimal mark'},
  {key: 'law', name: 'Law', hint: 'what the law committed or refused, against the truth row'},
];
const FIELDS = ['total', 'liters', 'unitPrice'];
const COLORS = {total: '#ff5a5f', liters: '#4cc3ff', unitPrice: '#ffc857', board: '#9b8cff'};
const OK = '#4ade80', BAD = '#f87171', WARN = '#ffc857', GREY = '#8a919c';
const STATUS_COLOR = {ok: OK, bad: BAD, warn: WARN, none: '#3a414c'};
const IOU_MATCH = 0.3;

const $p = s => document.querySelector(s);
const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;'}[c]));

const st = {
  open: false, set: [], index: 0, stage: 0, attempt: null, zoom: 1, grid: false,
  traces: {}, truth: {}, images: {}, statuses: {},
  opts: {detector: '', classifier: '', deskew: 'off', budget: 'app'},
  layers: {hand: true, dropped: true, labels: true, alpha: 0.9},
  showAllStrips: false, detectors: [], classifiers: [], shipped: {}, verifyMargin: 1.0,
};

// ---------------------------------------------------------------- styles + DOM
const css = `
#pipeline { grid-column:3 / 5; grid-row:1 / -1; min-width:0; min-height:0 }
#pipeline .pl-panel { height:100%; background:var(--panel); display:grid; grid-template-rows:auto 1fr; overflow:hidden }
#pipeline .pl-top { display:flex; flex-wrap:wrap; gap:6px; align-items:center; padding:6px 10px; border-bottom:1px solid var(--line); font-size:12px }
#pipeline .pl-top select, #pipeline .pl-top input { font-size:12px }
#pipeline .pl-chip { padding:1px 8px; border-radius:10px; font-size:11px; border:1px solid var(--line) }
#pipeline .pl-chip.app { color:${OK}; border-color:${OK} } #pipeline .pl-chip.diff { color:${WARN}; border-color:${WARN} }
#pipeline .pl-body { display:grid; grid-template-columns:150px 1fr 300px; min-height:0 }
#pipeline .pl-rail, #pipeline .pl-info { overflow:auto; border-right:1px solid var(--line); font-size:12px }
#pipeline .pl-info { border-right:none; border-left:1px solid var(--line); padding:8px }
#pipeline .dot { width:9px; height:9px; border-radius:50%; flex:none; display:inline-block }
#pipeline .pl-rail div.stage { padding:7px 10px; cursor:pointer; display:flex; gap:8px; align-items:center; border-bottom:1px solid var(--line) }
#pipeline .pl-rail div.stage.sel { background:#223 }
#pipeline .pl-rail .n { color:var(--dim); width:12px }
#pipeline .pl-rail .attempts { padding:8px 10px; display:flex; flex-direction:column; gap:4px }
#pipeline .pl-rail .attempts button { text-align:left; font-size:11px }
#pipeline .pl-rail .attempts button.sel { outline:1px solid var(--fg) }
#pipeline .pl-main { display:grid; grid-template-rows:auto 1fr; min-width:0; min-height:0 }
#pipeline .pl-tools { display:flex; gap:6px; align-items:center; padding:4px 8px; border-bottom:1px solid var(--line); font-size:12px; flex-wrap:wrap }
#pipeline .pl-canvas { overflow:auto; background:#05070a; position:relative }
#pipeline .pl-canvas canvas { display:block }
#pipeline .strip { margin:8px; padding:6px; border:1px solid var(--line); border-radius:6px; display:inline-block; vertical-align:top }
#pipeline .strip h4 { margin:0 0 4px; font-size:12px; font-weight:600 }
#pipeline .cells { display:flex; gap:6px; flex-wrap:wrap; margin:6px }
#pipeline .cell { border:2px solid var(--line); border-radius:6px; padding:4px; text-align:center; font-size:11px; background:#0b0e13 }
#pipeline .cell .big { font-size:22px; font-weight:700; font-family:ui-monospace,monospace }
#pipeline .cell .bar { height:4px; background:#2a303a; border-radius:2px; margin-top:3px }
#pipeline .cell .bar i { display:block; height:4px; border-radius:2px }
#pipeline table.pl { border-collapse:collapse; width:100%; font-size:12px } #pipeline table.pl td { padding:3px 6px; border-bottom:1px solid var(--line) }
#pipeline .grid { display:flex; flex-wrap:wrap; gap:8px; padding:8px }
#pipeline .grid .tile { border:2px solid var(--line); border-radius:6px; padding:4px; cursor:pointer; font-size:11px; max-width:320px }
#pipeline .grid .tile canvas { display:block; max-width:100% }
#pipeline .muted { color:var(--dim) }
#pipeline .mono { font-family:ui-monospace,monospace }
`;

function build() {
  const style = document.createElement('style'); style.textContent = css; document.head.appendChild(style);
  const root = document.createElement('div'); root.id = 'pipeline'; root.style.display = 'none';
  root.innerHTML = `<div class="pl-panel">
    <div class="pl-top">
      <b>Debugging</b>
      <span class="muted">|</span>
      <span class="muted">detector</span><select id="plDet"></select>
      <span class="muted">classifier</span><select id="plCls"></select>
      <span class="muted">deskew</span><select id="plDeskew"><option>off</option><option>onRefusal</option><option>always</option><option>level</option></select>
      <span class="muted">budget</span><select id="plBudget" title="the slow path's wall-clock cap"><option value="app">app 1.5 s</option><option value="none">no cap</option></select>
      <span id="plChip" class="pl-chip app">app pipeline</span>
      <span id="plTally" class="muted"></span>
      <span id="plTool" class="muted"></span>
      <span style="flex:1"></span>
      <button id="plRetrace" title="run again, ignoring the cache">⟳ re-run</button>
      <button id="plAll" title="trace every image in the set and tally where each first fails">▶ trace set</button>
      <button id="plGrid" title="this stage across every traced image (G)">▦ grid</button>
      <button id="plSave" title="write the trace and a PNG under ml/pump-reader/runs/<date>/trace/">save</button>
    </div>
    <div class="pl-body">
      <div class="pl-rail"><div id="plStages"></div><div class="attempts" id="plAttempts"></div></div>
      <div class="pl-main">
        <div class="pl-tools">
          <button id="plZoomOut" title="−">−</button><button id="plZoomFit" title="fit (0)">fit</button><button id="plZoom1" title="1:1">1:1</button><button id="plZoomIn" title="+">+</button>
          <span id="plZoomLbl" class="muted mono"></span>
          <label><input type="checkbox" id="plLHand" checked> hand boxes</label>
          <label><input type="checkbox" id="plLDrop" checked> dropped</label>
          <label><input type="checkbox" id="plLLab" checked> labels</label>
          <label>opacity <input type="range" id="plAlpha" min="0.2" max="1" step="0.05" value="0.9"></label>
          <label id="plAllStripsWrap"><input type="checkbox" id="plAllStrips"> every candidate's strip</label>
          <span style="flex:1"></span>
          <span id="plStatus" class="muted"></span>
        </div>
        <div class="pl-canvas" id="plView"></div>
      </div>
      <div class="pl-info" id="plInfo"></div>
    </div></div>`;
  document.body.appendChild(root);
  $p('#plRetrace').onclick = () => traceCurrent(false);
  $p('#plAll').onclick = traceAll;
  $p('#plGrid').onclick = () => { st.grid = !st.grid; render(); };
  $p('#plSave').onclick = save;
  for (const [id, key] of [['#plDet', 'detector'], ['#plCls', 'classifier'], ['#plDeskew', 'deskew'], ['#plBudget', 'budget']]) {
    $p(id).onchange = e => { st.opts[key] = e.target.value; st.traces = {}; st.statuses = {}; chip(); traceCurrent(true); renderList(); };
  }
  $p('#plZoomIn').onclick = () => setZoom(st.zoom * 1.25);
  $p('#plZoomOut').onclick = () => setZoom(st.zoom / 1.25);
  $p('#plZoom1').onclick = () => setZoom(1);
  $p('#plZoomFit').onclick = () => setZoom('fit');
  $p('#plLHand').onchange = e => { st.layers.hand = e.target.checked; render(); };
  $p('#plLDrop').onchange = e => { st.layers.dropped = e.target.checked; render(); };
  $p('#plLLab').onchange = e => { st.layers.labels = e.target.checked; render(); };
  $p('#plAlpha').oninput = e => { st.layers.alpha = +e.target.value; render(); };
  $p('#plAllStrips').onchange = e => { st.showAllStrips = e.target.checked; render(); };
  $p('#plView').addEventListener('wheel', e => {
    if (!(e.ctrlKey || e.metaKey)) return;
    e.preventDefault(); setZoom(st.zoom * (e.deltaY < 0 ? 1.1 : 1 / 1.1));
  }, {passive: false});
  $p('#plView').addEventListener('mousemove', hover);
}

// ------------------------------------------------------------------- opening
async function show(name) {
  if (!document.getElementById('pipeline')) build();
  st.open = true;
  $p('#pipeline').style.display = '';
  if (!st.detectors.length) await loadModels();
  if (name) await select(name); else render();
}
function hide() { st.open = false; if (document.getElementById('pipeline')) $p('#pipeline').style.display = 'none'; }

// A library pick. The set is the library as it is filtered (stills), or the
// picked video's frames; the pick opens at its place in it.
async function select(name) {
  if (!st.open) return;
  st.picked = name;
  await loadSet(name);
}

// The library's filter changed: the set follows it, staying on the image open
// when it is still in the list.
async function refreshSet() {
  if (!st.open || isVideoPick(st.picked)) return;
  const names = libraryStills();
  const here = st.set[st.index];
  st.set = names;
  if (names.includes(here)) { st.index = names.indexOf(here); renderList(); return; }
  st.index = 0; renderList();
  if (names.length) await go(0); else render();
}

function libraryStills() {
  const isStill = n => { const e = window.libraryEntry && window.libraryEntry(n); return !(e && e.video); };
  return (window.libraryNames ? window.libraryNames() : []).filter(isStill);
}
function isVideoPick(name) {
  if (!name) return false;
  if (name.startsWith('frame/')) return true;
  const e = window.libraryEntry && window.libraryEntry(name);
  return !!(e && e.video);
}

async function loadModels() {
  const [dets, clss, tool] = await Promise.all([
    fetch('/api/detectors').then(r => r.json()), fetch('/api/classifiers').then(r => r.json()),
    fetch('/api/trace/tool').then(r => r.json()).catch(() => null)]);
  st.detectors = dets; st.classifiers = clss;
  st.shipped = {detector: (dets.find(d => d.shipped) || dets[0] || {}).path, classifier: (clss.find(c => c.shipped) || clss[0] || {}).path};
  if (!st.opts.detector) st.opts.detector = st.shipped.detector;
  if (!st.opts.classifier) st.opts.classifier = st.shipped.classifier;
  $p('#plDet').innerHTML = dets.map(d => `<option value="${esc(d.path)}">${d.shipped ? '★ ' : ''}${esc(d.version)}</option>`).join('');
  $p('#plCls').innerHTML = clss.map(c => `<option value="${esc(c.path)}">${c.shipped ? '★ ' : ''}${esc(c.version)}</option>`).join('');
  $p('#plDet').value = st.opts.detector; $p('#plCls').value = st.opts.classifier;
  $p('#plDeskew').value = st.opts.deskew; $p('#plBudget').value = st.opts.budget;
  toolLine(tool); chip();
}

function toolLine(tool) {
  if (!tool) return;
  $p('#plTool').textContent = tool.error ? `⚠ ${tool.error}`
    : tool.rebuilt ? `pipeline rebuilt ${tool.rebuilt} (${tool.newestSource.split('/').pop()} changed)`
    : `pipeline build ${tool.binary || '?'}`;
  $p('#plTool').style.color = tool.error ? BAD : tool.rebuilt ? WARN : '';
}

function chip() {
  const diffs = [];
  if (st.opts.detector !== st.shipped.detector) diffs.push('detector');
  if (st.opts.classifier !== st.shipped.classifier) diffs.push('classifier');
  if (st.opts.deskew !== 'off') diffs.push(`deskew ${st.opts.deskew}`);
  if (st.opts.budget !== 'app') diffs.push('no budget cap');
  const c = $p('#plChip');
  c.className = 'pl-chip ' + (diffs.length ? 'diff' : 'app');
  c.textContent = diffs.length ? `differs from the app: ${diffs.join(', ')}` : 'app pipeline (shipped models, 1.5 s cap)';
}

// ----------------------------------------------------------------------- sets
async function loadSet(here) {
  here = here || st.picked || st.set[st.index];
  let names = [];
  if (isVideoPick(here)) {
    const stem = here.startsWith('frame/') ? here.split('/')[1] : here;
    const recs = await fetch('/api/records/' + encodeURIComponent(stem)).then(r => r.json());
    const rec = recs[0] || {tracked: []};
    const every = Math.max(1, Math.round(rec.tracked.length / 40));
    names = rec.tracked.filter((_, i) => i % every === 0).map(f => `frame/${stem}/${f}`);
    if (here.startsWith('frame/') && !names.includes(here)) names.unshift(here);
    st.recordCache = {stem, rec};
  } else {
    names = libraryStills();
    if (here && !names.includes(here)) names.unshift(here);
  }
  st.set = names; st.index = Math.max(0, names.indexOf(here));
  renderList();
  if (names.length) await go(st.index); else render();
}

// The set's position and where its traced images first fail, in the header;
// the per-image dots are drawn on the library rows (index.html asks statusOf).
function renderList() {
  const tally = {};
  let traced = 0;
  for (const n of st.set) {
    const s = st.statuses[n]; if (!s) continue; traced++;
    const first = s.findIndex(x => x === 'bad');
    const key = first < 0 ? (s.includes('warn') ? 'refused' : 'right') : `fail at ${first}`;
    tally[key] = (tally[key] || 0) + 1;
  }
  const pos = st.set.length ? `${st.index + 1}/${st.set.length}` : '0 images';
  $p('#plTally').innerHTML = `${pos} · ${traced} traced` +
    (traced ? ' · ' + Object.entries(tally).sort().map(([k, v]) => `${esc(k.replace('fail at', 'fails at'))}: <b>${v}</b>`).join(' · ') : '');
  if (typeof window.onDebugStatuses === 'function') window.onDebugStatuses();
}

/// A traced image's library dot: its colour and the first stage it fails at.
function statusOf(name) {
  const s = st.statuses[name]; if (!s) return null;
  const first = s.findIndex(x => x === 'bad');
  return {color: first >= 0 ? BAD : s.includes('warn') ? WARN : OK, first: first >= 0 ? first : null,
          stage: first >= 0 ? STAGES[first].name : null};
}

async function go(i) {
  if (!st.set.length) return;
  st.index = Math.max(0, Math.min(st.set.length - 1, i));
  st.attempt = null;
  renderList();
  // The library follows: it highlights this image, and Annotation opens it.
  if (typeof window.onDebugImage === 'function') window.onDebugImage(st.set[st.index]);
  await traceCurrent(true);
}

// ---------------------------------------------------------------- the trace
async function fetchTrace(image, cache) {
  const body = {image, detector: st.opts.detector, classifier: st.opts.classifier, deskew: st.opts.deskew,
                budget: st.opts.budget, cache};
  const reply = await fetch('/api/trace', {method: 'POST', body: JSON.stringify(body)}).then(r => r.json());
  if (reply.tool) toolLine(reply.tool);
  return reply;
}

async function loadTruth(image) {
  if (st.truth[image]) return st.truth[image];
  let truth = {windows: [], expected: {}, rotationCW: 0, kind: 'still'};
  if (image.startsWith('frame/')) {
    const [, stem, file] = image.split('/');
    if (!st.recordCache || st.recordCache.stem !== stem) {
      const recs = await fetch('/api/records/' + encodeURIComponent(stem)).then(r => r.json());
      st.recordCache = {stem, rec: recs[0] || {frames: {}}};
    }
    const frame = (st.recordCache.rec.frames || {})[file] || {windows: []};
    truth.windows = frame.windows.map(w => ({field: w.field, text: w.text || '', quad: w.quad}));
    const e = await fetch('/api/entry/' + encodeURIComponent(stem)).then(r => r.json());
    const lab = {}; for (const w of truth.windows) if (w.text) lab[w.field] = w.text;
    truth.expected = {total: lab.total, liters: lab.liters, unitPrice: (e.row || {}).unitPrice};
    truth.kind = 'frame';
  } else {
    const e = await fetch('/api/entry/' + encodeURIComponent(image)).then(r => r.json());
    truth.windows = ((e.entry || {}).windows || []).map(w => ({field: w.field, text: w.text || '', quad: w.quad}));
    truth.rotationCW = (e.entry || {}).rotationCW || 0;
    truth.expected = e.row || {};
    truth.reviewed = !!(e.entry || {}).reviewed;
  }
  st.truth[image] = truth;
  return truth;
}

function loadImage(url) {
  if (st.images[url]) return st.images[url];
  st.images[url] = new Promise(res => { const im = new Image(); im.onload = () => res(im); im.onerror = () => res(null); im.src = url; });
  return st.images[url];
}
const photoURL = image => image.startsWith('frame/') ? '/' + image : '/image/' + encodeURIComponent(image);

async function traceCurrent(cache) {
  const image = st.set[st.index]; if (!image) return;
  $p('#plStatus').textContent = 'running the app path…';
  const started = performance.now();
  const [trace, truth] = await Promise.all([fetchTrace(image, cache), loadTruth(image)]);
  st.traces[image] = trace;
  if (!trace.error) st.statuses[image] = statuses(trace, truth);
  $p('#plStatus').textContent = trace.error ? `⚠ ${trace.error}` :
    `${trace.cached ? 'cached' : `ran in ${trace.ms} ms`} · round trip ${Math.round(performance.now() - started)} ms`;
  renderList();
  render();
  // Warm the next image so stepping is instant.
  const next = st.set[st.index + 1];
  if (next && !st.traces[next]) fetchTrace(next, true).then(t => { st.traces[next] = t; loadTruth(next).then(tr => { if (!t.error) st.statuses[next] = statuses(t, tr); renderList(); }); });
}

async function traceAll() {
  for (let i = 0; i < st.set.length && st.open; i++) {
    const image = st.set[i];
    if (!st.traces[image]) {
      $p('#plStatus').textContent = `tracing ${i + 1}/${st.set.length}…`;
      const [t, tr] = await Promise.all([fetchTrace(image, true), loadTruth(image)]);
      st.traces[image] = t; if (!t.error) st.statuses[image] = statuses(t, tr);
      renderList();
    }
  }
  $p('#plStatus').textContent = `traced ${st.set.length}`;
  render();
}

// ------------------------------------------------------------- geometry/truth
function bbox(q) { const xs = q.map(p => p[0]), ys = q.map(p => p[1]); return [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)]; }
function iou(a, b) {
  const [ax0, ay0, ax1, ay1] = bbox(a), [bx0, by0, bx1, by1] = bbox(b);
  const w = Math.min(ax1, bx1) - Math.max(ax0, bx0), h = Math.min(ay1, by1) - Math.max(ay0, by0);
  if (w <= 0 || h <= 0) return 0;
  const i = w * h; return i / ((ax1 - ax0) * (ay1 - ay0) + (bx1 - bx0) * (by1 - by0) - i);
}
const digits = t => String(t || '').replace(/[^0-9]/g, '');
const num = t => { const v = parseFloat(String(t ?? '').replace(',', '.')); return Number.isFinite(v) ? v : null; };
function attemptOf(trace) {
  if (!trace || !trace.attempts || !trace.attempts.length) return null;
  const i = st.attempt ?? (trace.chosen ?? trace.attempts.length - 1);
  return trace.attempts[Math.min(i, trace.attempts.length - 1)];
}
const handTx = truth => truth.windows.filter(w => FIELDS.includes(w.field) && w.quad);
function bestOver(list, quad) {
  let best = null, score = 0;
  for (const x of list) { const v = iou(x.quad, quad); if (v > score) { score = v; best = x; } }
  return score >= IOU_MATCH ? best : null;
}

// One status per stage for one image: ok / bad / warn / none (nothing to judge).
function statuses(trace, truth, attempt) {
  const a = attempt || (trace.attempts || [])[trace.chosen ?? (trace.attempts || []).length - 1];
  const out = STAGES.map(() => 'none');
  const hand = handTx(truth);
  if (!a) return out;
  const fin = trace.final || {};
  out[0] = fin.detection && fin.detection.display ? 'ok' : hand.length ? 'bad' : 'ok';
  out[1] = truth.kind === 'still' && hand.length ? (a.rotationCW === (truth.rotationCW || 0) ? 'ok' : 'bad') : 'none';
  if (!hand.length) return out;
  const found = hand.map(w => bestOver(a.candidates || [], w.quad) || bestOver(a.verdicts || [], w.quad));
  out[2] = found.every(Boolean) ? 'ok' : 'bad';
  const kept = hand.map(w => bestOver((a.verdicts || []).filter(v => v.kept), w.quad));
  out[3] = kept.every(Boolean) ? 'ok' : kept.some(Boolean) ? 'bad' : 'bad';
  const roles = hand.map(w => { const v = bestOver(a.verified || [], w.quad); return v ? v.role : undefined; });
  out[4] = roles.every((r, i) => r === hand[i].field) ? 'ok' : roles.some((r, i) => r && r !== hand[i].field) ? 'bad' : 'warn';
  let slice = 'ok', cls = 'ok';
  for (const w of hand) {
    const r = (a.reads || []).find(r => r.field === w.field);
    if (!r) { slice = slice === 'bad' ? 'bad' : 'warn'; cls = cls === 'bad' ? 'bad' : 'warn'; continue; }
    const want = digits(w.text);
    if (r.skipped) { slice = 'bad'; continue; }
    const n = (r.cellRects || []).filter(c => !c.blank).length;
    if (want && n !== want.length) slice = 'bad';
    const got = r.readings.map(c => c.top[0].d).join('');
    if (want && got.length === want.length && got !== want) cls = 'bad';
    else if (r.readings.some(c => c.margin < st.verifyMargin) && cls === 'ok') cls = 'warn';
  }
  out[5] = slice; out[6] = cls;
  const law = fin.law || a.law;
  if (!law) out[7] = 'warn';
  else {
    let s = 'ok';
    for (const f of FIELDS) {
      const v = law[f] && law[f].value, e = truth.expected[f];
      if (v == null) { if (e) s = s === 'bad' ? 'bad' : 'warn'; continue; }
      if (e == null || e === '') continue;
      if (Math.abs(num(v) - num(e)) > 0.005) s = 'bad';
    }
    out[7] = s;
  }
  return out;
}

// ------------------------------------------------------------------- render
function setZoom(z) { st.zoom = z === 'fit' ? 'fit' : Math.max(0.1, Math.min(8, z)); render(); }

async function render() {
  if (!st.open) return;
  const image = st.set[st.index], trace = st.traces[image], truth = st.truth[image];
  renderRail(trace, truth);
  const view = $p('#plView');
  const keep = {x: view.scrollLeft, y: view.scrollTop};
  $p('#plAllStripsWrap').style.display = st.stage === 5 ? '' : 'none';
  if (st.grid) { await renderGrid(); return; }
  if (!image) { view.innerHTML = '<p class="muted" style="padding:12px">Pick an image in the library on the left; ←/→ steps through the library as it is filtered.</p>'; return; }
  if (!trace) { view.innerHTML = '<p class="muted" style="padding:12px">running…</p>'; return; }
  if (trace.error) { view.innerHTML = `<pre style="color:${BAD};padding:12px;white-space:pre-wrap">${esc(trace.error)}\n${esc(trace.output || '')}</pre>`; return; }
  const a = attemptOf(trace);
  if (st.stage <= 4) await renderPhoto(view, image, trace, truth, a);
  else if (st.stage <= 6) renderStrips(view, trace, truth, a);
  else renderLaw(view, trace, truth, a);
  view.scrollLeft = keep.x; view.scrollTop = keep.y;
  renderInfo(trace, truth, a);
}

function renderRail(trace, truth) {
  const s = trace && !trace.error && truth ? statuses(trace, truth, attemptOf(trace)) : STAGES.map(() => 'none');
  $p('#plStages').innerHTML = STAGES.map((g, i) => `<div class="stage ${i === st.stage ? 'sel' : ''}" data-s="${i}" title="${esc(g.hint)}"><span class="n">${i}</span><span class="dot" style="background:${STATUS_COLOR[s[i]]}"></span>${g.name}</div>`).join('');
  for (const el of document.querySelectorAll('#plStages .stage')) el.onclick = () => { st.stage = +el.dataset.s; render(); };
  const at = (trace && trace.attempts) || [];
  $p('#plAttempts').innerHTML = at.length ? '<span class="muted">attempts</span>' + at.map((a, i) => {
    const sel = (st.attempt ?? trace.chosen ?? at.length - 1) === i;
    const law = a.law ? `${a.law.committed} committed` : a.detection && !a.detection.display ? 'not a display' : 'not read';
    return `<button data-a="${i}" class="${sel ? 'sel' : ''}" title="${a.kind} at ${a.rotationCW}°">${i === trace.chosen ? '★ ' : ''}${a.kind} ${a.rotationCW}° · ${law}</button>`;
  }).join('') : '';
  for (const el of document.querySelectorAll('#plAttempts button')) el.onclick = () => { st.attempt = +el.dataset.a; render(); };
}

async function renderPhoto(view, image, trace, truth, a) {
  const img = await loadImage(photoURL(image));
  if (!img) { view.innerHTML = '<p class="muted">image failed to load</p>'; return; }
  if (st.stage === 1) return renderOrientation(view, img, trace, truth);
  const fit = Math.min((view.clientWidth - 4) / img.naturalWidth, (view.clientHeight - 4) / img.naturalHeight);
  const z = st.zoom === 'fit' ? fit : st.zoom * fit;
  $p('#plZoomLbl').textContent = `${Math.round(z * 100)}%`;
  const cv = document.createElement('canvas');
  cv.width = Math.round(img.naturalWidth * z); cv.height = Math.round(img.naturalHeight * z);
  const g = cv.getContext('2d');
  g.drawImage(img, 0, 0, cv.width, cv.height);
  st.hit = [];
  drawStage(g, cv.width, cv.height, trace, truth, a, st.stage);
  view.innerHTML = ''; view.appendChild(cv);
  st.canvas = cv;
}

// Draws one stage's overlay onto a photo canvas of size W x H.
function drawStage(g, W, H, trace, truth, a, stage, small) {
  const lw = small ? 1.5 : 2.5, font = small ? 10 : 13;
  g.globalAlpha = st.layers.alpha;
  const poly = (q, color, dash, width) => {
    g.beginPath(); q.forEach(([x, y], i) => i ? g.lineTo(x * W, y * H) : g.moveTo(x * W, y * H)); g.closePath();
    g.setLineDash(dash || []); g.strokeStyle = color; g.lineWidth = width || lw; g.stroke(); g.setLineDash([]);
  };
  const label = (q, text, color) => {
    if (!st.layers.labels || !text) return;
    const [x0, y0] = bbox(q);
    g.font = `${font}px ui-monospace,monospace`;
    const w = g.measureText(text).width + 6;
    g.fillStyle = 'rgba(0,0,0,0.75)'; g.fillRect(x0 * W, y0 * H - font - 4, w, font + 4);
    g.fillStyle = color; g.fillText(text, x0 * W + 3, y0 * H - 4);
  };
  const hit = (q, info) => { if (!small) st.hit.push({q, info}); };
  if (st.layers.hand) for (const w of truth.windows) poly(w.quad, COLORS[w.field] || '#fff', [6, 5], 1.5);
  if (!a) return;
  if (stage === 0 || stage === 2) {
    for (const r of a.detectedRows || []) {
      const strong = r.confidence >= 0.3;
      poly(r.quad, strong ? '#4cc3ff' : GREY, strong ? [] : [3, 3]);
      label(r.quad, `det ${r.confidence.toFixed(2)}${r.passesSize ? '' : ' small'}`, strong ? '#4cc3ff' : GREY);
      hit(r.quad, `detector row · confidence ${r.confidence.toFixed(3)} · ${r.passesSize ? 'passes' : 'fails'} the size rules`);
    }
    if (stage === 2) for (const c of a.candidates || []) if (!c.detected) {
      poly(c.quad, '#b388ff', [2, 3], 1.2); hit(c.quad, 'Vision / classical proposal');
    }
  }
  if (stage === 3) {
    for (const v of a.verdicts || []) {
      if (!v.kept && !st.layers.dropped) continue;
      poly(v.quad, v.kept ? OK : BAD, v.kept ? [] : [5, 3]);
      label(v.quad, v.kept ? `kept ${v.cells}c` : v.reasons.join(','), v.kept ? OK : BAD);
      hit(v.quad, `${v.kept ? 'KEPT' : 'DROPPED'} · ${v.detected ? 'detector' : 'proposal'} · ${v.cells} cells · height ${(v.heightFraction * 100).toFixed(1)}% · margin ${v.meanMargin.toFixed(2)}${v.reasons.length ? ' · ' + v.reasons.join(', ') : ''}`);
    }
  }
  if (stage === 4) {
    for (const v of a.verified || []) {
      const hand = bestOver(truth.windows, v.quad);
      const wrong = hand && FIELDS.includes(hand.field) && v.role !== hand.field;
      poly(v.quad, wrong ? BAD : COLORS[v.role] || GREY, [], wrong ? lw * 1.6 : lw);
      label(v.quad, `${v.role || 'no role'}${wrong ? ` ≠ ${hand.field}` : ''}`, wrong ? BAD : COLORS[v.role] || GREY);
      hit(v.quad, `verified row → ${v.role || 'no role'} · ${v.cells} cells${hand ? ` · hand box: ${hand.field} "${hand.text}"` : ' · no hand box here'}`);
    }
  }
  g.globalAlpha = 1;
}

async function renderOrientation(view, img, trace, truth) {
  const scores = trace.orientationScores || [];
  const tried = (trace.attempts || []).map(a => a.rotationCW);
  const rots = [...new Set([0, ...scores.map(s => s.rotationCW)])];
  const box = document.createElement('div'); box.className = 'grid';
  const edge = st.zoom === 'fit' ? 360 : 360 * st.zoom;
  $p('#plZoomLbl').textContent = st.zoom === 'fit' ? 'fit' : `${Math.round(st.zoom * 100)}%`;
  const chosen = attemptOf(trace);
  for (const r of rots) {
    const s = scores.find(x => x.rotationCW === r);
    const cv = document.createElement('canvas');
    const turned = r % 180 !== 0;
    const w = turned ? img.naturalHeight : img.naturalWidth, h = turned ? img.naturalWidth : img.naturalHeight;
    const k = edge / Math.max(w, h);
    cv.width = w * k; cv.height = h * k;
    const g = cv.getContext('2d');
    g.translate(cv.width / 2, cv.height / 2); g.rotate(r * Math.PI / 180);
    g.drawImage(img, -img.naturalWidth * k / 2, -img.naturalHeight * k / 2, img.naturalWidth * k, img.naturalHeight * k);
    const isChosen = chosen && chosen.rotationCW === r, isTruth = (truth.rotationCW || 0) === r;
    const tile = document.createElement('div'); tile.className = 'tile';
    tile.style.borderColor = isChosen ? (isTruth || truth.kind !== 'still' ? OK : BAD) : 'var(--line)';
    tile.innerHTML = `<div><b>${r}°</b> ${isChosen ? '· read at this orientation' : ''} ${isTruth && truth.kind === 'still' ? '· <span style="color:' + OK + '">annotated</span>' : ''}</div>
      <div class="muted">${s ? `search: ${s.keptRows} row(s) pass geometry · ink ${Math.round(s.inkBandArea)}` : tried.includes(r) ? 'seed (no search ran: the seed read committed)' : 'not scored'}</div>`;
    tile.appendChild(cv); box.appendChild(tile);
  }
  view.innerHTML = ''; view.appendChild(box);
}

function stripCanvas(url, meta, cells, readings, field, scale, onReady) {
  const cv = document.createElement('canvas');
  loadImage(url).then(img => {
    if (!img) return;
    cv.width = meta.w * scale; cv.height = meta.h * scale;
    const g = cv.getContext('2d'); g.imageSmoothingEnabled = scale < 2;
    g.drawImage(img, 0, 0, cv.width, cv.height);
    let k = 0;
    for (const c of cells || []) {
      g.setLineDash(c.blank ? [3, 3] : []);
      g.strokeStyle = c.blank ? GREY : COLORS[field] || '#fff'; g.lineWidth = 1.5;
      g.strokeRect(c.x * scale, c.y * scale, c.w * scale, c.h * scale);
      if (!c.blank) {
        const rd = readings && readings[k];
        if (c.dp || (rd && rd.dp)) { g.fillStyle = c.dp ? '#fff' : WARN; g.beginPath(); g.arc((c.x + c.w) * scale, (c.y + c.h) * scale - 4, 4, 0, 7); g.fill(); }
        const lx = Math.max(0, c.x * scale), ly = Math.max(0, c.y * scale);
        g.fillStyle = 'rgba(0,0,0,0.7)'; g.fillRect(lx, ly, 14, 14);
        g.fillStyle = '#fff'; g.font = '11px ui-monospace,monospace'; g.fillText(String(k), lx + 3, ly + 11);
        k++;
      }
    }
    g.setLineDash([]);
    if (onReady) onReady(img);
  });
  return cv;
}

function renderStrips(view, trace, truth, a) {
  const z = st.zoom === 'fit' ? 1.5 : st.zoom * 1.5;
  $p('#plZoomLbl').textContent = `${Math.round(z * 100)}%`;
  view.innerHTML = '';
  if (!a) { view.innerHTML = '<p class="muted" style="padding:12px">no attempt</p>'; return; }
  const reads = a.reads || [];
  if (!reads.length) view.innerHTML = '<p class="muted" style="padding:12px">nothing was read: no verified row got a role, or the frame was not a display</p>';
  for (const r of reads) {
    const hand = truth.windows.find(w => w.field === r.field);
    const want = digits(hand && hand.text);
    const n = (r.cellRects || []).filter(c => !c.blank).length;
    const got = r.readings.map(c => c.top[0].d).join('');
    const box = document.createElement('div'); box.className = 'strip';
    const sliceOk = !want || n === want.length, readOk = !want || got === want;
    const col = r.skipped || !sliceOk ? BAD : st.stage === 6 && !readOk ? BAD : OK;
    box.style.borderColor = col;
    box.innerHTML = `<h4 style="color:${COLORS[r.field] || '#fff'}">${r.field} <span class="muted">·</span> <span style="color:${col}">${r.skipped ? 'skipped: ' + r.skipped : `${n} cell(s)${want ? ` · hand "${esc(hand.text)}" has ${want.length}` : ''}`}</span></h4>`;
    if (r.strip) {
      box.appendChild(stripCanvas(trace.base + r.strip.file, r.strip, r.cellRects, r.readings, r.field, z, img => {
        if (st.stage === 6) box.appendChild(cellTiles(img, r, want));
      }));
    }
    view.appendChild(box);
  }
  if (st.stage === 5 && st.showAllStrips) {
    const h = document.createElement('h4'); h.style.margin = '12px 8px 0'; h.textContent = 'every candidate the verifier judged';
    view.appendChild(h);
    (a.verdicts || []).forEach((v, i) => {
      const box = document.createElement('div'); box.className = 'strip'; box.style.borderColor = v.kept ? OK : BAD;
      box.innerHTML = `<h4 style="color:${v.kept ? OK : BAD}">#${i} ${v.kept ? 'kept' : 'dropped: ' + esc(v.reasons.join(', '))} <span class="muted">· ${v.cells} cells · ${v.detected ? 'detector' : 'proposal'}</span></h4>`;
      if (v.strip) box.appendChild(stripCanvas(trace.base + v.strip.file, v.strip, v.cellRects, null, 'board', Math.min(z, 1)));
      view.appendChild(box);
    });
  }
}

function cellTiles(img, r, want) {
  const wrap = document.createElement('div'); wrap.className = 'cells';
  const cells = (r.cellRects || []).filter(c => !c.blank);
  cells.forEach((c, i) => {
    const rd = r.readings[i]; if (!rd) return;
    const truthDigit = want && want.length === cells.length ? want[i] : null;
    const wrong = truthDigit != null && String(rd.top[0].d) !== truthDigit;
    const low = rd.margin < st.verifyMargin;
    const tile = document.createElement('div'); tile.className = 'cell';
    tile.style.borderColor = wrong ? BAD : low ? WARN : truthDigit != null ? OK : 'var(--line)';
    const cv = document.createElement('canvas'); const k = 96 / c.h;
    cv.width = Math.max(32, c.w * k); cv.height = 96;
    cv.getContext('2d').drawImage(img, c.x, c.y, c.w, c.h, 0, 0, cv.width, cv.height);
    tile.appendChild(cv);
    const alts = rd.top.slice(1).map(t => `<b>${t.d}</b> <span class="muted">−${(rd.top[0].lp - t.lp).toFixed(1)}</span>`).join(' &nbsp; ');
    const m = Math.max(0, Math.min(1, rd.margin / 6));
    tile.insertAdjacentHTML('beforeend', `<div class="big" style="color:${wrong ? BAD : '#fff'}">${rd.top[0].d}${rd.dp ? '.' : ''}</div>
      <div title="runner-up digits and how far behind the top one they are (log-posterior)">then ${alts}</div>
      <div>${truthDigit != null ? `hand <b>${truthDigit}</b>` : '<span class="muted">no hand digit</span>'}</div>
      <div class="muted">margin ${rd.margin.toFixed(2)} · dp ${(rd.dpProb * 100).toFixed(0)}%</div>
      <div class="bar"><i style="width:${m * 100}%;background:${low ? WARN : OK}"></i></div>`);
    wrap.appendChild(tile);
  });
  return wrap;
}

function lawRows(law, truth) {
  return FIELDS.map(f => {
    const x = law[f] || {}, e = truth.expected[f];
    const v = x.value;
    const verdict = v == null ? (e ? 'refused' : '–') : (e == null || e === '') ? 'no truth' : Math.abs(num(v) - num(e)) <= 0.005 ? '✓' : '✗ WRONG';
    const col = verdict === '✓' ? OK : verdict.startsWith('✗') ? BAD : verdict === 'refused' ? WARN : GREY;
    const prov = x.provenance && typeof x.provenance === 'object' && x.provenance.repaired
      ? `repaired cell ${x.provenance.repaired.cell}: ${x.provenance.repaired.from}→${x.provenance.repaired.to}` : (x.provenance || '');
    return `<tr><td style="color:${COLORS[f]}">${f}</td><td class="mono">${esc(e ?? '–')}</td><td class="mono" style="color:${col}"><b>${esc(v ?? '–')}</b></td><td style="color:${col}">${verdict}</td><td class="muted">${esc(prov)}${x.reason ? ' · ' + esc(x.reason) : ''}</td></tr>`;
  }).join('');
}

function renderLaw(view, trace, truth, a) {
  const fin = trace.final || {};
  const law = fin.law;
  let html = '<div style="padding:12px;max-width:820px">';
  html += `<h3 style="margin:0 0 6px">What the app would pre-fill</h3>`;
  if (!fin.routedAsPump) html += `<p style="color:${WARN}">Not routed as a pump display - the receipt path would run on this photo.</p>`;
  if (law) {
    html += `<table class="pl"><tr class="muted"><td>field</td><td>truth</td><td>committed</td><td></td><td>how</td></tr>${lawRows(law, truth)}</table>`;
    const L = num(law.liters.value), P = num(law.unitPrice.value) ?? num(truth.expected.unitPrice), T = num(law.total.value);
    if (L != null && P != null && T != null) {
      const calc = Math.round(L * P * 100) / 100;
      html += `<p class="mono">${L} × ${P} = ${calc.toFixed(2)} ${Math.abs(calc - T) < 0.011 ? `<span style="color:${OK}">= total ${T}</span>` : `<span style="color:${WARN}">≠ total ${T}</span>`}</p>`;
    }
    if (law.reason) html += `<p style="color:${WARN}">refused: <b>${esc(law.reason)}</b></p>`;
    if (law.caution) html += `<p style="color:${WARN}">caution: ${esc(law.caution)}</p>`;
  }
  html += '<h3 style="margin:16px 0 6px">Every attempt</h3>';
  (trace.attempts || []).forEach((x, i) => {
    html += `<div style="margin-bottom:10px"><b>${i === trace.chosen ? '★ ' : ''}${x.kind} at ${x.rotationCW}°</b> <span class="muted">${x.detection ? (x.detection.display ? `display (${x.detection.path}, ${x.detection.rows} rows)` : 'not a display') : ''}${x.budgetHit ? ' · budget hit' : ''}</span>`;
    html += x.law ? `<table class="pl">${lawRows(x.law, truth)}</table>` + (x.law.reason ? `<div style="color:${WARN}">refused: ${esc(x.law.reason)}</div>` : '') : '<div class="muted">no read</div>';
    html += '</div>';
  });
  html += '</div>';
  view.innerHTML = html;
}

function renderInfo(trace, truth, a) {
  const g = STAGES[st.stage];
  let h = `<h3 style="margin:0 0 4px">${st.stage} · ${g.name}</h3><p class="muted" style="margin:0 0 8px">${esc(g.hint)}</p>`;
  const fin = trace.final || {}, d = (a && a.detection) || fin.detection || {};
  if (st.stage === 0 && a) {
    const fast = a.fastVerdict;
    h += `<table class="pl">
      <tr><td>verdict</td><td style="color:${d.display ? OK : BAD}"><b>${d.display ? 'pump display' : 'not a display'}</b></td></tr>
      <tr><td>path</td><td>${fast ? 'fast - two stacked detector rows decided' : 'slow - the verifier decided'}</td></tr>
      <tr><td>detector rows</td><td>${(a.detectedRows || []).length} (${(a.detectedRows || []).filter(r => r.passesSize).length} pass size)</td></tr>
      <tr><td>display rows</td><td>${d.rows ?? '–'} <span class="muted">≥ 2</span></td></tr>
      <tr><td>text lines</td><td>${d.textLines ?? '–'} <span class="muted">≤ 30 on the slow path</span></td></tr>
      <tr><td>widest row</td><td>${d.widestRow != null ? (d.widestRow * 100).toFixed(1) + '%' : '–'} <span class="muted">≥ 18%</span></td></tr>
      <tr><td>budget</td><td>${trace.budget} s${a.budgetHit ? ` <b style="color:${BAD}">hit - refused</b>` : ''}</td></tr></table>`;
  }
  if (st.stage === 2 && a) h += `<p>${(a.detectedRows || []).length} detector row(s), ${(a.candidates || []).filter(c => !c.detected).length} proposal(s), ${(a.candidates || []).length} candidate(s) offered.</p>`;
  if (st.stage === 3 && a) {
    const reasons = {};
    for (const v of a.verdicts || []) if (!v.kept) for (const r of v.reasons) reasons[r] = (reasons[r] || 0) + 1;
    h += `<p>${(a.verdicts || []).length} judged, <b style="color:${OK}">${(a.verdicts || []).filter(v => v.kept).length} kept</b>, ${(a.verified || []).length} after duplicates.</p>`;
    h += Object.keys(reasons).length ? `<p>dropped for: ${Object.entries(reasons).map(([k, v]) => `${esc(k)} ×${v}`).join(', ')}</p>` : '';
  }
  if ([2, 3, 4].includes(st.stage) && a) {
    h += '<h4 style="margin:10px 0 4px">hand boxes</h4><table class="pl">';
    for (const w of handTx(truth)) {
      const c = bestOver([...(a.candidates || []), ...(a.verdicts || [])], w.quad);
      const k = bestOver((a.verdicts || []).filter(v => v.kept), w.quad);
      const dropped = !k && bestOver((a.verdicts || []).filter(v => !v.kept), w.quad);
      const role = bestOver(a.verified || [], w.quad);
      const state = st.stage === 2 ? (c ? ['found', OK] : ['MISSED', BAD])
        : st.stage === 3 ? (k ? ['kept', OK] : dropped ? [`dropped: ${dropped.reasons.join(', ')}`, BAD] : ['never offered', BAD])
        : role ? (role.role === w.field ? [`→ ${role.role}`, OK] : [`→ ${role.role || 'no role'}`, BAD]) : ['not verified', WARN];
      h += `<tr><td style="color:${COLORS[w.field]}">${w.field}</td><td class="mono">${esc(w.text)}</td><td style="color:${state[1]}">${esc(state[0])}</td></tr>`;
    }
    h += '</table>';
  }
  if (st.stage === 5 || st.stage === 6) h += '<p class="muted">Cells are numbered as the classifier sees them; a white dot is the slicer\'s decimal mark, an amber one the classifier\'s. Dashed cells are blank (unlit).</p>';
  h += `<h4 style="margin:12px 0 4px">image</h4><p class="mono" style="word-break:break-all">${esc(st.set[st.index])}</p>`;
  h += `<p class="muted">${truth.kind === 'still' ? (truth.reviewed ? 'annotation reviewed' : 'annotation NOT reviewed - a mismatch may be the box, not the reader') : 'video frame - truth is the frame label, when there is one'}</p>`;
  h += `<p class="muted">models: ${esc(trace.detector)}<br>${esc(trace.classifier)}<br>deskew ${esc(trace.deskew)} · currency ${esc(trace.currency || 'none')}</p>`;
  h += '<p class="muted" id="plHover"></p>';
  $p('#plInfo').innerHTML = h;
}

function hover(e) {
  if (!st.canvas || st.grid || st.stage > 4 || !st.hit) return;
  const r = st.canvas.getBoundingClientRect();
  const x = (e.clientX - r.left) / r.width, y = (e.clientY - r.top) / r.height;
  const hits = st.hit.filter(h => { const [x0, y0, x1, y1] = bbox(h.q); return x >= x0 && x <= x1 && y >= y0 && y <= y1; });
  const el = $p('#plHover'); if (el) el.innerHTML = hits.map(h => esc(h.info)).join('<br><br>');
}

async function renderGrid() {
  const view = $p('#plView');
  const traced = st.set.filter(n => st.traces[n] && !st.traces[n].error);
  view.innerHTML = `<div class="grid" id="plGridBox"></div>`;
  const box = $p('#plGridBox');
  if (!traced.length) { box.innerHTML = '<p class="muted">nothing traced yet - ▶ trace set</p>'; return; }
  for (const n of traced.slice(0, 60)) {
    const trace = st.traces[n], truth = await loadTruth(n);
    const a = attemptOf(trace), s = statuses(trace, truth, a)[st.stage];
    const tile = document.createElement('div'); tile.className = 'tile'; tile.style.borderColor = STATUS_COLOR[s];
    tile.innerHTML = `<div class="nm" title="${esc(n)}">${esc(n.replace(/^frame\//, '').slice(0, 40))}</div>`;
    tile.onclick = () => { st.grid = false; go(st.set.indexOf(n)); };
    if (st.stage <= 4) {
      const img = await loadImage(photoURL(n)); if (!img) continue;
      const k = 300 / Math.max(img.naturalWidth, img.naturalHeight);
      const cv = document.createElement('canvas'); cv.width = img.naturalWidth * k; cv.height = img.naturalHeight * k;
      const g = cv.getContext('2d'); g.drawImage(img, 0, 0, cv.width, cv.height);
      drawStage(g, cv.width, cv.height, trace, truth, a, st.stage === 1 ? 4 : st.stage, true);
      tile.appendChild(cv);
    } else if (st.stage <= 6) {
      const reads = (a && a.reads) || [];
      if (!reads.length) tile.insertAdjacentHTML('beforeend', `<div class="muted">${(trace.final || {}).detection && !trace.final.detection.display ? 'not a display - nothing read' : 'no row got a role - nothing read'}</div>`);
      for (const r of reads) {
        const hand = truth.windows.find(w => w.field === r.field), want = digits(hand && hand.text);
        const got = r.readings.map(c => c.top[0].d).join(''), n = (r.cellRects || []).filter(c => !c.blank).length;
        const bad = r.skipped || (want && (st.stage === 5 ? n !== want.length : got !== want));
        const row = document.createElement('div'); row.style.margin = '4px 0';
        row.innerHTML = `<div class="mono" style="color:${bad ? BAD : OK}"><span style="color:${COLORS[r.field] || '#fff'}">${r.field}</span> ${r.skipped ? esc(r.skipped) : st.stage === 5 ? `${n} cells${want ? ' / hand ' + want.length : ''}` : `${got || '–'}${want ? ' / hand ' + want : ''}`}</div>`;
        if (r.strip) row.appendChild(stripCanvas(trace.base + r.strip.file, r.strip, r.cellRects, r.readings, r.field, Math.min(0.6, 300 / r.strip.w)));
        tile.appendChild(row);
      }
    } else {
      const law = (trace.final || {}).law;
      tile.insertAdjacentHTML('beforeend', law ? `<table class="pl">${lawRows(law, truth)}</table>` : '<div class="muted">not read</div>');
    }
    box.appendChild(tile);
  }
}

async function save() {
  const image = st.set[st.index], trace = st.traces[image]; if (!trace) return;
  const cv = document.querySelector('#plView canvas');
  const png = cv ? cv.toDataURL('image/png') : '';
  const r = await fetch('/api/trace/save', {method: 'POST', body: JSON.stringify({image, stage: STAGES[st.stage].key, trace, png})}).then(r => r.json());
  $p('#plStatus').textContent = r.dir ? `saved ${r.dir}` : `save failed: ${r.error || ''}`;
}

// --------------------------------------------------------------------- keys
function keys(e) {
  if (!st.open) return false;
  const t = e.target;
  const typing = t.tagName === 'TEXTAREA' || t.tagName === 'SELECT' || (t.tagName === 'INPUT' && !['range', 'checkbox', 'radio'].includes(t.type));
  if (typing) return true;
  const k = e.key;
  if (k === 'ArrowRight') { e.preventDefault(); go(st.index + 1); }
  else if (k === 'ArrowLeft') { e.preventDefault(); go(st.index - 1); }
  else if (k === 'ArrowDown') { e.preventDefault(); st.stage = Math.min(STAGES.length - 1, st.stage + 1); render(); }
  else if (k === 'ArrowUp') { e.preventDefault(); st.stage = Math.max(0, st.stage - 1); render(); }
  else if (/^[0-7]$/.test(k) && !e.metaKey && !e.ctrlKey) { e.preventDefault(); st.stage = +k; render(); }
  else if (k === 'g' || k === 'G') { e.preventDefault(); st.grid = !st.grid; render(); }
  else if (k === '+' || k === '=') { e.preventDefault(); setZoom((st.zoom === 'fit' ? 1 : st.zoom) * 1.25); }
  else if (k === '-') { e.preventDefault(); setZoom((st.zoom === 'fit' ? 1 : st.zoom) / 1.25); }
  else if (k === 'f') { e.preventDefault(); setZoom('fit'); }
  return true;
}

window.pipelineView = {show, hide, select, refreshSet, keys, statusOf, get isOpen() { return st.open; }};
})();
