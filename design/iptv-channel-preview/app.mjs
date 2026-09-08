import { ChannelStudy, makeSample, channelIdentity } from './model.mjs';
import { icon, nowRow } from './marks.mjs';

const $ = id => document.getElementById(id);
const player = $('player'), panel = $('playlist-panel'), viewport = $('viewport');
const rows = $('list-rows'), listHeight = $('list-height'), listArea = $('list-area');
const search = $('search'), menu = $('group-menu'), shield = $('menu-shield');
const H = 38, PAD = 6, OVERSCAN = 4;
const STORAGE_KEY = 'salu-channel-study:favourites:preview-provider.invalid:v1';
let sample = new URLSearchParams(location.search).get('sample') || 'mixed';
if (!['mixed', 'partial', 'missing', 'large'].includes(sample)) sample = 'mixed';
let saved;
try {
  const value = JSON.parse(localStorage.getItem(STORAGE_KEY));
  if (Array.isArray(value) && value.every(v => typeof v === 'string')) saved = value;
} catch { /* A blocked storage area must not stop a design preview. */ }
const initial = makeSample(sample);
const state = new ChannelStudy(initial, saved ?? [initial[0], initial[9], initial[24]].filter(Boolean).map(channelIdentity));
let descriptors = [], panelOpen = true, chromeTimer, scrollTimer, persistTimer, toastTimer;
let tooltipTimer, activeTip, renderFrame, undoSnapshot = null, volumeBeforeMute = 62;
let scrollSuppressedUntil = 0;
const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
const sampleNames = { mixed: 'Mixed metadata', partial: 'Category only', missing: 'No grouping metadata', large: 'Large sample' };

for (const el of document.querySelectorAll('[data-icon]')) el.innerHTML = icon(el.dataset.icon);
// Pointer clicks on view/transport marks never steal keyboard focus.
document.addEventListener('pointerdown', event => {
  const button = event.target.closest('button');
  if (button) event.preventDefault();
  if (event.target.closest('#playlist-panel') && !event.target.closest('.search-field')) search.blur();
});

function setTip(el, tip) { el.dataset.tip = tip; el.setAttribute('aria-label', tip); }
function hideTooltip() { clearTimeout(tooltipTimer); $('tooltip').hidden = true; activeTip = null; }
document.addEventListener('pointerover', event => {
  const target = event.target.closest('[data-tip]');
  if (!target || target === activeTip) return;
  hideTooltip(); activeTip = target;
  tooltipTimer = setTimeout(() => {
    if (!target.isConnected) return;
    const rect = target.getBoundingClientRect();
    const tip = $('tooltip'); tip.textContent = target.dataset.tip; tip.hidden = false;
    const width = tip.offsetWidth;
    tip.style.left = `${Math.max(6, Math.min(innerWidth - width - 6, rect.left + (rect.width - width) / 2))}px`;
    tip.style.top = `${Math.min(innerHeight - tip.offsetHeight - 6, rect.bottom + 7)}px`;
  }, 550);
});
document.addEventListener('pointerout', event => {
  if (activeTip && !activeTip.contains(event.relatedTarget)) hideTooltip();
});
document.addEventListener('pointerdown', hideTooltip);

function wakeChrome() {
  player.classList.remove('chrome-hidden'); clearTimeout(chromeTimer);
  if (menu.hidden && !player.classList.contains('is-minimised') && !player.classList.contains('is-closed')) {
    chromeTimer = setTimeout(() => player.classList.add('chrome-hidden'), 3000);
  }
}
player.addEventListener('pointermove', wakeChrome);
player.addEventListener('focusin', wakeChrome);

function persist() {
  clearTimeout(persistTimer);
  persistTimer = setTimeout(flushFavourites, 500);
}
function flushFavourites() {
  clearTimeout(persistTimer);
  try { localStorage.setItem(STORAGE_KEY, JSON.stringify([...state.favourites])); } catch { /* Session still works. */ }
}
addEventListener('pagehide', flushFavourites);

