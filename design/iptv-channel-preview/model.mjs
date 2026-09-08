// Approved points 5/6 interaction reference (2026-09-08), NOT the production Dart parser.
export const MODES = ['flat', 'category', 'language', 'country'];
const FIELD = { category: 'group', language: 'language', country: 'country' };
const countries = new Map([
  ['uk', 'United Kingdom'], ['gb', 'United Kingdom'], ['united kingdom', 'United Kingdom'],
  ['us', 'United States'], ['usa', 'United States'], ['united states', 'United States'],
  ['bd', 'Bangladesh'], ['bangladesh', 'Bangladesh'], ['jp', 'Japan'], ['japan', 'Japan'],
  ['fr', 'France'], ['france', 'France'], ['es', 'Spain'], ['spain', 'Spain'],
  ['de', 'Germany'], ['germany', 'Germany'], ['ca', 'Canada'], ['canada', 'Canada'],
]);
const languages = new Map([
  ['en', 'English'], ['eng', 'English'], ['english', 'English'],
  ['bn', 'Bangla'], ['ben', 'Bangla'], ['bengali', 'Bangla'], ['bangla', 'Bangla'],
  ['ja', 'Japanese'], ['jpn', 'Japanese'], ['japanese', 'Japanese'],
  ['es', 'Spanish'], ['spa', 'Spanish'], ['spanish', 'Spanish'],
  ['fr', 'French'], ['fra', 'French'], ['french', 'French'],
  ['de', 'German'], ['deu', 'German'], ['german', 'German'],
]);
const clean = value => typeof value === 'string' && value.trim() ? value.trim() : null;
const normalise = (value, aliases) => {
  const s = clean(value);
  // A compound field stays one provider-supplied value, never split into groups.
  return s === null ? null : aliases.get(s.toLowerCase()) ?? s;
};
export const channelIdentity = item => item.tvgId || item.tvgName || item.name;

export function prepareItems(raw) {
  const pool = new Map();
  const intern = value => {
    if (value === null) return null;
    if (!pool.has(value)) pool.set(value, value);
    return pool.get(value);
  };
  return Object.freeze(raw.map((item, index) => {
    const name = clean(item.name) || clean(item.tvgName) || clean(item.tvgId) || 'Unknown';
    // FINAL with point 5 (2026-09-08): same-file #EXTGRP fallback; group-title wins.
    const group = intern(clean(item.group) || clean(item.extgrp));
    return Object.freeze({
      url: item.url || `https://preview-provider.invalid/channel/${index}`,
      tvgId: clean(item.tvgId), tvgName: clean(item.tvgName), name, group,
      language: intern(normalise(item.language, languages)),
      country: intern(normalise(item.country, countries)),
      logo: item.logo ?? null,
      groupSource: clean(item.group) ? 'group-title' : clean(item.extgrp) ? 'EXTGRP' : null,
      searchKey: `${name} ${group ?? ''}`.toLowerCase(),
    });
  }));
}

