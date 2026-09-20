'use strict';
/* SALU Remote — interactive preview.
 * Review artifact only: no Flutter, nothing wired into lib/.
 * Marks are drawn from the real painters' geometry (lib/ui/widgets/salu_marks.dart,
 * transport_marks.dart); colours are AppColors from lib/theme/app_theme.dart. */

// ── marks ────────────────────────────────────────────────────────────────
// Stroke follows markStrokeFor(size) = clamp(size * 0.085, 1.4, 2.2), which is
// 1.53 at the 18 px these are used at.
const SW = 1.53;
const svg = (size, body, extra = '') =>
  `<svg viewBox="0 0 18 18" width="${size}" height="${size}" fill="none" ` +
  `stroke="currentColor" stroke-width="${SW}" stroke-linecap="round" ` +
  `stroke-linejoin="round" ${extra}>${body}</svg>`;

const M = {
  // transport_marks.dart · _ChevronPainter
  prev:  (s=18) => svg(s, '<path d="M6.12 5.76L1.8 9l4.32 3.24M10.44 5.76L6.12 9l4.32 3.24"/><path d="M16.2 4.32v9.36"/>'),
  back:  (s=18) => svg(s, '<path d="M7.56 5.76L3.24 9l4.32 3.24M13.68 5.76L9.36 9l4.32 3.24"/>'),
  play:  (s=18) => svg(s, '<path d="M6.12 3.96L11.88 9l-5.76 5.04z"/>'),
  fwd:   (s=18) => svg(s, '<path d="M4.32 5.76L8.64 9l-4.32 3.24M10.44 5.76L14.76 9l-4.32 3.24"/>'),
  next:  (s=18) => svg(s, '<path d="M1.8 5.76L6.12 9L1.8 12.24M7.92 5.76L12.24 9l-4.32 3.24"/><path d="M16.2 4.32v9.36"/>'),
  pause: (s=18) => svg(s, '<path d="M6.48 4.32v9.36M11.52 4.32v9.36"/>'),
  stop:  (s=18) => svg(s, '<rect x="3.78" y="3.78" width="10.44" height="10.44" rx="2.34"/>'),
  // salu_marks.dart · _RepeatPainter — 3/4 arc + arrowhead, bead for repeat-one
  repeat: (s=18, quiet=false, bead=false) => svg(s,
    `<path d="M11.77 5.77A4.5 4.5 0 1 0 12.5 9"/>` +
    `<path d="M10.81 5.37L11.77 5.77L12.17 4.81"/>` +
    (bead ? '<circle cx="9" cy="9" r="1.62" fill="currentColor" stroke="none"/>' : ''),
    quiet ? 'opacity="0.55"' : ''),
  // salu_marks.dart · _ShufflePainter — crossing rules + chevron-V heads
  shuffle: (s=18, quiet=false) => svg(s,
    '<path d="M2.88 5.4L11.16 10.44M2.88 12.6L11.16 7.56"/>' +
    '<path d="M11.16 10.44L7.95 10.18M11.16 10.44L9.47 13.17"/>' +
    '<path d="M11.16 7.56L7.95 7.82M11.16 7.56L9.47 4.83"/>',
    quiet ? 'opacity="0.55"' : ''),
  // dot_grid_icon.dart — six dots, dot = clamp(size * 0.17, 1.6, 4) = 3.06
  dots: (s=18) => {
    const d = 3.06;
    const row = (y) => `<circle cx="${(18-d)/2}" cy="${y}" r="${d/2}" fill="currentColor" stroke="none"/>` +
      `<circle cx="9" cy="${y}" r="${d/2}" fill="currentColor" stroke="none"/>` +
      `<circle cx="${18-(18-d)/2}" cy="${y}" r="${d/2}" fill="currentColor" stroke="none"/>`;
    return `<svg viewBox="0 0 18 18" width="${s}" height="${s}">${row(5.7)}${row(12.3)}</svg>`;
  },
  // salu_marks.dart · _InfoPainter — the sheet (locked in right-menu-preview)
  info: (s=18) => svg(s,
    '<path d="M4.14 1.8h6.3l3.96 3.96v10.44H4.14z"/><path d="M10.44 1.8v3.96h3.96"/>' +
    '<path d="M6.48 9.54h5.22M6.48 12.6h4.32"/>'),
  // remote.md §10.1 · the NEW QrMark — three corner finders + a sparse dot field
  qr: (s=18) => svg(s,
    '<rect x="1.6" y="1.6" width="4.7" height="4.7" rx="0.7"/><rect x="3.1" y="3.1" width="1.7" height="1.7" rx="0.3" fill="currentColor" stroke="none"/>' +
    '<rect x="11.7" y="1.6" width="4.7" height="4.7" rx="0.7"/><rect x="13.2" y="3.1" width="1.7" height="1.7" rx="0.3" fill="currentColor" stroke="none"/>' +
    '<rect x="1.6" y="11.7" width="4.7" height="4.7" rx="0.7"/><rect x="3.1" y="13.2" width="1.7" height="1.7" rx="0.3" fill="currentColor" stroke="none"/>' +
    '<path d="M8.4 1.9v3.2M10.3 1.9v1.4M8.4 6.9h1.9M8.4 8.4h3.4M13.1 8.4h3M8.4 10.1v2.9"/>' +
    '<path d="M8.4 14.9h1.6M11.6 11.7v1.5M11.6 14.9v1.2M13.4 11.7h2.7M15 13.4v1.3M13.4 16.1h2.7"/>'),
  speaker: (s=18, muted=false) => svg(s,
    '<path d="M3.2 6.9h2.7l3.6-3.1v10.4l-3.6-3.1H3.2z"/>' +
    (muted ? '<path d="M12.3 6.9l3.3 4.2M15.6 6.9l-3.3 4.2"/>'
           : '<path d="M11.9 6.5a3.4 3.4 0 0 1 0 5M14 4.7a6.2 6.2 0 0 1 0 8.6"/>')),
  fullscreen: (s=18) => svg(s,
    '<path d="M2.2 6.4V2.2h4.2M15.8 6.4V2.2h-4.2M2.2 11.6v4.2h4.2M15.8 11.6v4.2h-4.2"/>'),
  queue: (s=18) => svg(s,
    '<path d="M3.3 4.6h8.4M3.3 9h8.4M3.3 13.4h8.4"/>' +
    '<path d="M13.9 7.4l2.2 1.6-2.2 1.6z" fill="currentColor" stroke="none"/>'),
  globe: (s=18) => svg(s, '<circle cx="9" cy="9" r="6.9"/><path d="M2.1 9h13.8"/>' +
    '<path d="M9 2.1c2.2 2.4 2.2 11.4 0 13.8-2.2-2.4-2.2-11.4 0-13.8z"/>'),
  folder: (s=18) => svg(s, '<path d="M1.9 4.6h4.6l1.6 1.9h8v9.1H1.9z"/>'),
  drive: (s=18) => svg(s, '<rect x="1.9" y="4.6" width="14.2" height="8.8" rx="1.4"/>' +
    '<circle cx="13.1" cy="9" r="0.95" fill="currentColor" stroke="none"/>'),
  film: (s=18) => svg(s, '<rect x="2.2" y="3.4" width="13.6" height="11.2" rx="1.2"/>' +
    '<path d="M2.2 6.6h13.6M2.2 11.4h13.6M6.1 3.4v3.2M11.9 3.4v3.2M6.1 11.4v3.2M11.9 11.4v3.2"/>'),
  file: (s=18) => svg(s, '<path d="M4.3 1.9h5.6l3.8 3.8v10.4H4.3z"/><path d="M9.9 1.9v3.8h3.8"/>'),
  link: (s=18) => svg(s, '<path d="M7.6 10.4a3 3 0 0 0 4.3 0l2.3-2.3a3 3 0 0 0-4.3-4.3l-.9.9"/>' +
    '<path d="M10.4 7.6a3 3 0 0 0-4.3 0l-2.3 2.3a3 3 0 0 0 4.3 4.3l.9-.9"/>'),
  cc: (s=18) => svg(s, '<rect x="1.7" y="4.1" width="14.6" height="9.8" rx="2"/>' +
    '<path d="M7.3 7.7a2 2 0 1 0 0 2.6M12.6 7.7a2 2 0 1 0 0 2.6"/>'),
  eq: (s=18) => svg(s, '<path d="M4.6 2.4v13.2M9 2.4v13.2M13.4 2.4v13.2"/>' +
    '<rect x="3.1" y="9.4" width="3" height="2.2" rx="0.7" fill="var(--bg)" stroke="currentColor"/>' +
    '<rect x="7.5" y="5.4" width="3" height="2.2" rx="0.7" fill="var(--bg)" stroke="currentColor"/>' +
    '<rect x="11.9" y="11" width="3" height="2.2" rx="0.7" fill="var(--bg)" stroke="currentColor"/>'),
  search: (s=18) => svg(s, '<circle cx="7.9" cy="7.9" r="4.9"/><path d="M11.5 11.5l4.1 4.1"/>'),
  plus: (s=18) => svg(s, '<path d="M9 3.2v11.6M3.2 9h11.6"/>'),
  arrowLeft: (s=18) => svg(s, '<path d="M11.2 3.6L5.8 9l5.4 5.4"/>'),
  reload: (s=18) => svg(s, '<path d="M14.2 6.4A5.9 5.9 0 1 0 14.9 9.9"/><path d="M14.6 2.9v3.6h-3.6"/>'),
  x: (s=13) => `<svg viewBox="0 0 16 16" width="${s}" height="${s}" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"><path d="M4.2 4.2l7.6 7.6M11.8 4.2l-7.6 7.6"/></svg>`,
  chevronDown: (s=12) => `<svg viewBox="0 0 16 16" width="${s}" height="${s}" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 6.4L8 10.2l4-3.8"/></svg>`,
};

