// Study checks for the Remote preview.
//
//   npm i jsdom        # outside the repo — SALU's pubspec stays untouched
//   node design/remote-preview/preview.test.mjs
//
// Loads the real index.html into a DOM and drives it: right-click, pairing,
// mode switching, browse-to-play, the EQ grid. It exercises the page's own
// handlers and render path — nothing here re-implements them. The QR assertion
// shells out to Python `qrcode` 8.2 and compares the modules the page actually
// drew, so a regression in the encoder shows up here too.

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const { JSDOM, VirtualConsole } = await import('jsdom');

const errors = [];
const vc = new VirtualConsole()
  .on('jsdomError', (e) => errors.push('jsdomError: ' + e.message))
  .on('error', (...a) => errors.push('console.error: ' + a.join(' ')))
  .on('warn', (...a) => errors.push('console.warn: ' + a.join(' ')));

// app.js is loaded over the wire the way a browser would (index.html carries
// the verified QR block inline and reaches for the app with <script src>).
const dom = new JSDOM(readFileSync(join(here, 'index.html'), 'utf8'), {
  runScripts: 'dangerously', resources: 'usable', pretendToBeVisual: true,
  url: pathToFileURL(join(here, 'index.html')).href, virtualConsole: vc,
});
const { window } = dom;
await new Promise((res, rej) => {
  window.addEventListener('load', res);
  setTimeout(() => rej(new Error('page never finished loading')), 8000);
});
assert.ok(window.saluRemote?.state, 'app.js did not load / did not install its handle');
const { document } = window;
window.addEventListener('error', (e) => errors.push('pageerror: ' + e.message));

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
const act = (name, root = document) => {
  const el = $(`[data-act="${name}"]`, root);
  assert.ok(el, `no element with data-act="${name}"`);
  return el;
};
const tap = (name, root = document) => act(name, root).click();
const tapValue = (name, value, root = document) => {
  const el = $$(`[data-act="${name}"]`, root).find((n) => n.dataset.v === value);
  assert.ok(el, `no ${name}="${value}"`);
  el.click();
};
const tab = (name) => tapValue('tab', name, $('#phone'));
const phoneMode = (m) => tapValue('setmode', m, $('#phone .phead'));   // the phone's own switch
const barMode = (m) => tapValue('setmode', m, $('#barMode'));          // the reviewer toolbar's
const dpadTap = (k) => {
  const el = $(`#phone .dpad [data-k="${k}"]`);
  assert.ok(el, `no D-pad key "${k}"`);
  el.click();
};
const openStrip = () => $('#canvas').dispatchEvent(
  new window.MouseEvent('contextmenu', { bubbles: true, cancelable: true, clientX: 300, clientY: 200 }));

let passed = 0, failed = 0;
async function check(label, fn) {
  try { await fn(); passed++; console.log(`PASS  ${label}`); }
  catch (e) { failed++; console.log(`FAIL  ${label}\n      ${String(e.message).split('\n')[0]}`); }
}

// ── the page loaded clean ────────────────────────────────────────────────
await check('page boots with no console output', async () => {
  assert.deepEqual(errors, [], errors.join(' | '));
  assert.ok(window.saluRemote?.state, 'window.saluRemote handle missing');
});
const S = window.saluRemote.state;

// ── initial state ────────────────────────────────────────────────────────
await check('phone opens on the Connect sheet, PC canvas in Player mode', async () => {
  assert.ok($('.sheet'), 'connect sheet not rendered');
  assert.match($('.sheet h3').textContent, /Connect to SALU/);
  assert.equal(S.mode, 'player');
  assert.equal(S.remoteOn, true);
  assert.equal(S.fileAccess, true);
  assert.match($('#osc').textContent, /12:34/, 'OSC clock not rendered: ' + $('#osc').textContent);
  assert.equal($('#pcTitle').textContent, 'Big Buck Bunny');
  assert.ok($('.settings .srow'), 'settings section did not render');
});

// ── the right-click strip: the QR seat ───────────────────────────────────
await check('right-click opens the 5-seat strip, Remote last', async () => {
  openStrip();
  const strip = $('.strip');
  assert.ok(strip, 'strip did not render');
  const acts = $$('.strip [data-act]').map((n) => n.dataset.act);
  assert.deepEqual(acts, ['shuffle', 'repeat', 'info', 'settings', 'remote'], acts.join(','));
  assert.equal(strip.style.width, '198px', 'remote.md §5.3: full-canvas strip is 198 with the QR seat');
  assert.equal($$('.strip .g').length, 1, 'the old Info|Settings gap should still appear once');
  assert.ok($('.strip .newseat'), 'Remote seat not annotated as new');
});