const samples = [
  // Fictional channels and logo artwork; no actual IPTV service is contacted.
  ['Atlas Earth', 'Documentary', 'en', 'GB', 'atlas'],
  ['Wild North', 'Documentary', 'English', 'CA', 'wild'],
  ['Oceanic', 'Documentary', 'eng', 'UK', 'ocean'],
  ['Deep Space', 'Documentary', 'English', 'US', 'orbit'],
  ['The History Room', 'Documentary', 'en', 'United Kingdom', 'history'],
  ['Living Planet', 'Documentary', null, null, 'atlas'],
  ['Beyond Science', 'Documentary', 'English', 'US', 'orbit'],
  ['River Stories', 'Documentary', 'bn', 'BD', 'river'],
  ['Worldline', 'News', 'English', 'GB', 'world'],
  ['Dhaka Now', 'News', 'Bangla', 'BD', 'river'],
  ['North News', 'News', 'English', 'CA', 'north'],
  ['Morning Journal', 'News', 'fr', 'FR', 'journal'],
  ['Vista Noticias', 'News', 'es', 'ES', 'vista'],
  ['City Bulletin', 'News', 'en', 'US', 'world'],
  ['The Current', 'News', null, null, null],
  ['Tokyo Today', 'News', 'ja', 'JP', 'tokyo'],
  ['Lumière', 'Cinema', 'French', 'FR', 'lumiere'],
  ['Midnight Cinema', 'Cinema', 'English', 'US', 'midnight'],
  ['Frame Classics', 'Cinema', 'en', 'UK', 'frame'],
  ['Indie House', 'Cinema', 'English', 'US', 'frame'],
  ['Eastern Screen', 'Cinema', 'Japanese', 'JP', 'tokyo'],
  ['Matinée', 'Cinema', 'fr', 'FR', 'lumiere'],
  ['The Picture Room', 'Cinema', null, null, null],
  ['Bangla Cinema', 'Cinema', 'Bengali', 'Bangladesh', 'river'],
  ['Field Sports', 'Sport', 'en', 'GB', 'field'],
  ['Court One', 'Sport', 'English', 'US', 'court'],
  ['Trackside', 'Sport', 'German', 'DE', 'track'],
  ['The Climb', 'Sport', 'English', 'CA', 'wild'],
  ['Matchday', 'Sport', 'Spanish', 'ES', 'field'],
  ['Boundary', 'Sport', 'bn', 'BD', 'court'],
  ['Open Water', 'Sport', null, null, 'ocean'],
  ['Velocity', 'Sport', 'en', 'US', 'track'],
  ['Nocturne', 'Music', 'French', 'FR', 'nocturne'],
  ['Frequency', 'Music', 'en', 'GB', 'frequency'],
  ['Jazz Room', 'Music', 'English', 'US', 'nocturne'],
  ['Acoustic', 'Music', null, null, 'frequency'],
  ['Bangla Beats', 'Music', 'Bangla', 'BD', 'river'],
  ['Studio Sessions', 'Music', 'English', 'UK', 'frequency'],
  ['Canvas', 'Culture', 'en', 'GB', 'canvas'],
  ['Little Orbit', 'Family', 'English', 'US', 'orbit'],
  ['Story Garden', 'Family', 'Bangla', 'BD', 'wild'],
  ['Bright World', 'Family', 'Spanish', 'ES', 'world'],
  ['Artisan', null, 'French', 'FR', 'canvas'],
  ['Signal East', null, null, null, null],
  ['Horizon', null, 'English', null, 'atlas'],
  ['After Hours', null, null, null, 'midnight'],
  ['Studio Local', null, null, null, null],
  ['Open Window', null, null, null, 'frame'],
];

export function makeSample(kind = 'mixed') {
  const raw = samples.map(([name, group, language, country, logo], i) => ({
    name, group, language, country, logo,
    tvgId: i === 44 ? 'horizon.uk' : `salu-demo-${name.toLowerCase().replace(/[^a-z0-9]+/g, '-')}`,
    tvgName: name,
    // This category is present only in an alternative tag within the same fixture.
    extgrp: name === 'Artisan' ? 'Culture' : null,
  }));
  if (kind === 'partial') for (const item of raw) item.language = item.country = null;
  if (kind === 'missing') for (const item of raw) {
    item.group = item.extgrp = item.language = item.country = null;
  }
  if (kind === 'large') {
    const large = Array.from({ length: 50000 }, (_, i) => ({
      ...raw[i % raw.length], tvgId: `salu-demo-large-${i}`,
      // Repeated names intentionally test that ID, not the visible label, is identity.
    }));
    return prepareItems(large);
  }
  return prepareItems(raw);
}