// ── helpers ──────────────────────────────────────────────────────────────
const $ = (id) => document.getElementById(id);
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const esc = (s) => String(s).replace(/[&<>"]/g, (c) =>
  ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const fmtTime = (ms) => {
  if (!isFinite(ms) || ms < 0) ms = 0;
  const t = Math.floor(ms / 1000);
  const h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), s = t % 60;
  const p = (n) => String(n).padStart(2, '0');
  return h ? `${h}:${p(m)}:${p(s)}` : `${m}:${p(s)}`;
};
const fmtSize = (mb) => (mb >= 1024 ? (mb / 1024).toFixed(1) + 'G' : mb + 'M');

// ── state ────────────────────────────────────────────────────────────────
const BANDS = ['31', '63', '125', '250', '500', '1k', '2k', '4k', '8k', '16k'];
const SPEEDS = ['0.5×', '0.75×', '1×', '1.25×', '1.5×', '2×', '3×'];
const PRESETS = ['Flat', 'Rock', 'Pop', 'Jazz', 'Classical', 'Bass', 'Vocal', 'My'];
const EPISODES = [
  'Episode 1.mkv', 'Episode 2.mkv', 'Episode 3.mkv', 'Big Buck Bunny.mkv',
  'Episode 4.mkv', 'Episode 5.mkv', 'Episode 6.mkv', 'Sintel.mp4',
  'Episode 7.mkv', 'Tears of Steel.mkv', 'Episode 8.mkv', 'Cosmos Laundromat.mp4',
];
const FS = {
  'C:': [
    { k: 'folder', n: 'Users' }, { k: 'folder', n: 'Program Files' },
    { k: 'folder', n: 'Windows' }, { k: 'file', n: 'notes.txt', mb: 1 },
  ],
  'D:': [
    { k: 'folder', n: 'Movies' }, { k: 'folder', n: 'Music' },
    { k: 'folder', n: 'Downloads' }, { k: 'media', n: 'Dune.Part.One.2021.mkv', mb: 4200 },
    { k: 'media', n: 'Alien.mkv', mb: 2200 }, { k: 'file', n: 'readme.txt', mb: 1 },
  ],
  'D:\\Movies': [
    { k: 'up' }, { k: 'folder', n: '2024' }, { k: 'folder', n: 'Extras' },
    { k: 'media', n: 'Dune.Part.One.2021.1080p.mkv', mb: 4200 },
    { k: 'media', n: 'Alien.mkv', mb: 2200 },
    { k: 'media', n: 'Blade.Runner.2049.mkv', mb: 5100 },
    { k: 'file', n: 'notes.txt', mb: 1 },
  ],
  'D:\\Movies\\2024': [
    { k: 'up' }, { k: 'media', n: 'Episode 1.mkv', mb: 1800 },
    { k: 'media', n: 'Episode 2.mkv', mb: 1750 }, { k: 'media', n: 'Episode 3.mkv', mb: 1810 },
    { k: 'media', n: 'Episode 4.mkv', mb: 1790 },
  ],
  'Now playing': [{ k: 'up' }, { k: 'media', n: 'Episode 3.mkv', mb: 1810 },
    { k: 'media', n: 'Episode 4.mkv', mb: 1790 }],
  'Videos': [{ k: 'up' }, { k: 'media', n: 'holiday.mp4', mb: 340 }],
  'Music': [{ k: 'up' }, { k: 'media', n: 'Nightfall.flac', mb: 42 }],
  'Downloads': [{ k: 'up' }, { k: 'media', n: 'trailer.mp4', mb: 120 }],
  'Desktop': [{ k: 'up' }, { k: 'file', n: 'todo.txt', mb: 1 }],
};
/* The focusables on the mock page. A real D-pad walks the page's own tab order
 * (link · button · input); this stands in for it so the ring has somewhere to go. */
const WEB_FOCUS = [
  { tag: 'input',  n: 'Search' },
  { tag: 'link',   n: 'Sign in' },
  { tag: 'button', n: 'Play / pause the video', act: 'play' },
  { tag: 'link',   n: 'Dune: Part Two — Official Trailer' },
  { tag: 'button', n: 'Subscribe · 4.2M' },
  { tag: 'link',   n: '12,480 comments' },
];

const PLACES = [
  { n: 'Now playing', i: 'play' }, { n: 'Downloads', i: 'arrowLeft' },
  { n: 'Videos', i: 'film' }, { n: 'Music', i: 'eq' }, { n: 'Desktop', i: 'drive' },
];

const S = {
  remoteOn: true, fileAccess: true,
  status: 'running',            // running | off | waiting
  ip: '192.168.0.12', port: 7258, pcName: 'DESKTOP-ABC',
  code: '7K4MQP2X',
  devices: [],                  // { id, name, sub, control }
  connected: false, controlName: null,
  mode: 'player',
  playing: true, hasMedia: true,
  title: 'Big Buck Bunny', sub: 'Sintel · 1080p',
  position: 754000, duration: 596000,
  volume: 80, muted: false, shuffle: false, repeat: 'off',
  fullscreen: false,
  queue: EPISODES.map((n) => n.replace(/\.[^.]+$/, '')), index: 3, queueOpen: true,
  tab: 'play', focus: false,
  browseSeg: 'files', tuneSeg: 'eq',
  path: 'D:\\Movies', page: 0, filterOn: true,
  bands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0], preset: 'Flat', autoEq: true, speed: '1×',
  subTracks: [
    { n: 'English (embedded)', on: true }, { n: 'off', on: false },
    { n: 'Bengali — local .srt', on: false },
  ],
  subDelay: 0, autoDownload: true,
  audioTracks: [{ n: 'English · 5.1 AC3', on: true }, { n: 'Hindi · 2.0 AAC', on: false }],
  web: { title: 'Dune: Part Two — Official Trailer', url: 'https://www.youtube.com/watch?v=dune-trailer',
         tabs: 3, hasMedia: true, position: 754000, duration: 161000, volume: 70, muted: false, canBack: true },
  webPlaying: true,
  webFocus: 2,
  sheet: true, connectErr: '', sheetMode: 'pair',
  menu: null,                   // {x, y}
  remotePanel: false,
  log: [],
};

// ── the socket log ───────────────────────────────────────────────────────
function logMsg(dir, obj) {
  const stamp = new Date().toLocaleTimeString('en-GB', { hour12: false });
  S.log.push({ dir, stamp, text: JSON.stringify(obj) });
  if (S.log.length > 300) S.log.shift();   // a review session outruns 40 frames easily
  const el = $('log');
  if (!el) return;
  el.innerHTML = S.log.map((l) =>
    `<div><span class="t">${l.stamp}</span> <span class="${l.dir}">${l.dir === 'out' ? '→' : '←'}</span> ${esc(l.text)}</div>`
  ).join('');
  el.scrollTop = el.scrollHeight;
}
const cmd = (verb, args) => {
  logMsg('out', args ? { type: 'cmd', id: Math.floor(Math.random() * 900) + 1, verb, args } : { type: 'cmd', id: Math.floor(Math.random() * 900) + 1, verb });
  logMsg('in', { type: 'ack', id: 7, ok: true });
};
/* remote.md §6.3 — one message type, one shape, always complete. There is no
 * `event` message in v1: a snapshot *is* the event (D5). */
function pushState() {
  logMsg('in', {
    type: 'state', rev: (S.rev = (S.rev || 40) + 1), at: Date.now(),
    mode: S.mode,
    window: { mode: 'full', fullscreen: S.fullscreen },
    playback: { state: S.playing ? 'playing' : 'paused', hasMedia: S.hasMedia,
                title: S.title, kind: 'video', position: S.position,
                duration: S.duration, buffering: false,
                seekable: S.duration > 0, volume: S.volume, muted: S.muted,
                shuffle: S.shuffle, repeat: S.repeat },
    queue: { kind: S.queue.length ? 'files' : 'empty', count: S.queue.length, index: S.index },
    control: S.controlName ? { deviceId: 'a1b2c3', name: S.controlName } : null,
    devices: S.devices.map((d) => ({ id: d.id, name: d.name, online: d.control, control: d.control })),
  });
}