await check('the strip box model really adds up to 198 (remote.md §5.3)', async () => {
  const css = $('style').textContent;
  const px = (sel, prop) => {
    const m = css.match(new RegExp('\\' + sel + '\\{([^}]*)\\}'));
    assert.ok(m, `no CSS rule for ${sel}`);
    const v = m[1].match(new RegExp(prop + ':([^;}]+)'));
    assert.ok(v, `${sel} has no ${prop}`);
    return parseFloat(v[1]);
  };
  const button = px('.strip .icb', 'width');
  const gap = px('.strip .s', 'width');
  const divider = px('.strip .g', 'width');
  assert.equal(button, 30, '§5.3: _button renders a SaluIconButton(size: 30)');
  assert.equal(gap, 6, 'gaps are SizedBox(width: 6)');
  assert.equal(divider, 14, 'the Info/Settings divider is 14, not 6');

  // Count what the page actually rendered, then do §5.3's arithmetic on it.
  const kids = [...$('.strip').children];
  const seats = $$('.strip [data-act]').length;
  const gaps = kids.filter((k) => k.classList.contains('s')).length;
  const divs = kids.filter((k) => k.classList.contains('g')).length;
  assert.equal(seats, 5);
  assert.equal(gaps, 3, 'three 6 px gaps: shuffle|repeat, info|settings, settings|remote');
  assert.equal(divs, 1, 'one 14 px divider before the Info/Settings group');
  // `.strip` sets `padding:5px 7px` — the horizontal value is the second one.
  const pad = css.match(/\.strip\{[^}]*padding:([^;}]+)/)[1].trim().split(/\s+/);
  const padX = parseFloat(pad.length > 1 ? pad[1] : pad[0]);
  const chrome = 2 * (padX + 1);                            // 7 padding + 1 border, per side
  assert.equal(chrome, 16, 'capsule adds 7 padding + 1 border per side = 16');
  const total = seats * button + gaps * gap + divs * divider + chrome;
  assert.equal(total, 198, `30+6+30+14+30+6+30+6+30 + 16 should be 198, got ${total}`);
  assert.equal($('.strip').style.width, total + 'px', 'the rendered width must match the arithmetic');
});

await check('the strip closes before the Remote panel opens', async () => {
  tap('remote');
  assert.ok($('.modal'), 'Remote modal did not open');
  assert.equal($('.strip'), null, 'strip should have closed — one popup at a time');
  assert.match($('.modal h3').textContent, /^Remote$/);
});

// ── the QR is a real, decodable symbol ───────────────────────────────────
function pythonMatrix(uri, ec) {
  const out = execFileSync('python3', ['-c', `
import json, sys
import qrcode
from qrcode.util import QRData, MODE_8BIT_BYTE
q = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_${ec}, box_size=1, border=0)
q.add_data(QRData(sys.argv[1].encode(), mode=MODE_8BIT_BYTE))
q.make(fit=True)
print(json.dumps(q.get_matrix()))
`, uri], { encoding: 'utf8' });
  return JSON.parse(out.trim());
}

await check('the panel draws a QR identical to Python qrcode for the real payload', async () => {
  const uri = window.saluRemote.pairUri();
  assert.match(uri, /^salu:\/\/pair\?v=1&n=.+&h=.+&p=\d+&c=[A-Z0-9]{8}$/, uri);
  const svg = $('.qrcard svg');
  assert.ok(svg, 'QR card not rendered');
  assert.equal(svg.getAttribute('viewBox'), '0 0 208 208', 'QR must be 208 px (remote.md §10.2)');
  const rects = $$('g[fill="#000"] rect', svg);
  assert.ok(rects.length > 100, 'no dark modules drawn, got ' + rects.length);

  // Derive the geometry from the reference, then demand the drawn rects land on it.
  const ref = pythonMatrix(uri, 'M');
  const size = ref.length;
  const px = 208 / size;
  const drawn = Array.from({ length: size }, () => Array(size).fill(0));
  for (const r of rects) {
    const c = Math.round(parseFloat(r.getAttribute('x')) / px);
    const row = Math.round(parseFloat(r.getAttribute('y')) / px);
    assert.ok(c >= 0 && c < size && row >= 0 && row < size, `module outside the grid at ${row},${c}`);
    assert.ok(drawn[row][c] === 0, `duplicate module at ${row},${c}`);
    drawn[row][c] = 1;
  }
  const diffs = [];
  for (let r = 0; r < size; r++) for (let c = 0; c < size; c++)
    if (drawn[r][c] !== (ref[r][c] ? 1 : 0)) diffs.push(`${r},${c}`);
  assert.deepEqual(diffs, [], `${diffs.length} modules differ, first: ${diffs.slice(0, 5)}`);
  console.log(`      ${size}x${size} (version ${(size - 17) / 4}), ${drawn.flat().reduce((a, b) => a + b, 0)} dark modules, payload ${uri.length} chars`);
});