function dismissToast() {
  clearTimeout(toastTimer); $('osd').hidden = true; $('osd').replaceChildren();
  undoSnapshot = null;
}
function toast(mark, label = '', { undo = null, duration = 1000 } = {}) {
  dismissToast();
  const deck = $('osd'); deck.innerHTML = icon(mark);
  if (label) { const text = document.createElement('span'); text.textContent = label; deck.append(text); }
  deck.classList.toggle('has-action', !!undo);
  if (undo) {
    undoSnapshot = undo;
    const button = document.createElement('button'); button.className = 'toast-action'; button.textContent = 'Undo';
    button.addEventListener('click', () => {
      const snapshot = undoSnapshot;
      dismissToast();
      if (snapshot) { state.restore(snapshot); search.value = state.query; sync({ top: true }); revealPlaying(false, true); }
    });
    deck.append(button);
  }
  deck.hidden = false;
  toastTimer = setTimeout(dismissToast, duration);
}

function groupNode(desc) {
  const button = document.createElement('button');
  button.type = 'button'; button.className = `group-head${desc.expanded ? ' is-expanded' : ''}${desc.unknown ? ' is-unknown' : ''}`;
  button.dataset.group = desc.key; button.setAttribute('aria-expanded', String(desc.expanded));
  const twist = document.createElement('span'); twist.className = 'group-chevron'; twist.innerHTML = icon('right');
  const name = document.createElement('span'); name.className = 'group-label'; name.textContent = desc.label;
  button.append(twist, name);
  if (!desc.expanded && desc.indexes.includes(state.current)) {
    const now = document.createElement('span'); now.className = 'row-chevron'; now.innerHTML = icon('play');
    now.setAttribute('aria-label', 'Playing channel in this group'); button.append(now);
  }
  button.addEventListener('click', () => toggleGroup(desc.key));
  return button;
}
function channelNode(desc) {
  const item = state.items[desc.index];
  const row = document.createElement('div'); row.className = `channel-row${state.current === desc.index ? ' is-playing' : ''}`;
  row.dataset.index = desc.index; row.setAttribute('role', 'listitem');
  if (state.current === desc.index) row.setAttribute('aria-current', 'true');
  const chevron = document.createElement('span'); chevron.className = 'row-chevron';
  if (state.current === desc.index) chevron.innerHTML = icon('play');
  const logo = document.createElement('span'); logo.className = 'logo-slot';
  if (item.logo) {
    const image = document.createElement('img');
    image.src = `assets/logos/${item.logo}.svg`; image.alt = ''; image.loading = 'lazy'; image.decoding = 'async'; image.draggable = false;
    image.addEventListener('error', () => image.remove(), { once: true }); logo.append(image);
  }
  const name = document.createElement('span'); name.className = 'channel-name'; name.textContent = item.name;
  name.dataset.tip = item.name;
  const favourite = document.createElement('button'); favourite.type = 'button'; favourite.className = 'icon-button row-favourite';
  const isFavourite = state.isFavourite(item);
  favourite.setAttribute('aria-pressed', String(isFavourite));
  setTip(favourite, isFavourite ? 'Remove favourite' : 'Add favourite');
  favourite.innerHTML = icon(isFavourite ? 'bookmarkFilled' : 'bookmark');
  favourite.addEventListener('click', event => {
    event.stopPropagation(); state.toggleFavourite(desc.index); persist(); sync();
  });
  row.append(chevron, logo, name, favourite);
  row.addEventListener('click', () => { search.blur(); state.select(desc.index); sync(); revealPlaying(true, true); });
  return row;
}
function renderRows() {
  renderFrame = null;
  const height = viewport.clientHeight;
  const scroll = viewport.scrollTop;
  const start = Math.max(0, Math.floor((scroll - PAD) / H) - OVERSCAN);
  const end = Math.min(descriptors.length, Math.ceil((scroll + height) / H) + OVERSCAN);
  const fragment = document.createDocumentFragment();
  for (let i = start; i < end; i++) {
    const desc = descriptors[i];
    const node = desc.type === 'group' ? groupNode(desc) : channelNode(desc);
    node.style.top = `${PAD + i * H}px`; fragment.append(node);
  }
  rows.replaceChildren(fragment);
  updateSticky(); updateEdges(); updateScrollbar();
}
function scheduleRows() {
  if (!renderFrame) renderFrame = requestAnimationFrame(renderRows);
}
function updateSticky() {
  const sticky = $('sticky-head'); sticky.hidden = true; sticky.replaceChildren();
  if (state.effectiveMode === 'flat') return;
  const first = Math.max(0, Math.floor((viewport.scrollTop - PAD) / H));
  const desc = descriptors[first];
  if (desc?.type !== 'channel' || !desc.groupKey) return;
  const group = descriptors.find(d => d.type === 'group' && d.key === desc.groupKey);
  if (!group) return;
  sticky.append(groupNode(group)); sticky.hidden = false;
}
function playingDescriptorIndex() {
  const direct = descriptors.findIndex(d => d.type === 'channel' && d.index === state.current);
  if (direct >= 0) return direct;
  // A filtered-out item is not revealed by changing/clearing the user's filter.
  if (state.query.trim() || (state.favouritesOnly && state.item && !state.isFavourite(state.item))) return -1;
  return descriptors.findIndex(d => d.type === 'group' && d.indexes.includes(state.current));
}
function updateEdges() {
  const index = playingDescriptorIndex();
  const top = PAD + index * H;
  const minTop = viewport.scrollTop + 6 + ($('sticky-head').hidden ? 0 : H);
  $('reveal-up').hidden = index < 0 || top >= minTop;
  $('reveal-down').hidden = index < 0 || top + H <= viewport.scrollTop + viewport.clientHeight - 6;
}
function updateScrollbar() {
  const max = viewport.scrollHeight - viewport.clientHeight;
  const bar = $('scrollbar'), thumb = $('scroll-thumb');
  bar.hidden = max <= 0;
  if (max <= 0) return;
  const track = Math.max(1, listArea.clientHeight - 10);
  const h = Math.max(24, track * viewport.clientHeight / viewport.scrollHeight);
  thumb.style.height = `${h}px`;
  thumb.style.top = `${(track - h) * viewport.scrollTop / max}px`;
}
function sync({ top = false } = {}) {
  descriptors = state.descriptors();
  listHeight.style.height = `${descriptors.length * H + PAD * 2}px`;
  if (top) viewport.scrollTop = 0;
  $('panel-header').hidden = !state.items.length;
  $('channel-title').textContent = state.title;
  $('channel-count').textContent = String(state.items.length);
  $('channel-count').setAttribute('aria-label', `${state.items.length} total channels`);
  $('search-clear').hidden = !state.query;
  $('group-by').classList.toggle('is-suspended', !!state.query.trim());
  $('favourites').setAttribute('aria-pressed', String(state.favouritesOnly));
  $('favourites').innerHTML = icon(state.favouritesOnly ? 'bookmarkFilled' : 'bookmark');
  const playLabel = state.transport === 'playing' ? 'Pause' : 'Play';
  setTip($('play'), playLabel); $('play').innerHTML = icon(state.transport === 'playing' ? 'pause' : 'play');
  $('play').disabled = !state.item;
  $('stop').disabled = !state.item || state.transport === 'stopped';
  $('previous').disabled = state.current <= 0;
  $('next').disabled = state.current < 0 || state.current >= state.items.length - 1;
  player.classList.toggle('is-stopped', state.transport === 'stopped');
  player.classList.toggle('is-paused', state.transport === 'paused');
  $('playlist-toggle').innerHTML = nowRow(state.current, state.items.length);
  const empty = $('empty-state'); empty.hidden = descriptors.length > 0;
  empty.innerHTML = !state.items.length ? nowRow(-1, 0) : icon(state.query.trim() ? 'search' : 'bookmark');
  empty.setAttribute('aria-label', !state.items.length ? 'Empty playlist' : state.query.trim() ? 'No matching channels' : 'No favourites');
  $('sample-label').textContent = sampleNames[sample];
  $('sample-description').textContent = 'Fictional channels · local artwork';
  for (const button of document.querySelectorAll('[data-sample]')) button.setAttribute('aria-pressed', String(button.dataset.sample === sample));
  updateMenu(); renderRows();
}
function toggleGroup(key) {
  const priorIndex = descriptors.findIndex(d => d.key === key);
  const offset = PAD + priorIndex * H - viewport.scrollTop;
  state.toggleGroup(key);
  descriptors = state.descriptors();
  listHeight.style.height = `${descriptors.length * H + PAD * 2}px`;
  const nextIndex = descriptors.findIndex(d => d.key === key);
  viewport.scrollTop = Math.max(0, PAD + nextIndex * H - offset);
  renderRows();
}
function revealPlaying(animate = true, force = false) {
  if (!panelOpen || !state.item || (!force && performance.now() < scrollSuppressedUntil)) return;
  const index = playingDescriptorIndex();
  if (index < 0) return;
  const top = PAD + index * H, bottom = top + H;
  const slack = 6 + ($('sticky-head').hidden ? 0 : H);
  let target = viewport.scrollTop;
  if (top < target + slack) target = Math.max(0, top - slack);
  else if (bottom > target + viewport.clientHeight - 6) target = bottom - viewport.clientHeight + 6;
  if (target !== viewport.scrollTop) viewport.scrollTo({ top: target, behavior: animate && !reduceMotion ? 'smooth' : 'instant' });
  scheduleRows();
}
function explicitReveal() {
  if (playingDescriptorIndex() < 0) return;
  if (state.effectiveMode !== 'flat') {
    state.openGroup = state.groupKey(state.item); sync();
  }
  revealPlaying(true, true);
}
$('reveal-up').addEventListener('click', explicitReveal);
$('reveal-down').addEventListener('click', explicitReveal);
viewport.addEventListener('scroll', () => {
  listArea.classList.add('is-scrolling');
  clearTimeout(scrollTimer); scrollTimer = setTimeout(() => listArea.classList.remove('is-scrolling'), 900);
  hideTooltip(); scheduleRows();
}, { passive: true });
viewport.addEventListener('wheel', () => { scrollSuppressedUntil = performance.now() + 3000; }, { passive: true });
viewport.addEventListener('touchmove', () => { scrollSuppressedUntil = performance.now() + 3000; }, { passive: true });
$('scroll-thumb').addEventListener('pointerdown', event => {
  event.preventDefault(); event.stopPropagation();
  const thumb = event.currentTarget, y = event.clientY, original = viewport.scrollTop;
  thumb.setPointerCapture(event.pointerId); $('scrollbar').classList.add('is-dragging');
  const move = e => {
    const track = listArea.clientHeight - 10 - thumb.clientHeight;
    if (track > 0) viewport.scrollTop = original + (e.clientY - y) * (viewport.scrollHeight - viewport.clientHeight) / track;
    scrollSuppressedUntil = performance.now() + 3000;
  };
  const done = () => {
    thumb.removeEventListener('pointermove', move); thumb.removeEventListener('pointerup', done);
    thumb.removeEventListener('pointercancel', done); $('scrollbar').classList.remove('is-dragging');
  };
  thumb.addEventListener('pointermove', move); thumb.addEventListener('pointerup', done); thumb.addEventListener('pointercancel', done);
});
new ResizeObserver(scheduleRows).observe(viewport);