/* D8 — a *transport* command arriving while the PC is in Web mode pulls SALU
 * back to Player mode and focuses the window. The PC says so by pushing a full
 * snapshot, never a partial one. */
function pullToPlayer() {
  if (S.mode !== 'web') return;
  S.mode = 'player';
  pushState();
}

// ── actions ──────────────────────────────────────────────────────────────
function rotateCode() {
  const A = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let s = '';
  for (let i = 0; i < 8; i++) s += A[Math.floor(Math.random() * A.length)];
  S.code = s;
}
const pairUri = () =>
  `salu://pair?v=1&n=${S.pcName}&h=${S.ip}&p=${S.port}&c=${S.code}`;
const prettyCode = () => `${S.code.slice(0, 4)}-${S.code.slice(4)}`;

function openRemotePanel() {
  S.menu = null;
  S.remotePanel = true;
  render();
}
function closeRemotePanel() {
  S.remotePanel = false;
  rotateCode();                       // A5 — the code rotates when the panel closes
  render();
}
function toggleRemote() {
  S.remoteOn = !S.remoteOn;
  if (!S.remoteOn) {
    S.status = 'off';
    S.connected = false;
    S.controlName = null;
    S.remotePanel = false;
    logMsg('in', { type: 'close', code: 4004, reason: 'Remote control is switched off' });
  } else {
    S.status = 'running';
    rotateCode();
    logMsg('in', { type: 'hello', proto: 1, server: 'SALU', version: '0.1.0', name: S.pcName });
  }
  render();
}
function pairPhone() {
  S.connected = true;
  S.sheet = false;
  S.controlName = 'Pixel 7';
  S.devices = [{ id: 'a1b2c3', name: 'Pixel 7', sub: 'has control', control: true },
               { id: 'b7d1f0', name: 'Redmi Note', sub: 'last seen 2 h ago', control: false }];
  logMsg('in', { type: 'auth', id: 1, proto: 1, pair: S.code, device: { name: 'Pixel 7', platform: 'android' } });
  logMsg('out', { type: 'auth_ok', id: 1, deviceId: 'a1b2c3', token: '••••', control: true });
  pushState();
  render();
}
function unpair() {
  S.connected = false;
  S.controlName = null;
  S.devices = [];
  S.sheet = true;
  S.sheetMode = 'pair';
  S.connectErr = '';
  logMsg('in', { type: 'close', code: 4001, reason: 'Device forgotten on the PC' });
  render();
}
function forgetDevice(id) {
  S.devices = S.devices.filter((d) => d.id !== id);
  if (!S.devices.some((d) => d.control)) { S.controlName = null; S.connected = false; S.sheet = true; }
  render();
}

let toastTimer = null;
function phoneToast(text) {
  const screen = $('screen');
  if (!screen) return;
  screen.querySelectorAll('.ptoast').forEach((n) => n.remove());
  const el = document.createElement('div');
  el.className = 'ptoast';
  el.textContent = text;
  screen.appendChild(el);
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.remove(), 2200);
}

let osdTimer = null;
function osd(text) {
  const el = $('osd');
  el.textContent = text;
  el.classList.add('show');
  clearTimeout(osdTimer);
  osdTimer = setTimeout(() => el.classList.remove('show'), 1100);
}

function togglePlay() {
  pullToPlayer();
  S.playing = !S.playing;
  cmd(S.playing ? 'play' : 'pause');
  osd(S.playing ? '▶  Play' : '⏸  Pause');
  render();
}
function seekTo(ms, silent) {
  pullToPlayer();
  S.position = clamp(ms, 0, S.duration);
  if (S.mode === 'web') S.web.position = clamp(S.position, 0, S.web.duration);
  if (!silent) { cmd('seek_to', { position: Math.round(S.position) }); osd(`»  ${fmtTime(S.position)}`); }
  render();
}
function nudge(ms) { seekTo(S.position + ms); }
function setVolume(v, fromPhone) {
  S.volume = clamp(Math.round(v), 0, 100);
  if (!fromPhone) cmd('volume_set', { volume: S.volume });
  render();                                   // A1 — no OSD card for volume
}
function setWebVolume(v) { S.web.volume = clamp(Math.round(v), 0, 100); cmd('web_media_volume', { volume: S.web.volume }); render(); }
function toggleMute() { S.muted = !S.muted; cmd('mute_set', { muted: S.muted }); render(); }
function toggleWebMute() { S.web.muted = !S.web.muted; cmd('web_media_mute', { muted: S.web.muted }); render(); }
function cycleRepeat() {
  S.repeat = S.repeat === 'off' ? 'all' : S.repeat === 'all' ? 'one' : 'off';
  cmd('repeat_set', { mode: S.repeat });
  osd(`Repeat · ${S.repeat}`);
  render();
}
function toggleShuffle() { S.shuffle = !S.shuffle; cmd('shuffle_set', { on: S.shuffle }); osd(`Shuffle · ${S.shuffle ? 'on' : 'off'}`); render(); }
function toggleFullscreen() { S.fullscreen = !S.fullscreen; cmd('fullscreen_set', { on: S.fullscreen }); osd(S.fullscreen ? 'Fullscreen' : 'Windowed'); render(); }
function stopPlayback() { pullToPlayer(); S.playing = false; cmd('stop'); osd('⏹  Stop'); render(); }
function skip(delta) {
  pullToPlayer();
  S.index = clamp(S.index + delta, 0, S.queue.length - 1);
  S.title = S.queue[S.index];
  S.sub = 'Episode · 1080p';
  S.position = 0;
  S.playing = true;
  cmd(delta < 0 ? 'prev' : 'next');
  osd(`${delta < 0 ? '⏮' : '⏭'}  ${S.title}`);
  pushState();
  render();
}
function jumpTo(i) {
  S.index = i;
  S.title = S.queue[i];
  S.position = 0;
  S.playing = true;
  cmd('queue_jump', { index: i });
  osd(`▶  ${S.title}`);
  pushState();
  render();
}
/* One D-pad press. ▲▼ walk the page's focus; ◀▶ are history, which is the
 * escape hatch when focus-walking lands somewhere useless; OK activates. */
function webKey(k) {
  if (k === 'left' || k === 'right') {
    cmd('browser_nav', { action: k === 'left' ? 'back' : 'forward' });
    phoneToast(k === 'left' ? '◀  Back' : '▶  Forward');
    return;
  }
  if (k === 'ok') {
    const f = WEB_FOCUS[S.webFocus];
    if (f.act === 'play') {
      S.webPlaying = !S.webPlaying;
      cmd('web_media_toggle');
      phoneToast(S.webPlaying ? '▶  Page player playing' : '⏸  Page player paused');
    } else {
      logMsg('out', { type: 'cmd', id: Math.floor(Math.random() * 900) + 1, verb: 'web_key', args: { key: 'Enter' } });
      logMsg('in', { type: 'ack', id: 7, ok: true });
      phoneToast(`↵  ${f.n}`);
    }
    return;
  }
  const d = k === 'up' ? -1 : 1;
  S.webFocus = (S.webFocus + d + WEB_FOCUS.length) % WEB_FOCUS.length;
  logMsg('out', { type: 'cmd', id: Math.floor(Math.random() * 900) + 1, verb: 'web_key',
                  args: { key: k === 'up' ? 'ArrowUp' : 'ArrowDown' } });
  logMsg('in', { type: 'ack', id: 7, ok: true });
  render();
}

function setMode(mode) {
  if (S.mode === mode) return;
  S.mode = mode;
  if (mode === 'web' && S.tab === 'browse') S.tab = 'play';   // Browse is Player-only
  if (mode === 'player') S.webFocus = 2;
  cmd('mode_set', { mode });
  pushState();
  osd(mode === 'web' ? '◑  Web mode' : '◐  Player mode');
  render();
}
function playPath(name) {
  // The file never travels — the phone sends a path, the PC opens it locally.
  S.mode = 'player';
  S.hasMedia = true;
  S.title = name.replace(/\.[^.]+$/, '');
  S.sub = name.split('\\').pop();
  S.position = 0;
  S.playing = true;
  const qi = S.queue.findIndex((q) => q === S.title);
  if (qi >= 0) S.index = qi;
  cmd('fs_open', { path: (S.path === 'Now playing' ? 'D:\\Movies\\2024\\' : S.path + '\\') + name });
  osd(`▶  ${S.title}`);
  pushState();
  S.tab = 'play';
  render();
}
function queuePath(name) {
  const t = name.replace(/\.[^.]+$/, '');
  if (!S.queue.includes(t)) S.queue.push(t);
  cmd('queue_add', { paths: [(S.path === 'Now playing' ? 'D:\\Movies\\2024\\' : S.path + '\\') + name] });
  osd(`＋  Queued ${t}`);
  render();
}
function playUrl(u) {
  if (/youtube|http/.test(u) && !/\.(m3u8?|mp4|mkv)$/i.test(u)) {
    S.mode = 'web';
    S.web.url = u;
    S.web.title = 'Dune: Part Two — Official Trailer';
    cmd('browser_open', { url: u });
  } else {
    S.mode = 'player';
    S.title = u.split('/').pop();
    S.playing = true;
    cmd('open_url', { url: u });
  }
  osd('▶  ' + (S.mode === 'web' ? 'Opened in the browser' : S.title));
  render();
}