await check('the code under the QR is the code in the payload', async () => {
  assert.equal($('.modal .code').textContent.replace(/-/g, ''), S.code);
  assert.equal(S.code.length, 8);
});

await check('closing the panel rotates the code (A5)', async () => {
  const before = S.code;
  tap('closePanel');
  assert.equal($('.modal'), null, 'panel did not close');
  assert.notEqual(S.code, before, 'code did not rotate');
});

// ── pairing ──────────────────────────────────────────────────────────────
await check('pairing connects the phone and logs auth + a state snapshot', async () => {
  const from = S.log.length;
  tap('pair');
  assert.equal($('.sheet'), null, 'sheet should close on success');
  assert.equal(S.connected, true);
  assert.equal(S.controlName, 'Pixel 7');
  assert.match($('#phone .phead .nm').textContent, /Living Room PC/);
  assert.ok($('#phone .transport'), 'transport row did not render once connected');
  const kinds = S.log.slice(from).map((l) => JSON.parse(l.text).type);
  assert.ok(kinds.includes('auth'), 'no auth frame: ' + kinds.join(','));
  assert.ok(kinds.includes('state'), 'no state snapshot: ' + kinds.join(','));
});

// ── the two sides follow each other ──────────────────────────────────────
await check('both mode seats are visible, on the phone and in the toolbar', async () => {
  const seats = $$('#phone .phead .modeseg button').map((b) => b.dataset.v);
  assert.deepEqual(seats, ['player', 'web'], 'the phone must show both seats, not one toggling pill');
  assert.deepEqual($$('#barMode button').map((b) => b.dataset.v), ['player', 'web']);
  assert.ok($('#phone .phead .modeseg button[data-v="player"]').classList.contains('on'));
  assert.ok($('#barMode button[data-v="player"]').classList.contains('on'));
});

await check('the mode switch moves the PC canvas to Web mode', async () => {
  phoneMode('web');
  assert.equal(S.mode, 'web');
  assert.ok($('#canvas').classList.contains('web'), 'canvas did not switch');
  assert.match($('#pcMeta').textContent, /Web mode/);
  assert.ok($('#phone [data-act="webback"]'), 'web nav row missing on the phone');
  assert.equal($('#phone [data-act="prev"]'), null, 'mpv transport must disappear in Web mode');
});

await check('switching from the PC side moves the phone seat with it', async () => {
  phoneMode('web');
  barMode('player');
  assert.equal(S.mode, 'player');
  assert.ok($('#phone .phead .modeseg button[data-v="player"]').classList.contains('on'),
    'the phone switch must follow the PC');
  assert.ok($('#phone [data-act="prev"]'), 'transport did not come back');
  assert.equal($('#canvas').classList.contains('web'), false);
});

await check('Web mode takes Browse away and moves you off it', async () => {
  tab('browse');
  assert.equal(S.tab, 'browse');
  phoneMode('web');
  assert.notEqual(S.tab, 'browse', 'Web mode must leave the tab Browse can no longer serve');
  const browse = $$('#phone .tab').find((t) => t.textContent.trim() === 'browse');
  assert.ok(browse.classList.contains('dis'), 'Browse must read as disabled');
  assert.equal(browse.dataset.act, 'tabdis', 'a disabled tab must not route to the tab handler');
  browse.click();
  assert.notEqual(S.tab, 'browse', 'tapping it must not switch');
  assert.ok($('.ptoast'), 'it should say why, not fail silently');
  assert.match($('.ptoast').textContent, /Player-only/);
});