function updateMenu() {
  const available = state.availability;
  for (const button of document.querySelectorAll('[data-mode]')) {
    button.disabled = !available[button.dataset.mode];
    button.setAttribute('aria-checked', String(state.mode === button.dataset.mode));
  }
}
function closeMenu() {
  menu.hidden = shield.hidden = true; $('group-by').setAttribute('aria-expanded', 'false'); hideTooltip(); wakeChrome();
}
function openMenu() {
  wakeChrome();
  search.blur(); updateMenu(); menu.hidden = shield.hidden = false;
  const rect = $('group-by').getBoundingClientRect();
  menu.style.left = `${Math.min(innerWidth - menu.offsetWidth - 8, rect.left - 3)}px`;
  menu.style.top = `${rect.bottom + 7}px`;
  $('group-by').setAttribute('aria-expanded', 'true'); clearTimeout(chromeTimer);
}
$('group-by').addEventListener('click', () => menu.hidden ? openMenu() : closeMenu());
shield.addEventListener('click', closeMenu);
for (const button of document.querySelectorAll('[data-mode]')) button.addEventListener('click', () => {
  if (state.setMode(button.dataset.mode)) { closeMenu(); sync({ top: true }); }
});

function setPanel(open) {
  panelOpen = open; player.classList.toggle('panel-hidden', !open);
  $('playlist-toggle').classList.toggle('is-active', open);
  $('playlist-toggle').setAttribute('aria-expanded', String(open));
  setTip($('playlist-toggle'), open ? 'Hide playlist' : 'Playlist');
  panel.inert = !open;
  if (!open) { search.blur(); closeMenu(); } else { sync(); revealPlaying(false, true); }
}
$('playlist-toggle').addEventListener('click', () => setPanel(!panelOpen));
$('panel-close').addEventListener('click', () => setPanel(false));
$('favourites').addEventListener('click', () => { state.favouritesOnly = !state.favouritesOnly; sync({ top: true }); });
search.addEventListener('input', () => { state.query = search.value; sync({ top: true }); });
$('search-clear').addEventListener('click', () => { search.value = state.query = ''; sync({ top: true }); search.focus(); });
$('clear-playlist').addEventListener('click', () => {
  const snapshot = state.clear(); search.value = ''; sync({ top: true });
  toast('trash', '', { undo: snapshot, duration: 5000 });
});
function step(delta) {
  if (!state.step(delta)) return;
  sync(); revealPlaying(true, true); toast(delta > 0 ? 'next' : 'previous', state.title);
}
$('next').addEventListener('click', () => step(1));
$('previous').addEventListener('click', () => step(-1));
function playPause() { state.togglePlay(); sync(); toast(state.transport === 'playing' ? 'play' : 'pause'); }
$('play').addEventListener('click', playPause);
$('video').addEventListener('click', () => {
  if (!player.classList.contains('is-closed')) playPause();
});
function stop() { if (!state.item) return; state.stop(); sync(); toast('stop'); }
$('stop').addEventListener('click', stop);
function setVolume(value) {
  const v = Math.max(0, Math.min(100, value)); $('volume').value = v;
  document.querySelector('.volume-wrap').style.setProperty('--volume', `${v}%`);
  $('volume-value').textContent = `${v}%`; $('mute').innerHTML = icon(v ? 'volume' : 'mute');
  setTip($('mute'), v ? 'Mute' : 'Unmute');
}
$('volume').addEventListener('input', e => setVolume(Number(e.target.value)));
$('volume').addEventListener('wheel', e => { e.preventDefault(); setVolume(Number($('volume').value) + (e.deltaY < 0 ? 5 : -5)); });
function mute() { const value = Number($('volume').value); if (value) volumeBeforeMute = value; setVolume(value ? 0 : volumeBeforeMute || 62); }
$('mute').addEventListener('click', mute);