// ── PC rendering ─────────────────────────────────────────────────────────
function renderOsc() {
  const pct = S.duration ? (S.position / S.duration) * 100 : 0;
  const web = S.mode === 'web';
  $('osc').innerHTML = web ? `
      <span class="icb" data-act="webback" title="Back">${M.arrowLeft(18)}</span>
      <span class="icb" data-act="webreload" title="Reload">${M.reload(18)}</span>
      <span style="flex:1"></span>
      <span class="meta" style="color:var(--sec);font-size:11.5px">Web mode · ${S.web.tabs} tabs</span>
    ` : `
      <span class="t">${fmtTime(S.position)}</span>
      <span class="track" id="pcTrack"><span class="rail"><span class="fill" style="width:${pct}%"></span></span></span>
      <span class="t r">${fmtTime(S.duration)}</span>
      <span class="icb ${S.playing ? '' : ''}" data-act="play" title="${S.playing ? 'Pause' : 'Play'}">${S.playing ? M.pause(18) : M.play(18)}</span>
      <span class="icb ${S.muted ? 'active' : ''}" data-act="mute" title="Mute">${M.speaker(18, S.muted)}</span>
    `;
  const c = $('canvas');
  c.classList.toggle('web', web);
  $('vid').style.display = web ? 'none' : 'grid';
  $('webpage').style.display = web ? 'flex' : 'none';
  $('pcTitle').textContent = web ? `${S.web.title} — SALU` : S.title;
  $('pcMeta').textContent = web ? `Web mode · ${S.web.tabs} tabs` : 'Video · 1080p · h264';
  $('pcUrl').textContent = S.web.url;
}

/* The PC's page, redrawn so the D-pad's focus has somewhere visible to land.
 * Without this ring the phone would be steering the browser blind. */
function renderWebPage() {
  const el = $('webbody');
  if (!el) return;
  el.innerHTML = `
    <div class="vframe"><svg viewBox="0 0 24 24"><path d="M10 8.5l6 3.5-6 3.5z"/></svg></div>
    <h4>${esc(S.web.title)}</h4>
    ${WEB_FOCUS.map((f, i) => `<div class="frow ${i === S.webFocus ? 'on' : ''}">
        <span class="tag">${f.tag}</span><span>${esc(f.n)}</span></div>`).join('')}`;
}

function renderSettings() {
  const on = S.remoteOn;
  $('settings').innerHTML = `
    <h3>Settings · General · Remote</h3>
    <div class="sub">Slots in after the Equalizer block, using the <code>_AutoEqSwitch</code> layout. Global — reachable in Player <i>and</i> Web mode, and in mini.</div>
    <div class="srow">
      <span class="tile">${M.qr(16)}</span>
      <span class="txt"><span class="t">Remote control</span>
        <span class="h">Let the SALU Remote app on your phone control playback. Local network only.</span></span>
      <span class="sw ${on ? 'on' : ''}" data-act="toggleRemote"><i></i></span>
    </div>
    <div class="srow ${on ? '' : 'dis'}">
      <span class="tile">${M.folder(16)}</span>
      <span class="txt"><span class="t">Let phones browse PC files</span>
        <span class="h">Read-only. Folders and media names only. <i>(v1.1 · default ON)</i></span></span>
      <span class="sw ${on && S.fileAccess ? 'on' : ''} ${on ? '' : 'dis'}" data-act="toggleFiles"><i></i></span>
    </div>
    <div class="srow ${on ? '' : 'dis'}" data-act="${on ? 'openPanel' : ''}" style="${on ? 'cursor:pointer' : ''}">
      <span class="tile">${M.qr(16)}</span>
      <span class="txt"><span class="t">Show pairing code…</span>
        <span class="h">${on ? 'Opens the Remote panel.' : 'Turn remote control on to pair a phone.'}</span></span>
      <span class="chev">›</span>
    </div>
    <div class="srow" style="cursor:default">
      <span class="tile">${M.dots(16)}</span>
      <span class="txt"><span class="t">Remembered phones</span>
        <span class="h">${S.devices.length} paired · opens the same panel</span></span>
      <span class="chev">›</span>
    </div>`;
}

function renderRemotePanel() {
  if (!S.remotePanel) return '';
  const running = S.remoteOn;
  const waiting = running && !S.connected;
  const statusHtml = !running
    ? '<span class="dot dead"></span> Remote is off — turn it on in Settings'
    : waiting
      ? '<span class="dot wait"></span> Waiting for your phone'
      : `<span class="dot alive"></span> Connected · Wi-Fi · ${S.ip} · ${S.port}`;

  let qrHtml;
  if (!running) {
    qrHtml = `<div class="qrnote" style="padding:52px 0">Turn remote control on in Settings<br>to pair a phone.</div>`;
  } else {
    let code;
    try {
      code = encodeQr(pairUri(), 'M');
    } catch (e) {
      code = null;
    }
    if (code) {
      const px = 208 / code.size;
      let rects = '';
      for (let r = 0; r < code.size; r++) {
        for (let c = 0; c < code.size; c++) {
          if (code.modules[r][c]) {
            rects += `<rect x="${(c * px).toFixed(2)}" y="${(r * px).toFixed(2)}" width="${(px + 0.35).toFixed(2)}" height="${(px + 0.35).toFixed(2)}"/>`;
          }
        }
      }
      qrHtml = `<div class="qrcard"><svg viewBox="0 0 208 208" shape-rendering="crispEdges">
          <rect width="208" height="208" fill="#fff"/><g fill="#000">${rects}</g></svg></div>
        <div class="qrnote">Scan with <b style="color:var(--text)">SALU Remote</b><br>
          or enter <span class="code">${prettyCode()}</span></div>`;
    } else {
      qrHtml = `<div class="qrnote" style="padding:52px 0">Payload too long for this preview encoder.</div>`;
    }
  }

  const devices = S.devices.length
    ? S.devices.map((d) => `<div class="prow">
        <span class="dot ${d.control ? 'alive' : 'unknown'}" style="background:${d.control ? 'var(--alive)' : 'var(--unknown)'}"></span>
        <span class="nm">${esc(d.name)}</span>
        <span class="st">${esc(d.sub)}</span>
        <span class="fg" data-act="forget" data-id="${d.id}">✕ Forget</span>
      </div>`).join('')
    : '<div class="empty">No phones paired yet.</div>';

  return `<div class="barrier" data-act="closePanel">
    <div class="modal" data-stop>
      <div class="hd"><h3>Remote</h3><span class="xbtn" data-act="closePanel">${M.x(13)}</span></div>
      <div class="statusline">${statusHtml}</div>
      ${qrHtml}
      ${running ? `<div class="foot">This code is only for pairing. It changes when you close this panel.</div>` : ''}
      <div class="sect">Phones</div>
      ${devices}
      ${waiting ? `<div class="fw">⚠ Can't connect? Windows Firewall may be blocking SALU.
        <br><button data-act="noop">Open firewall settings</button></div>` : ''}
    </div></div>`;
}

function renderPc() {
  renderOsc();
  renderWebPage();
  renderSettings();
  // strip + panel live inside the canvas
  const c = $('canvas');
  c.querySelectorAll('.strip,.barrier').forEach((n) => n.remove());
  if (S.menu) {
    const w = 198, h = 42;                      // remote.md §5.3 — full canvas with QR
    const x = clamp(S.menu.x - w / 2, 12, c.clientWidth - w - 12);
    const y = S.menu.y + 10 + h <= c.clientHeight - 12
      ? S.menu.y + 10 : S.menu.y - 10 - h;
    const el = document.createElement('div');
    el.className = 'strip';
    el.style.left = x + 'px';
    el.style.top = clamp(y, 12, c.clientHeight - h - 12) + 'px';
    el.style.width = w + 'px';
    const b = (act, title, mark, cls = '') =>
      `<span class="icb ${cls}" data-act="${act}" title="${title}">${mark}</span>`;
    el.innerHTML =
      b('shuffle', 'Shuffle', M.shuffle(18, !S.shuffle), S.shuffle ? 'active' : '') +
      '<span class="s"></span>' +
      b('repeat', 'Repeat · ' + S.repeat, M.repeat(18, S.repeat === 'off', S.repeat === 'one'), S.repeat !== 'off' ? 'active' : '') +
      '<span class="g"></span>' +
      b('info', 'Info', M.info(18)) +
      '<span class="s"></span>' +
      b('settings', 'Settings', M.dots(18)) +
      '<span class="s"></span>' +
      `<span style="position:relative">${b('remote', 'Remote', M.qr(18))}
         <span class="newseat">NEW · D9</span></span>`;
    c.appendChild(el);
  }
  if (S.remotePanel) c.insertAdjacentHTML('beforeend', renderRemotePanel());
}

