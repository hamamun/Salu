import test from 'node:test';
import assert from 'node:assert/strict';
import { ChannelStudy, makeSample, prepareItems, channelIdentity } from './model.mjs';

test('fresh load is Flat regardless of complete metadata or previous grouping', () => {
  const s = new ChannelStudy();
  assert.equal(s.mode, 'flat'); s.setMode('category'); s.load(makeSample());
  assert.equal(s.mode, 'flat'); assert.equal(s.openGroup, null);
});
test('only actual metadata enables grouping; ID suffix is not a country detector', () => {
  const s = new ChannelStudy(makeSample('missing'));
  assert.deepEqual(s.availability, { flat: true, category: false, country: false, language: false });
  assert.equal(s.setMode('country'), false);
  assert.equal(s.items.find(i => i.tvgId === 'horizon.uk').country, null);
});
test('partial data enables category without pretending language/country are known', () => {
  const s = new ChannelStudy(makeSample('partial'));
  assert.deepEqual(s.availability, { flat: true, category: true, country: false, language: false });
});
test('category order follows first appearance, and Unknown is last', () => {
  const s = new ChannelStudy(); s.setMode('category');
  assert.deepEqual(s.groups().map(g => g.label), ['Documentary','News','Cinema','Sport','Music','Culture','Family','Unknown']);
});
test('country aliases merge; remaining country groups sort alphabetically', () => {
  const s = new ChannelStudy(); s.setMode('country');
  const groups = s.groups();
  assert.equal(groups.filter(g => g.label === 'United Kingdom').length, 1);
  assert.equal(groups.at(-1).label, 'Unknown');
  const names = groups.slice(0,-1).map(g => g.label);
  assert.deepEqual(names, [...names].sort((a,b)=>a.localeCompare(b)));
});
test('language aliases merge and multi-value fields are never split', () => {
  const items = prepareItems([
    { name:'One', language:'en' }, { name:'Two', language:'English' },
    { name:'Three', language:'English;Spanish', group:'UK | News' },
  ]);
  const s = new ChannelStudy(items); s.setMode('language');
  assert.equal(s.groups().length, 2);
  assert.equal(items[2].group, 'UK | News');
});
test('approved same-file EXTGRP fallback is conservative; group-title wins', () => {
  const items = prepareItems([
    { name:'One', extgrp:'Culture' }, { name:'Two', group:'News', extgrp:'Culture' },
    { name:'BBC.uk', tvgId:'some-channel.gb' },
  ]);
  assert.equal(items[0].group, 'Culture'); assert.equal(items[0].groupSource, 'EXTGRP');
  assert.equal(items[1].group, 'News'); assert.equal(items[2].group, null); assert.equal(items[2].country, null);
});
test('ID takes precedence over names; absent metadata does not discard a channel', () => {
  const items = prepareItems([{ tvgId:'stable', tvgName:'Provider name', name:'Visible name' }, { tvgName:'Fallback' }, { url:'https://private.invalid/token' }]);
  assert.equal(channelIdentity(items[0]), 'stable');
  assert.equal(channelIdentity(items[1]), 'Fallback');
  assert.equal(items[2].name, 'Unknown');
  assert.equal(items.length, 3);
});
test('exactly one accordion group can be expanded; current group opens on manual choice', () => {
  const s = new ChannelStudy(); s.setMode('category');
  assert.equal(s.descriptors().filter(d => d.type === 'group' && d.expanded).length, 1);
  assert.equal(s.openGroup, s.groupKey(s.item));
  const nextGroup = s.groups()[1].key; s.toggleGroup(nextGroup);
  assert.equal(s.openGroup, nextGroup);
  assert.equal(s.descriptors().filter(d => d.type === 'group' && d.expanded).length, 1);
  s.toggleGroup(nextGroup); assert.equal(s.openGroup, null);
});
test('automatic advance cannot steal a group deliberately browsed by the viewer', () => {
  const s = new ChannelStudy(); s.setMode('category');
  const cinema = s.groups().find(g => g.label === 'Cinema').key;
  s.toggleGroup(cinema); s.select(1, 'automatic');
  assert.equal(s.openGroup, cinema);
});
test('manual Next is original-list order, not favourite/search/group order', () => {
  const s = new ChannelStudy(); s.toggleFavourite(0); s.toggleFavourite(24);
  s.favouritesOnly = true; s.query = 'field'; s.setMode('country');
  assert.equal(s.step(1), true); assert.equal(s.current, 1);
});
test('Previous always moves one channel; either end never wraps', () => {
  const s = new ChannelStudy(); assert.equal(s.step(-1), false);
  s.select(20); s.step(-1); assert.equal(s.current, 19);
  s.select(s.items.length-1); assert.equal(s.step(1), false);
});
test('favourite toggle does not select a channel or reorder the queue', () => {
  const s = new ChannelStudy(); const original = s.items;
  s.toggleFavourite(24); assert.equal(s.current, 0); assert.equal(s.items, original);
  assert.equal(s.isFavourite(s.items[24]), true);
});
test('favourites survive reload; favourites-only preserves grouping', () => {
  const s = new ChannelStudy(); s.toggleFavourite(0); s.toggleFavourite(24);
  s.setMode('category'); s.favouritesOnly = true;
  assert.equal(s.groups().length, 2); assert.equal(s.effectiveMode, 'category');
  s.load(makeSample()); assert.equal(s.isFavourite(s.items[24]), true); assert.equal(s.mode, 'flat');
});
test('search matches only names/groups, temporarily flattens, and restores grouping', () => {
  const s = new ChannelStudy(); s.setMode('category'); const open = s.openGroup;
  s.query = 'NEWS'; assert.equal(s.effectiveMode, 'flat'); assert.equal(s.filteredIndexes().length, 8);
  s.query = 'preview-provider.invalid'; assert.equal(s.filteredIndexes().length, 0);
  s.query = ''; assert.equal(s.mode, 'category'); assert.equal(s.openGroup, open);
});
test('filtering never changes total count or channel records', () => {
  const s = new ChannelStudy(); const original = s.items;
  s.query = 'oceanic'; assert.equal(s.filteredIndexes().length, 1);
  assert.equal(s.items.length, 48); assert.equal(s.items, original);
  s.favouritesOnly = true; assert.equal(s.items.length, 48);
});
test('Stop parks the same channel and queue; no accordion group is forced open', () => {
  const s = new ChannelStudy(); s.select(10); s.setMode('category');
  const original = s.items; s.stop();
  assert.equal(s.items, original); assert.equal(s.current, 10); assert.equal(s.title, 'SALU');
  assert.equal(s.openGroup, null); s.togglePlay(); assert.equal(s.current, 10); assert.equal(s.transport, 'playing');
});
test('Clear/Undo holds one immutable snapshot and preserves favourites', () => {
  const s = new ChannelStudy(); s.select(5); s.toggleFavourite(24); const original = s.items;
  const snapshot = s.clear(); assert.equal(s.items.length, 0); assert.equal(s.title, 'SALU');
  assert.equal(snapshot.items, original); s.restore(snapshot);
  assert.equal(s.items, original); assert.equal(s.current, 5); assert.equal(s.isFavourite(s.items[24]), true);
});
test('large fixture is 50,000 entries without a second copied channel-object list', () => {
  const items = makeSample('large'); const s = new ChannelStudy(items);
  assert.equal(s.items, items); assert.equal(s.items.length, 50000);
  s.setMode('country'); const descriptors = s.descriptors();
  assert.ok(descriptors.length < 50000);
  assert.ok(descriptors.filter(d => d.type === 'channel').every(d => typeof d.index === 'number' && !('url' in d)));
});