await check('a late transport command in Web mode also pulls it back (D8)', async () => {
  // The race D8 exists for: the PC has switched to Web mode but its snapshot
  // has not reached the phone yet, so the phone still shows Player controls.
  // The span below stands in for that stale button; the handler it reaches is
  // the page's own `togglePlay`.
  phoneMode('web');
  assert.equal(S.mode, 'web');
  const stale = document.createElement('span');
  stale.dataset.act = 'play';
  $('#phone').appendChild(stale);
  const from = S.log.length;
  stale.click();
  assert.equal(S.mode, 'player', 'D8: a transport command must pull SALU back to Player mode');
  const states = S.log.slice(from).map((l) => JSON.parse(l.text)).filter((m) => m.type === 'state');
  assert.equal(states.length, 1, 'exactly one snapshot should announce the switch, got ' + states.length);
  assert.equal(states[0].mode, 'player');
  stale.remove();
});

await check('mute raises no OSD card, play/pause does (A1)', async () => {
  const osd = $('#osd');
  osd.classList.remove('show');
  tap('mute');
  assert.equal(S.muted, true);
  assert.equal(osd.classList.contains('show'), false, 'OSD card shown for mute');
  tap('mute');
  assert.equal(S.muted, false);
  tap('play');
  assert.ok(osd.classList.contains('show'), 'no OSD card for play/pause');
  tap('play');
});

// ── browse ───────────────────────────────────────────────────────────────
await check('Browse lists the PC files and plays one without transferring it', async () => {
  tab('browse');
  assert.ok($('#phone .flist'), 'file list did not render');
  const row = $('#phone .frow[data-act="fplay"]');
  assert.ok(row, 'no playable media row');
  const name = row.dataset.n;
  const from = S.log.length;
  row.click();
  const sent = S.log.slice(from).map((l) => JSON.parse(l.text));
  const open = sent.find((m) => m.verb === 'fs_open');
  assert.ok(open, 'no fs_open command: ' + JSON.stringify(sent.map((m) => m.verb)));
  assert.deepEqual(Object.keys(open.args), ['path'], 'fs_open must send only a path');
  assert.ok(open.args.path.endsWith(name), 'the path must carry the whole file, not its bytes');
  assert.equal($('#pcTitle').textContent, name.replace(/\.[^.]+$/, ''), 'PC title did not follow');
  assert.equal(S.tab, 'play', 'playing a file should land on the Play tab');
});

await check('the mini bar appears while another tab is up', async () => {
  tab('tune');
  assert.ok($('#phone .mini'), 'mini bar missing');
  assert.match($('#phone .mini .tm').textContent, /^\d+:\d\d \/ \d+:\d\d$/);
  $('#phone .mini').click();
  assert.equal(S.tab, 'play');
});

await check('Streams tab mirrors the PC library with health dots', async () => {
  tab('browse');
  tapValue('bseg', 'streams', $('#phone'));
  assert.ok($('#phone [data-act="addurl"]'), 'Add a URL row missing');
  const rows = $$('#phone .srow2');
  assert.equal(rows.length, 3);
  assert.equal($$('#phone .srow2 .dot.dead').length, 1, 'the unreachable stream should carry a dead dot');
});

await check('turning off file access blanks the list, not the tab', async () => {
  tapValue('bseg', 'files', $('#phone'));
  assert.ok($('#phone .flist'), 'files list should be present while access is on');
  act('toggleFiles').click();
  assert.equal(S.fileAccess, false);
  assert.equal($('#phone .flist'), null, 'list still shown with access off');
  assert.match($('#phone .nothing').textContent, /turned off on the PC/);
  assert.ok($$('#phone .seg button').length === 2, 'the Files|Streams segment must survive');
  act('toggleFiles').click();
  assert.equal(S.fileAccess, true);
});

// ── tune ─────────────────────────────────────────────────────────────────
await check('Tune draws the EQ curve, ten bands and the PC speed stops', async () => {
  tab('tune');
  assert.equal($$('#phone .sliders .sl').length, 10, 'expected ten EQ bands');
  assert.ok($('#phone .curve polyline'), 'curve not drawn');
  assert.equal($$('#phone [data-act="speed"]').length, 7);
  tapValue('speed', '1.5×', $('#phone'));
  assert.equal(S.speed, '1.5×');
  assert.ok(S.log.some((l) => /"speed_set"/.test(l.text)), 'no speed_set frame');
});