// ── phone rendering ──────────────────────────────────────────────────────
function header() {
  const online = S.connected && S.remoteOn;
  const dot = !S.remoteOn ? 'var(--dead)' : online ? 'var(--alive)' : 'var(--unknown)';
  const name = !S.remoteOn ? 'Remote is off on the PC' : online ? 'Living Room PC' : 'Not connected';
  return `<div class="phead">
    <div class="r1">
      <span class="dot" style="background:${dot}"></span>
      <span class="nm">${esc(name)}<span class="act ${S.busy ? 'on' : ''}"></span></span>
      <span class="chevbtn ${S.focus ? 'up' : ''}" data-act="focus" title="Focus mode">${M.chevronDown(12)}</span>
      <span class="chevbtn" data-act="sheet" title="Connection">⋮</span>
    </div>
    <span class="modeseg">
      <button class="${S.mode === 'player' ? 'on' : ''}" data-act="setmode" data-v="player">
        ${M.play(12)} Player</button>
      <button class="${S.mode === 'web' ? 'on web' : ''}" data-act="setmode" data-v="web">
        ${M.globe(12)} Web</button>
    </span>
  </div>`;
}

function seekBar() {
  const dur = S.mode === 'web' ? S.web.duration : S.duration;
  const pos = S.mode === 'web' ? S.web.position : S.position;
  const pct = dur ? (pos / dur) * 100 : 0;
  return `<div class="seekrow">
      <span class="ptrack" data-seek="${S.mode}"><span class="rail"><span class="fill" style="width:${pct}%"></span></span></span>
      <span class="times"><span>${fmtTime(pos)}</span><span>${fmtTime(dur)}</span></span>
    </div>`;
}
function volBar(v, act, muted) {
  return `<div class="volrow">
    <span data-act="${muted ? 'webunmute' : 'webmute'}" style="cursor:pointer">${M.speaker(17, muted)}</span>
    <span class="vtrack" data-vol="${act}"><span class="rail"><span class="fill" style="width:${v}%"></span></span></span>
    <span class="val">${muted ? '—' : v}</span></div>`;
}

function playTab() {
  if (!S.connected || !S.remoteOn) return offlineBody();
  if (S.mode === 'web') return webBody();
  const f = S.focus;
  const queueRows = S.queue.slice(Math.max(0, S.index - 1), Math.max(0, S.index - 1) + 5)
    .map((q, i) => {
      const real = Math.max(0, S.index - 1) + i;
      const now = real === S.index;
      return `<div class="qrow ${now ? 'now' : ''}" data-act="jump" data-i="${real}">
        <span class="ix">${now ? '' : real + 1}</span>${now ? M.play(11) : ''}
        <span class="nm">${esc(q)}</span></div>`;
    }).join('');

  return `<div class="pbody"><div class="pad">
    <div class="pTitle">${esc(S.title)}<span class="sub">${esc(S.sub)}</span></div>
    ${seekBar()}
    <div class="transport">
      <span class="icb" data-act="prev">${M.prev(21)}</span>
      <span class="icb" data-act="back">${M.back(21)}</span>
      <span class="icb play" data-act="play">${S.playing ? M.pause(30) : M.play(30)}</span>
      <span class="icb" data-act="fwd">${M.fwd(21)}</span>
      <span class="icb" data-act="next">${M.next(21)}</span>
    </div>
    ${f ? '' : `<div class="chips">
      <span class="chip" data-act="stop">${M.stop(13)} Stop</span>
      <span class="chip ${S.shuffle ? 'on' : ''}" data-act="shuffle">${M.shuffle(13)} Shuffle</span>
      <span class="chip ${S.repeat !== 'off' ? 'on' : ''}" data-act="repeat">${M.repeat(13)} ${S.repeat === 'one' ? 'Repeat one' : S.repeat === 'all' ? 'Repeat all' : 'Repeat'}</span>
      <span class="chip ${S.fullscreen ? 'on' : ''}" data-act="fs">${M.fullscreen(13)} Fullscreen</span>
      <span class="chip" data-act="queueToggle">${M.queue(13)} Queue</span>
    </div>
    <div class="volrow">
      ${M.speaker(17, S.muted)}
      <span class="vtrack" data-vol="pc"><span class="rail"><span class="fill" style="width:${S.volume}%"></span></span></span>
      <span class="val">${S.muted ? '—' : S.volume}</span>
    </div>
    <div class="card ${S.queueOpen ? '' : 'closed'}">
      <div class="ch" data-act="queueToggle"><span>Queue</span><span class="n">· ${S.queue.length} items</span>
        <span class="cv">${M.chevronDown(11)}</span></div>
      <div class="cb">${queueRows}</div>
    </div>`}
  </div></div>`;
}

function webBody() {
  const w = S.web;
  const navRow = `<div class="chips" style="margin:12px 2px 2px">
      <span class="chip" data-act="webback">${M.arrowLeft(13)} Back</span>
      <span class="chip" data-act="webfwd">Fwd</span>
      <span class="chip" data-act="webreload">${M.reload(13)} Reload</span>
      <span class="chip" data-act="webfs">${M.fullscreen(13)}</span>
      <span class="chip">${w.tabs} tabs</span>
    </div>`;
  if (!w.hasMedia) {
    return `<div class="pbody"><div class="pad">
      ${navRow}
      <div class="card"><div class="ch" style="cursor:default"><span>${esc(w.title)}</span></div>
        <div class="cb" style="max-height:none"><div style="padding:0 12px 11px;font-size:10.5px;color:#6e6e73;word-break:break-all">${esc(w.url)}</div></div></div>
      <div class="linebtn" data-act="openurl">${M.link(14)} Open a URL on the PC</div>
      <div class="nothing" style="padding:22px 10px">No media on this page — the transport rows are hidden rather than sitting there dead.</div>
    </div></div>`;
  }
  return `<div class="pbody"><div class="pad">
    ${navRow}
    <div class="pTitle" style="margin-top:14px" data-act="openurl">${esc(w.title)}
      <span class="sub">Tap the title to open a URL on the PC</span></div>
    ${seekBar()}
    <div style="display:grid;place-items:center;margin:22px 0 6px">
      <span class="icb play" data-act="webplay" style="width:74px;height:74px">${S.webPlaying === false ? M.play(32) : M.pause(32)}</span>
    </div>
    ${volBar(w.volume, 'web', w.muted)}
    <div class="nothing" style="padding:20px 10px;font-size:11px">
      These drive the <b style="display:inline;font-size:11px">page's own player</b>, not mpv. The volume slider is the site's — it never touches the Windows volume.</div>
  </div></div>`;
}

function offlineBody() {
  return `<div class="pbody"><div class="nothing" style="padding-top:70px">
    <b>${S.remoteOn ? 'Not connected' : 'Remote is off on the PC'}</b>
    ${S.remoteOn ? 'Open the Remote panel on the PC and scan the QR.'
                 : 'Turn on Settings → General → Remote control.'}
    <br><button data-act="sheet">Open the Connect sheet</button>
  </div></div>`;
}