function loadSample(kind = sample) {
  sample = kind; dismissToast(); closeMenu();
  state.load(makeSample(sample)); search.value = ''; sync({ top: true });
  player.classList.remove('is-closed', 'is-minimised'); $('reopen-preview').hidden = true;
  setPanel(true); wakeChrome();
  const url = new URL(location.href); url.searchParams.set('sample', kind); history.replaceState(null, '', url);
}
$('reload').addEventListener('click', () => loadSample());
for (const button of document.querySelectorAll('[data-sample]')) button.addEventListener('click', () => loadSample(button.dataset.sample));
$('minimise').addEventListener('click', () => { player.classList.toggle('is-minimised'); wakeChrome(); });
$('maximise').addEventListener('click', () => {
  player.classList.remove('is-minimised'); document.body.classList.toggle('maximised'); closeMenu(); wakeChrome(); scheduleRows();
});
$('window-close').addEventListener('click', () => {
  state.stop(); sync(); setPanel(false); player.classList.add('is-closed'); $('reopen-preview').hidden = false;
});
$('reopen-preview').addEventListener('click', () => { player.classList.remove('is-closed'); $('reopen-preview').hidden = true; setPanel(true); wakeChrome(); });

addEventListener('resize', () => { closeMenu(); scheduleRows(); });
document.addEventListener('keydown', event => {
  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'l') { event.preventDefault(); setPanel(!panelOpen); return; }
  if (event.key === 'Escape') {
    event.preventDefault();
    if (!menu.hidden) closeMenu();
    else if (document.activeElement === search) {
      if (search.value) { search.value = state.query = ''; sync({ top: true }); }
      else search.blur();
    } else if (panelOpen) setPanel(false);
    else dismissToast();
    return;
  }
  if (event.target instanceof HTMLInputElement) return;
  if (!menu.hidden) return;
  switch (event.key.toLowerCase()) {
    case ' ': event.preventDefault(); playPause(); break;
    case 'pageup': event.preventDefault(); step(-1); break;
    case 'pagedown': event.preventDefault(); step(1); break;
    case 's': event.preventDefault(); stop(); break;
    case 'm': event.preventDefault(); mute(); break;
    case 'arrowup': event.preventDefault(); setVolume(Number($('volume').value) + 5); break;
    case 'arrowdown': event.preventDefault(); setVolume(Number($('volume').value) - 5); break;
    case 'arrowleft': case 'arrowright': event.preventDefault(); break; // Live seek is silent.
    default: wakeChrome();
  }
});

// Inspection hook for the study tests. It exposes no real credentials or live streams.
window.saluStudy = { state, sync, loadSample, revealPlaying, get descriptors() { return descriptors; } };
sync({ top: true }); wakeChrome();