export class ChannelStudy {
  constructor(items = makeSample(), favourites = []) {
    this.favourites = new Set(favourites);
    this.load(items);
  }
  load(items) {
    this.items = items;
    this.current = items.length ? 0 : -1;
    this.transport = items.length ? 'playing' : 'stopped';
    this.mode = 'flat'; // Owner's final default, never inferred from tag coverage.
    this.openGroup = null;
    this.query = '';
    this.favouritesOnly = false;
  }
  get item() { return this.items[this.current] ?? null; }
  get title() { return this.transport === 'stopped' ? 'SALU' : this.item?.name ?? 'SALU'; }
  get effectiveMode() { return this.query.trim() ? 'flat' : this.mode; }
  get availability() {
    const result = { flat: true, category: false, language: false, country: false };
    for (const item of this.items) {
      for (const mode of MODES.slice(1)) if (item[FIELD[mode]]) result[mode] = true;
      if (result.category && result.language && result.country) break;
    }
    return result;
  }
  isFavourite(item) { return this.favourites.has(channelIdentity(item)); }
  toggleFavourite(index) {
    const item = this.items[index];
    if (!item) return;
    const key = channelIdentity(item);
    if (this.favourites.has(key)) this.favourites.delete(key);
    else this.favourites.add(key);
  }
  groupKey(item, mode = this.mode) {
    return item && FIELD[mode] ? JSON.stringify([mode, item[FIELD[mode]]]) : null;
  }
  setMode(mode) {
    if (!MODES.includes(mode) || !this.availability[mode]) return false;
    this.mode = mode;
    this.openGroup = this.transport === 'stopped' ? null : this.groupKey(this.item);
    return true;
  }
  toggleGroup(key) { this.openGroup = this.openGroup === key ? null : key; }
  select(index, intent = 'manual') {
    if (index < 0 || index >= this.items.length) return false;
    const followedCurrent = this.openGroup === this.groupKey(this.item);
    this.current = index;
    this.transport = 'playing';
    if (!this.query.trim() && this.mode !== 'flat' && (intent === 'manual' || followedCurrent)) {
      this.openGroup = this.groupKey(this.item);
    }
    return true;
  }
  step(delta) { return this.select(this.current + delta); }
  stop() { this.transport = 'stopped'; this.openGroup = null; }
  togglePlay() {
    if (!this.item) return;
    if (this.transport === 'stopped') this.select(this.current);
    else this.transport = this.transport === 'playing' ? 'paused' : 'playing';
  }
  filteredIndexes() {
    const result = [];
    const q = this.query.trim().toLowerCase();
    for (let index = 0; index < this.items.length; index++) {
      const item = this.items[index];
      if (this.favouritesOnly && !this.isFavourite(item)) continue;
      if (q && !item.searchKey.includes(q)) continue;
      result.push(index);
    }
    return result;
  }
  groups(indexes = this.filteredIndexes()) {
    const mode = this.effectiveMode;
    if (mode === 'flat') return [];
    const grouped = new Map();
    for (const index of indexes) {
      const item = this.items[index];
      const value = item[FIELD[mode]];
      const key = this.groupKey(item, mode);
      if (!grouped.has(key)) grouped.set(key, { key, label: value ?? 'Unknown', unknown: value === null, indexes: [] });
      grouped.get(key).indexes.push(index);
    }
    const result = [...grouped.values()];
    const firstAppearance = new Map(result.map((g, i) => [g.key, i]));
    result.sort((a, b) => {
      if (a.unknown !== b.unknown) return a.unknown ? 1 : -1;
      return mode === 'category'
        ? firstAppearance.get(a.key) - firstAppearance.get(b.key)
        : a.label.localeCompare(b.label, 'en', { sensitivity: 'base' });
    });
    return result;
  }
  descriptors() {
    const indexes = this.filteredIndexes();
    if (this.effectiveMode === 'flat') return indexes.map(index => ({ type: 'channel', index, key: `item:${index}` }));
    const result = [];
    for (const group of this.groups(indexes)) {
      result.push({ type: 'group', ...group, expanded: this.openGroup === group.key });
      if (this.openGroup === group.key) {
        for (const index of group.indexes) result.push({ type: 'channel', index, key: `item:${index}`, groupKey: group.key });
      }
    }
    return result;
  }
  snapshot() {
    return {
      items: this.items, current: this.current, transport: this.transport,
      mode: this.mode, openGroup: this.openGroup, query: this.query,
      favouritesOnly: this.favouritesOnly,
    };
  }
  clear() {
    const snapshot = this.snapshot();
    this.load(Object.freeze([]));
    return snapshot;
  }
  restore(snapshot) { Object.assign(this, snapshot); }
}