function browseTab() {
  if (!S.connected || !S.remoteOn) return offlineBody();
  const seg = `<div class="seg">
      <button class="${S.browseSeg === 'files' ? 'on' : ''}" data-act="bseg" data-v="files">Files</button>
      <button class="${S.browseSeg === 'streams' ? 'on' : ''}" data-act="bseg" data-v="streams">Streams</button>
    </div>`;
  if (S.browseSeg === 'streams') {
    return `<div class="pbody">${seg}
      <div class="urlrow" data-act="addurl">${M.plus(14)} Add a URL</div>
      <div class="subhead">Saved on the PC</div>
      <div class="srow2" data-act="stream" data-u="http://10.0.0.5:8001/bdix.m3u8">
        <span class="dot alive"></span><span class="nm">BDIX IPTV<span class="u">http://10.0.0.5:8001/bdix.m3u8</span></span>${M.play(13)}</div>
      <div class="srow2" data-act="stream" data-u="http://cdn.example.com/sports/index.m3u8">
        <span class="dot alive"></span><span class="nm">Sports m3u8<span class="u">http://cdn.example.com/sports/index.m3u8</span></span>${M.play(13)}</div>
      <div class="srow2" data-act="stream" data-u="https://www.youtube.com/watch?v=dune-trailer">
        <span class="dot dead"></span><span class="nm">Festival cam<span class="u">https://fest.example.com/live</span></span>${M.play(13)}</div>
      <div class="nothing" style="padding:20px 14px;font-size:11px">
        This is the PC's own <code>UrlLibraryService</code>, mirrored — never a second list on the phone. The health dot is the PC's verdict.</div>
    </div>`;
  }
  if (!S.fileAccess) {
    return `<div class="pbody">${seg}<div class="nothing" style="padding-top:60px">
      <b>File browsing is turned off on the PC</b>
      Settings → General → Remote → “Let phones browse PC files”.
    </div></div>`;
  }
  const crumbs = S.path.split('\\').filter(Boolean);
  const items = (FS[S.path] || []).slice(0, S.page * 3 + 6);
  const total = (FS[S.path] || []).length + (S.path === 'D:\\Movies' ? 480 : 0);
  const rows = items.map((it, i) => {
    if (it.k === 'up') return `<div class="frow" data-act="up">${M.arrowLeft(15)}<span class="nm">..</span></div>`;
    if (it.k === 'folder') return `<div class="frow" data-act="cd" data-n="${esc(it.n)}">${M.folder(15)}<span class="nm">${esc(it.n)}</span>
      <span class="qk"><b data-act="cd" data-n="${esc(it.n)}">›</b></span></div>`;
    if (it.k === 'media') return `<div class="frow" data-act="fplay" data-n="${esc(it.n)}">${M.film(15)}<span class="nm">${esc(it.n)}</span>
      <span class="sz">${fmtSize(it.mb)}</span>
      <span class="qk"><b data-act="fplay" data-n="${esc(it.n)}">▶</b><b data-act="fqueue" data-n="${esc(it.n)}">＋</b></span></div>`;
    return `<div class="frow dim">${M.file(15)}<span class="nm">${esc(it.n)}</span><span class="sz">${fmtSize(it.mb)}</span></div>`;
  }).join('');
  const places = `<div class="subhead">Quick places</div><div class="places">
      ${PLACES.map((p) => `<span class="chip" data-act="place" data-n="${esc(p.n)}">${M[p.i](13)} ${esc(p.n)}</span>`).join('')}
    </div>
    <div class="subhead">Drives</div><div class="places">
      ${['C:', 'D:', 'E:'].map((d) => `<span class="chip" data-act="cd" data-n="${d}">${M.drive(13)} ${d}</span>`).join('')}
    </div>`;
  const atRoot = !FS[S.path] || S.path.length <= 2;
  return `<div class="pbody">${seg}
    ${atRoot ? places : `<div class="crumb">${crumbs.map((c, i) =>
        `<span data-act="crumb" data-i="${i}">${esc(c)}</span>${i < crumbs.length - 1 ? '<i>›</i>' : ''}`).join('')}</div>`}
    <div class="flist">${rows}
      <div class="more"><span data-act="more">${S.page * 3 + 6 < total ? `⋯ ${total - (S.page * 3 + 6)} more` : 'End of folder'}</span>
        <span data-act="filter">${S.filterOn ? '⚙ Media only' : '⚙ All files'}</span></div>
    </div>
    <div class="nothing" style="padding:14px 14px 22px;font-size:10.5px">
      Read-only, forever. No delete, no rename, no move. The file never travels — the PC opens the path locally, so a 40 GB file costs one message.</div>
  </div>`;
}

/* Web mode has no equalizer, no subtitles and no audio track — mpv is not in
 * the picture. What it does have is a page to get around, so Tune becomes a
 * D-pad: ▲▼ walk the page's focus, ◀▶ are history, OK clicks.
 *
 * NEW VERB. remote.md §17.4 defines browser_nav and the web_media_* family but
 * nothing that moves focus, so this needs `web_key {key}` added to the spec.
 * It would be injected JavaScript through the same WebTab.executeScript path
 * remote_web_media_bridge.dart already uses. */
function dpadTab() {
  const f = WEB_FOCUS[S.webFocus];
  const btn = (k, label, mark) =>
    `<button data-act="dpad" data-k="${k}">${mark}${label ? `<span>${label}</span>` : ''}</button>`;
  const up = '<svg viewBox="0 0 16 16"><path d="M8 12.4V3.6M4.2 7.4L8 3.6l3.8 3.8"/></svg>';
  const dn = '<svg viewBox="0 0 16 16"><path d="M8 3.6v8.8M4.2 8.6L8 12.4l3.8-3.8"/></svg>';
  const lf = '<svg viewBox="0 0 16 16"><path d="M10.4 3.6L4.6 8l5.8 4.4"/></svg>';
  const rt = '<svg viewBox="0 0 16 16"><path d="M5.6 3.6L11.4 8l-5.8 4.4"/></svg>';
  return `<div class="pbody">
    <div class="subhead">Navigate the page</div>
    <div class="dpadwrap"><div class="dpad">
      <span class="sp"></span>${btn('up', '', up)}<span class="sp"></span>
      ${btn('left', 'Back', lf)}
      <button class="ok" data-act="dpad" data-k="ok">OK</button>
      ${btn('right', 'Fwd', rt)}
      <span class="sp"></span>${btn('down', '', dn)}<span class="sp"></span>
    </div>
    <div class="dpadhint">▲▼ move the focus &nbsp;·&nbsp; ◀▶ back and forward &nbsp;·&nbsp; OK clicks</div>
    </div>
    <div class="focused"><span class="lbl">Focused</span><b>${esc(f.n)}</b>
      <span style="flex:1"></span><span class="lbl">${f.tag}</span></div>
    <div class="nothing" style="padding:14px 16px 22px;font-size:10.5px">
      The PC draws a ring on whatever the phone has focused — without it you would be
      steering the browser blind. Text fields keep the arrows for the caret, so OK
      submits instead of clicking.</div>
  </div>`;
}