await check('dragging a band moves it and marks the preset My', async () => {
  S.bands.fill(0);
  S.preset = 'Flat';
  const well = $('#phone [data-band="4"]');
  // jsdom has no layout, so the drag math needs explicit client coordinates.
  well.dispatchEvent(new window.MouseEvent('pointerdown', { bubbles: true, clientX: 100, clientY: 10 }));
  assert.equal(S.preset, 'My', 'preset should become My once a gain moves');
  assert.ok(Number.isFinite(S.bands[4]), 'gain is not a number: ' + S.bands[4]);
  window.dispatchEvent(new window.MouseEvent('pointerup'));
  assert.ok(S.log.some((l) => /"eq_set"/.test(l.text)), 'no eq_set frame');
  tap('eqreset', $('#phone'));
  assert.equal(S.preset, 'Flat');
  assert.deepEqual([...S.bands], [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);  // spread: S lives in the jsdom realm
});

await check('subtitles and audio segments switch and select', async () => {
  tapValue('tseg', 'subs', $('#phone'));
  assert.equal($$('#phone .track2').length, 3);
  assert.ok($('#phone [data-act="subsearch"]'), 'subtitle search row missing');
  act('subsync').click();
  assert.equal(S.subDelay, -0.5);
  tapValue('tseg', 'audio', $('#phone'));
  assert.equal($$('#phone .track2').length, 2);
  $$('#phone .track2')[1].click();
  assert.equal(S.audioTracks[1].on, true);
  assert.equal(S.audioTracks[0].on, false, 'audio tracks are exclusive');
});

await check('Tune explains itself when nothing is playing', async () => {
  S.hasMedia = false;
  tab('play');
  tap('stop');                        // goes through the real handler and re-renders
  tab('tune');
  assert.match($('#phone .nothing').textContent, /Nothing is playing/);
  assert.ok($('#phone [data-act="gotab"]'), 'it should offer a way to Browse');
  S.hasMedia = true;
  S.title = 'Big Buck Bunny';
  S.playing = true;
  tab('play');
});

// ── lifecycle ────────────────────────────────────────────────────────────
await check('in Web mode, Tune becomes a D-pad', async () => {
  phoneMode('web');
  tab('tune');
  assert.ok($('#phone .dpad'), 'no D-pad');
  assert.equal($$('#phone .dpad button').length, 5, 'up, back, OK, fwd, down');
  assert.equal($('#phone .dpad .ok').dataset.k, 'ok');
  assert.equal($$('#phone [data-act="tseg"]').length, 0,
    'EQ / Subs / Audio belong to mpv and must not be offered in Web mode');
  assert.ok($('#phone .focused'), 'it must say what is focused');
  assert.ok($('#webbody .frow'), 'the PC page must expose its focusables');
});

await check('the arrows walk the focus and the PC draws the ring where it lands', async () => {
  S.webFocus = 2;
  dpadTap('down');
  assert.equal(S.webFocus, 3);
  dpadTap('up');
  dpadTap('up');
  assert.equal(S.webFocus, 1, 'the walk must wrap at the top');
  const ring = $$('#webbody .frow.on');
  assert.equal(ring.length, 1, 'exactly one focus ring on the PC page');
  assert.match(ring[0].textContent, /Sign in/, 'the ring must sit on the focused element');
  assert.ok(S.log.some((l) => /"web_key"/.test(l.text)), 'no web_key frame logged');
});

await check('the side keys are history, reusing the verb the spec already has', async () => {
  const from = S.log.length;
  dpadTap('left');
  dpadTap('right');
  const navs = S.log.slice(from).map((l) => JSON.parse(l.text)).filter((m) => m.verb === 'browser_nav');
  // Spread: S.log is a jsdom-realm array, so its .map() result carries a
  // foreign Array prototype and deepStrictEqual rejects it on that alone.
  assert.deepEqual([...navs].map((n) => n.args.action), ['back', 'forward']);
});

await check('OK on the page player drives the page, never mpv', async () => {
  dpadTap('down');                                  // focus 1 -> the page's play button
  assert.match($('#phone .focused').textContent, /Play \/ pause the video/);
  const before = S.webPlaying;
  const from = S.log.length;
  dpadTap('ok');
  assert.equal(S.webPlaying, !before, 'the page player did not toggle');
  const verbs = S.log.slice(from).map((l) => JSON.parse(l.text)).map((m) => m.verb).filter(Boolean);
  assert.deepEqual([...verbs], ['web_media_toggle'], 'expected only web_media_toggle, got ' + verbs.join(','));
  assert.equal(S.playing, true, 'mpv must be untouched by a Web-mode key');
});

await check('web_key is a NEW verb — remote.md §17.4 does not define it yet', async () => {
  const spec = readFileSync(join(here, '..', '..', 'remote.md'), 'utf8');
  assert.ok(S.log.some((l) => /"web_key"/.test(l.text)), 'the preview should be sending it');
  assert.ok(!/`web_key`/.test(spec),
    'remote.md now documents web_key — retire this note and cite the section instead');
});

await check('back in Player mode, Tune is the equalizer again and Browse returns', async () => {
  phoneMode('player');
  tab('tune');
  assert.equal($$('#phone [data-act="tseg"]').length, 3, 'Equalizer / Subs / Audio must come back');
  assert.equal($('#phone .dpad'), null, 'the D-pad is Web-mode only');
  const browse = $$('#phone .tab').find((t) => t.textContent.trim() === 'browse');
  assert.equal(browse.classList.contains('dis'), false);
  assert.equal(browse.dataset.act, 'tab');
  tab('play');
});

await check('forgetting the only controlling phone drops the connection', async () => {
  openStrip();
  tap('remote');
  assert.equal($$('.modal .prow').length, 2);
  const controlling = $$('.modal .prow').find((r) => /has control/.test(r.textContent));
  assert.ok(controlling, 'no row marked has control');
  controlling.querySelector('[data-act="forget"]').click();
  assert.equal(S.connected, false);
  assert.equal(S.controlName, null);
  assert.ok($('.sheet'), 'phone should fall back to the Connect sheet');
  tap('closePanel');
});

await check('a wrong code is refused, the right one connects', async () => {
  tapValue('sheetmode', 'code', $('.sheet'));
  assert.ok($('#codein'), 'code entry did not render');
  $('#codein').value = 'ZZZZ-ZZZZ';
  tap('trycode');
  assert.equal(S.connected, false, 'a wrong code must not connect');
  assert.match($('.sheet .err').textContent, /not valid/);
  assert.ok(S.log.some((l) => /"bad_code"/.test(l.text)), 'no error frame logged');
  $('#codein').value = window.saluRemote.prettyCode();   // dashes must be tolerated
  tap('trycode');
  assert.equal(S.connected, true, 'the right code must connect');
  assert.equal($('.sheet'), null, 'sheet should close on success');
});

await check('turning Remote off tears it down on both sides (D10)', async () => {
  act('toggleRemote').click();
  assert.equal(S.remoteOn, false);
  assert.match($('#settings').textContent, /Show pairing code/);
  openStrip();
  tap('remote');
  assert.match($('.modal .statusline').textContent, /Remote is off/);
  assert.equal($('.qrcard'), null, 'no QR may be offered while remote is off');
  tap('closePanel');
  assert.match($('#phone .nothing').textContent, /Remote is off on the PC/);
  act('toggleRemote').click();
  assert.equal(S.remoteOn, true);
});

await check('the log stays a stream of full snapshots, never diffs (D5)', async () => {
  const states = S.log.filter((l) => l.dir === 'in')
    .map((l) => JSON.parse(l.text)).filter((m) => m.type === 'state');
  assert.ok(states.length >= 2, 'expected several state frames, got ' + states.length);
  for (const m of states) {
    assert.ok(m.playback && 'position' in m.playback && 'duration' in m.playback,
      'state is not a full snapshot: ' + JSON.stringify(m));
    assert.ok('rev' in m, 'state has no rev');
  }
  const revs = states.map((m) => m.rev);
  // Spread both sides: S.log is a jsdom-realm array, so its .map() result has
  // a foreign Array prototype and deepStrictEqual would reject it on that alone.
  const seen = [...revs];
  console.log(`      ${seen.length} snapshots, rev ${seen[0]} -> ${seen[seen.length - 1]}`);
  assert.deepEqual(seen, [...seen].sort((a, b) => a - b), 'rev must increase');
});

await check('no console output anywhere in the run', async () => {
  assert.deepEqual(errors, [], errors.join(' | '));
});

console.log(`\n${passed} passed, ${failed} failed`);
dom.window.close();
process.exit(failed ? 1 : 0);