function tuneTab() {
  if (!S.connected || !S.remoteOn) return offlineBody();
  const seg = `<div class="seg">
      <button class="${S.tuneSeg === 'eq' ? 'on' : ''}" data-act="tseg" data-v="eq">Equalizer</button>
      <button class="${S.tuneSeg === 'subs' ? 'on' : ''}" data-act="tseg" data-v="subs">Subs</button>
      <button class="${S.tuneSeg === 'audio' ? 'on' : ''}" data-act="tseg" data-v="audio">Audio</button>
    </div>`;
  if (S.mode === 'web') return dpadTab();
  if (!S.hasMedia) {
    return `<div class="pbody">${seg}<div class="nothing" style="padding-top:64px">
      <b>Nothing is playing</b>Open something on the PC, or pick a file in Browse.
      <br><button data-act="gotab" data-v="browse">Go to Browse</button></div></div>`;
  }
  if (S.tuneSeg === 'subs') {
    return `<div class="pbody">${seg}
      <div class="subhead">Tracks <span class="cv">${M.chevronDown(11)}</span></div>
      ${S.subTracks.map((t, i) => `<div class="track2 ${t.on ? 'on' : ''}" data-act="subtrack" data-i="${i}">
        <span class="rd"></span><span class="nm">${esc(t.n)}</span></div>`).join('')}
      <div class="subhead">Sync <span class="cv">${M.chevronDown(11)}</span></div>
      <div class="syncrow">
        <button data-act="subsync" data-d="-0.5">−0.5s</button>
        <span class="v">${S.subDelay.toFixed(1)} s</span>
        <button data-act="subsync" data-d="0.5">+0.5s</button>
        <button data-act="subreset">Reset</button>
      </div>
      <div class="linebtn" data-act="subsearch">${M.search(14)} Search online…</div>
      <div class="linebtn" data-act="subfile">${M.folder(14)} Add a subtitle file</div>
      <div class="swrow"><span class="t">Auto-download on play<span class="h">Mirrors the PC's existing setting.</span></span>
        <span class="sw ${S.autoDownload ? 'on' : ''}" data-act="autodl"><i></i></span></div>
      <div class="nothing" style="padding:12px 14px 22px;font-size:10.5px">
        The PC downloads and applies — the phone only asks and watches. The subtitle is on screen before your thumb leaves the phone.</div>
    </div>`;
  }
  if (S.tuneSeg === 'audio') {
    return `<div class="pbody">${seg}
      <div class="subhead">Audio tracks</div>
      ${S.audioTracks.map((t, i) => `<div class="track2 ${t.on ? 'on' : ''}" data-act="audiotrack" data-i="${i}">
        <span class="rd"></span><span class="nm">${esc(t.n)}</span></div>`).join('')}
      <div class="nothing" style="padding:16px 14px;font-size:10.5px">Tap to switch — no confirmation.</div>
    </div>`;
  }
  // equalizer
  const pts = S.bands.map((v, i) => {
    const x = 10 + (i * 280) / 9;
    const y = 46 - (v / 12) * 34;
    return `${x.toFixed(1)},${y.toFixed(1)}`;
  }).join(' ');
  return `<div class="pbody">${seg}
    <div class="curve"><svg viewBox="0 0 300 92" preserveAspectRatio="none">
      <path d="M10 46h280" stroke="#2c2e33" stroke-width="1" stroke-dasharray="3 4"/>
      <polyline points="${pts}" fill="none" stroke="var(--accent)" stroke-width="2"
        stroke-linecap="round" stroke-linejoin="round"/>
      ${S.bands.map((v, i) => `<circle cx="${(10 + (i * 280) / 9).toFixed(1)}" cy="${(46 - (v / 12) * 34).toFixed(1)}" r="2.6" fill="var(--accent)"/>`).join('')}
    </svg></div>
    <div class="chips" style="margin:10px 12px">
      ${PRESETS.map((p) => `<span class="chip ${S.preset === p ? 'on' : ''}" data-act="preset" data-v="${p}">${p === 'My' ? '⭐ ' : ''}${p}</span>`).join('')}
    </div>
    <div class="sliders">
      ${BANDS.map((b, i) => {
        const v = S.bands[i];
        const frac = (v + 12) / 24;
        const midPct = (12 / 24) * 100;
        const top = Math.min(frac, midPct) * 100;
        const hgt = Math.abs(frac - midPct) * 100;
        return `<div class="sl ${v ? 'act' : ''}">
          <span class="well" data-band="${i}">
            <span class="wrail"></span>
            <span class="wfill" style="top:${(100 - top - hgt).toFixed(1)}%;height:${hgt.toFixed(1)}%"></span>
            <span class="knob" style="top:calc(${(100 - frac * 100).toFixed(1)}% - 4px)"></span>
          </span>
          <span class="lb">${b}</span></div>`;
      }).join('')}
    </div>
    <div class="chips" style="margin:8px 12px 0">
      <span class="chip" data-act="eqreset">Reset</span>
      <span class="chip ${S.autoEq ? 'on' : ''}" data-act="autoeq">Auto EQ</span>
    </div>
    <div class="subhead">Speed</div>
    <div class="chips" style="margin:0 12px 6px">
      ${SPEEDS.map((s) => `<span class="chip ${S.speed === s ? 'on' : ''}" data-act="speed" data-v="${s}">${s}</span>`).join('')}
    </div>
    <div class="nothing" style="padding:12px 14px 22px;font-size:10.5px">
      The PC's own preset list and its own speed stops, verbatim — the phone renders what the PC sends, so the two can never disagree.</div>
  </div>`;
}

function renderPhone() {
  const online = S.connected && S.remoteOn;
  const showMini = online && S.tab !== 'play' && S.hasMedia;
  let body;
  if (S.tab === 'play') body = playTab();
  else if (S.tab === 'browse') body = browseTab();
  else body = tuneTab();

  // Browse is Player-only: opening a PC file pulls the PC out of Web mode
  // anyway (D8), so the tab would only ever bounce you back.
  const tabs = ['play', 'browse', 'tune'].map((t) => {
    const dis = t === 'browse' && S.mode === 'web';
    return `<span class="tab ${S.tab === t ? 'on' : ''}${dis ? ' dis' : ''}"
      data-act="${dis ? 'tabdis' : 'tab'}" data-v="${t}">${t}</span>`;
  }).join('');

  let sheet = '';
  if (S.sheet) {
    sheet = S.sheetMode === 'code' ? `<div class="sheet" data-act="closesheet"><div class="panel" data-stop>
        <h3>Enter the code</h3>
        <p>The PC shows it under the QR, as four letters, a dash, four more.</p>
        <input id="codein" value="${esc(S.code)}" spellcheck="false" autocomplete="off">
        <button class="big" data-act="trycode">Connect</button>
        <button class="alt" data-act="sheetmode" data-v="pair">Scan a QR instead</button>
        <div class="err">${esc(S.connectErr)}</div>
      </div></div>`
      : `<div class="sheet" data-act="closesheet"><div class="panel" data-stop>
        <h3>${S.remoteOn ? 'Connect to SALU' : 'Remote is off on the PC'}</h3>
        <p>${S.remoteOn
          ? 'On the PC: right-click the picture, then choose Remote. A QR appears — point the camera at it.'
          : 'Ask at the PC: Settings → General → Remote control must be on.'}</p>
        <button class="big" data-act="pair" ${S.remoteOn ? '' : 'disabled style="opacity:.45"'}>Scan the QR on the PC</button>
        <button class="alt" data-act="sheetmode" data-v="code">Enter a code instead</button>
        <div class="err">${esc(S.connectErr)}</div>
      </div></div>`;
  }

  $('phone').innerHTML = `
    ${header()}
    ${body}
    ${showMini ? `<div class="mini" data-act="tab" data-v="play">
        ${S.playing ? M.pause(14) : M.play(14)}
        <span class="ti">${esc(S.title)}</span>
        <span class="tm">${fmtTime(S.position)} / ${fmtTime(S.duration)}</span></div>` : ''}
    <div class="tabs">${tabs}</div>
    ${sheet}`;
}

// ── render ───────────────────────────────────────────────────────────────
function render() {
  renderPc();
  renderPhone();
  document.querySelectorAll('#barMode button').forEach((b) => {
    b.classList.toggle('on', b.dataset.v === S.mode);
    b.classList.toggle('web', b.dataset.v === 'web' && S.mode === 'web');
  });
}

// ── events ───────────────────────────────────────────────────────────────
document.addEventListener('click', (e) => {
  const stop = e.target.closest('[data-stop]');
  const t = e.target.closest('[data-act]');
  if (!t) {
    if (S.menu && !e.target.closest('.strip')) { S.menu = null; render(); }
    return;
  }
  if (stop && t.closest('.modal')) { /* clicks inside the modal do not dismiss it */ }
  const a = t.dataset.act;
  const v = t.dataset.v;
  switch (a) {
    case 'shuffle': toggleShuffle(); break;
    case 'repeat': cycleRepeat(); break;
    case 'info': S.menu = null; osd('Info panel (not part of this preview)'); render(); break;
    case 'settings': S.menu = null; osd('Settings'); render(); break;
    case 'remote': openRemotePanel(); break;
    case 'closePanel': if (!stop) closeRemotePanel(); break;
    case 'forget': forgetDevice(t.dataset.id); break;
    case 'toggleRemote': toggleRemote(); break;
    case 'toggleFiles': if (S.remoteOn) { S.fileAccess = !S.fileAccess; render(); } break;
    case 'openPanel': S.remotePanel = true; render(); break;
    case 'noop': break;

    case 'play': togglePlay(); break;
    case 'mute': toggleMute(); break;
    case 'webback': cmd('browser_nav', { nav: 'back' }); osd('◀  Back'); break;
    case 'webfwd': cmd('browser_nav', { nav: 'forward' }); break;
    case 'webreload': cmd('browser_nav', { nav: 'reload' }); osd('⟳  Reload'); break;
    case 'webfs': cmd('browser_fullscreen', {}); break;
    case 'webplay': S.webPlaying = S.webPlaying === false; cmd(S.webPlaying ? 'web_media_pause' : 'web_media_play'); break;
    case 'webmute': toggleWebMute(); break;
    case 'webunmute': toggleWebMute(); break;

    case 'prev': skip(-1); break;
    case 'next': skip(1); break;
    case 'back': nudge(-10000); break;
    case 'fwd': nudge(10000); break;
    case 'stop': stopPlayback(); break;
    case 'fs': toggleFullscreen(); break;
    case 'queueToggle': S.queueOpen = !S.queueOpen; render(); break;
    case 'jump': jumpTo(Number(t.dataset.i)); break;

    case 'setmode': setMode(v); break;
    case 'dpad': webKey(t.dataset.k); break;
    case 'tabdis':
      phoneToast('Browse is Player-only — opening a PC file switches the PC back anyway');
      break;
    case 'focus': S.focus = !S.focus; render(); break;
    case 'tab': S.tab = v; render(); break;
    case 'gotab': S.tab = v; render(); break;
    case 'sheet': S.sheet = true; S.sheetMode = 'pair'; S.connectErr = ''; render(); break;
    case 'closesheet': if (!stop) { S.sheet = false; render(); } break;
    case 'sheetmode': S.sheetMode = v; S.connectErr = ''; render(); break;
    case 'pair': if (S.remoteOn) pairPhone(); break;
    case 'trycode': {
      const input = $('codein');
      const given = (input.value || '').replace(/[\s-]/g, '').toUpperCase();
      if (given === S.code) pairPhone();
      else { S.connectErr = 'That pairing code is not valid.'; logMsg('in', { type: 'error', code: 'bad_code' }); render(); }
      break;
    }

    case 'bseg': S.browseSeg = v; render(); break;
    case 'tseg': S.tuneSeg = v; render(); break;
    case 'cd': {
      const n = t.dataset.n;
      S.path = /^[A-Z]:$/.test(n) ? n : (S.path.length <= 2 ? S.path + n : S.path + '\\' + n);
      if (!FS[S.path]) S.path = n;
      S.page = 0;
      cmd('fs_list', { path: S.path });
      render();
      break;
    }
    case 'place': S.path = t.dataset.n; S.page = 0; cmd('fs_list', { path: S.path }); render(); break;
    case 'crumb': {
      const i = Number(t.dataset.i);
      const parts = S.path.split('\\').filter(Boolean);
      S.path = parts.slice(0, i + 1).join('\\');
      S.page = 0;
      render();
      break;
    }
    case 'up': {
      const parts = S.path.split('\\').filter(Boolean);
      parts.pop();
      S.path = parts.join('\\') || 'C:';
      S.page = 0;
      render();
      break;
    }
    case 'more': S.page++; render(); break;
    case 'filter': S.filterOn = !S.filterOn; render(); break;
    case 'fplay': playPath(t.dataset.n); break;
    case 'fqueue': queuePath(t.dataset.n); break;
    case 'stream': playUrl(t.dataset.u); break;
    case 'addurl': playUrl('https://www.youtube.com/watch?v=dune-trailer'); break;
    case 'openurl': playUrl('https://www.youtube.com/watch?v=dune-trailer'); break;

    case 'preset': {
      S.preset = v;
      S.bands = v === 'Flat' || v === 'My'
        ? [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        : S.bands.map((_, i) => Math.round(6 * Math.sin(i / 1.6 + v.length)));
      cmd('eq_preset', { key: v.toLowerCase() });
      render();
      break;
    }
    case 'eqreset': S.bands = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]; S.preset = 'Flat'; cmd('eq_preset', { key: 'flat' }); render(); break;
    case 'autoeq': S.autoEq = !S.autoEq; cmd('auto_eq_set', { on: S.autoEq }); render(); break;
    case 'speed': S.speed = v; cmd('speed_set', { key: 'x' + v.replace('×', '').replace('.', '_') }); osd(`Speed · ${v}`); render(); break;
    case 'subtrack':
      S.subTracks.forEach((x, i) => { x.on = i === Number(t.dataset.i); });
      cmd('select_sub_track', { index: Number(t.dataset.i) });
      render();
      break;
    case 'subsync': S.subDelay = Math.round((S.subDelay + Number(t.dataset.d)) * 10) / 10; cmd('sub_delay_set', { seconds: S.subDelay }); render(); break;
    case 'subreset': S.subDelay = 0; cmd('sub_delay_set', { seconds: 0 }); render(); break;
    case 'subsearch': S.busy = true; render(); cmd('subs_search', { title: S.title, language: 'eng' });
      setTimeout(() => { S.busy = false; logMsg('in', { type: 'subs_results', count: 12 }); render(); }, 900);
      break;
    case 'subfile': S.tab = 'browse'; S.browseSeg = 'files'; render(); break;
    case 'autodl': S.autoDownload = !S.autoDownload; cmd('subs_auto_set', { on: S.autoDownload }); render(); break;
    case 'audiotrack':
      S.audioTracks.forEach((x, i) => { x.on = i === Number(t.dataset.i); });
      cmd('select_audio_track', { index: Number(t.dataset.i) });
      render();
      break;
  }
});

// right-click on the picture opens the strip
$('canvas').addEventListener('contextmenu', (e) => {
  if (e.target.closest('.strip') || e.target.closest('.barrier')) return;
  e.preventDefault();
  const r = $('canvas').getBoundingClientRect();
  S.menu = { x: e.clientX - r.left, y: e.clientY - r.top };
  S.remotePanel = false;
  render();
});

// ── dragging (seek + volume + EQ bands) ──────────────────────────────────
function drag(el, onMove) {
  const rect = el.getBoundingClientRect();
  const step = (ev) => onMove(clamp((ev.clientX - rect.left) / rect.width, 0, 1));
  step(event0);
  const move = (ev) => step(ev);
  const up = () => {
    window.removeEventListener('pointermove', move);
    window.removeEventListener('pointerup', up);
    el.classList.remove('seeking');
    render();
  };
  window.addEventListener('pointermove', move);
  window.addEventListener('pointerup', up);
}
let event0 = null;
document.addEventListener('pointerdown', (e) => {
  const seek = e.target.closest('[data-seek]');
  const vol = e.target.closest('[data-vol]');
  const band = e.target.closest('[data-band]');
  const track = e.target.closest('#pcTrack');
  if (seek) {
    e.preventDefault();
    event0 = e;
    seek.classList.add('seeking');
    const web = seek.dataset.seek === 'web';
    drag(seek, (f) => {
      if (web) { S.web.position = f * S.web.duration; S.position = f * S.duration; }
      else S.position = f * S.duration;
      renderOsc(); renderPhone();
    });
    setTimeout(() => cmd(web ? 'web_media_seek' : 'seek_to',
      { position: Math.round(web ? S.web.position : S.position) }), 0);
  } else if (vol) {
    e.preventDefault();
    event0 = e;
    drag(vol, (f) => {
      if (vol.dataset.vol === 'web') { S.web.volume = Math.round(f * 100); }
      else { S.volume = Math.round(f * 100); }
      renderOsc(); renderPhone();
    });
    setTimeout(() => cmd(vol.dataset.vol === 'web' ? 'web_media_volume' : 'volume_set',
      { volume: vol.dataset.vol === 'web' ? S.web.volume : S.volume }), 0);
  } else if (band) {
    e.preventDefault();
    const i = Number(band.dataset.band);
    const rect = band.getBoundingClientRect();
    const set = (ev) => {
      const f = clamp(1 - (ev.clientY - rect.top) / rect.height, 0, 1);
      S.bands[i] = Math.round(f * 24 - 12);
      S.preset = 'My';
      renderPhone();
    };
    set(e);
    const move = (ev) => set(ev);
    const up = () => {
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', up);
      cmd('eq_set', { gains: S.bands.slice() });
    };
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', up);
  } else if (track) {
    e.preventDefault();
    event0 = e;
    track.classList.add('seeking');
    drag(track, (f) => { S.position = f * S.duration; renderOsc(); });
    setTimeout(() => cmd('seek_to', { position: Math.round(S.position) }), 0);
  }
});

// ── the clock ────────────────────────────────────────────────────────────
setInterval(() => {
  if (!S.hasMedia) return;
  if (S.mode === 'player' && S.playing) {
    S.position = Math.min(S.duration, S.position + 1000);
    renderOsc();
    if (S.tab !== 'play' || S.focus) renderPhone();
  } else if (S.mode === 'web' && S.webPlaying !== false) {
    S.web.position = Math.min(S.web.duration, S.web.position + 1000);
    renderOsc();
  }
}, 1000);

// ── toolbar ──────────────────────────────────────────────────────────────
$('btnReset').onclick = () => {
  Object.assign(S, {
    mode: 'player', playing: true, hasMedia: true, title: 'Big Buck Bunny',
    sub: 'Sintel · 1080p', position: 754000, volume: 80, muted: false,
    shuffle: false, repeat: 'off', fullscreen: false, index: 3,
    tab: 'play', focus: false, menu: null, remotePanel: false, sheet: true,
    sheetMode: 'pair', connectErr: '', path: 'D:\\Movies', page: 0,
    tuneSeg: 'eq', browseSeg: 'files', speed: '1×', preset: 'Flat',
    bands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0], subDelay: 0, webPlaying: true,
    remoteOn: true, fileAccess: true, status: 'running',
  });
  rotateCode();
  render();
};
$('btnForget').onclick = unpair;
document.addEventListener('keydown', (e) => {
  if (e.key !== 'Escape') return;
  if (S.remotePanel) closeRemotePanel();
  else if (S.sheet) { S.sheet = false; render(); }
  else if (S.menu) { S.menu = null; render(); }
});

// Read-only handle for the study checks, same shape as the IPTV preview's
// `saluStudy`. Nothing in the page depends on it.
window.saluRemote = { state: S, pairUri, encodeQr, marks: M, prettyCode };

// ── go ───────────────────────────────────────────────────────────────────
rotateCode();
logMsg('in', { type: 'hello', proto: 1, server: 'SALU', version: '0.1.0', name: S.pcName, auth: ['token', 'pair'] });
render();
