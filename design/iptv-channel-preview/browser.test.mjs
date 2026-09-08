// Optional end-to-end study checks. Requires Playwright + an installed Chromium.
// See README.md. No browser/tool dependencies are added to SALU's pubspec.
import assert from 'node:assert/strict';
import fs from 'node:fs';
const { chromium } = await import(process.env.SALU_PLAYWRIGHT_MODULE || 'playwright');
const browser = await chromium.launch({
  headless: true,
  ...(process.env.SALU_CHROMIUM_EXECUTABLE ? { executablePath: process.env.SALU_CHROMIUM_EXECUTABLE } : {}),
  args: ['--no-sandbox', '--disable-dev-shm-usage', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'],
});
const base = process.env.SALU_PREVIEW_URL || 'http://127.0.0.1:8123';
const page = await browser.newPage({ viewport: { width: 1360, height: 900 } });
page.setDefaultTimeout(12000);
const errors = [], failures = [], external = [];
page.on('pageerror', error => errors.push(error.message));
page.on('requestfailed', request => failures.push(request.url()));
page.on('request', request => { if (new URL(request.url()).origin !== new URL(base).origin) external.push(request.url()); });
async function check(label, fn) { await fn(); console.log(`PASS ${label}`); }
async function read(fn) { return page.evaluate(fn); }
async function mode(name) { await page.locator('#group-by').click(); await page.locator(`[data-mode="${name}"]`).click(); }
async function screenshot(name) {
  if (!process.env.SALU_SCREENSHOT_DIR) return;
  fs.mkdirSync(process.env.SALU_SCREENSHOT_DIR, { recursive: true });
  if (await page.locator('#group-menu').isVisible()) await page.locator('#group-menu').hover();
  else await page.locator('#playlist-panel').hover();
  await page.screenshot({ path: `${process.env.SALU_SCREENSHOT_DIR}/${name}.png`, fullPage: true, animations: 'disabled', timeout: 45000 });
}
try {
  await page.goto(`${base}/?sample=mixed`, { waitUntil: 'networkidle' });
  await check('Flat default, correct total, virtual rows, original geometry', async () => {
    assert.equal(await read(() => saluStudy.state.mode), 'flat');
    assert.equal(await page.locator('#channel-count').textContent(), '48');
    assert.ok(await page.locator('.channel-row').count() < 48);
    const box = await page.locator('#playlist-panel').boundingBox();
    const window = await page.locator('#player').boundingBox();
    assert.equal(box.width, 322); assert.equal(box.y - window.y, 148);
  });
  await screenshot('flat');
  await check('Group pill, one open accordion and Unknown last', async () => {
    await page.locator('#group-by').click();
    assert.equal(await page.locator('[data-mode="flat"]').getAttribute('aria-checked'), 'true');
    await page.locator('[data-mode="category"]').click();
    assert.equal(await read(() => saluStudy.state.mode), 'category');
    assert.equal(await read(() => saluStudy.descriptors.filter(d => d.type === 'group' && d.expanded).length), 1);
    assert.equal(await read(() => saluStudy.state.groups().at(-1).label), 'Unknown');
    await page.getByRole('button', { name: 'Cinema', exact: true }).click();
    assert.equal(await read(() => saluStudy.descriptors.find(d => d.type === 'group' && d.expanded).label), 'Cinema');
    assert.equal(await read(() => saluStudy.state.current), 0);
  });
  await screenshot('category');
  await check('Favourite toggles independently and survives persistence debounce', async () => {
    const row = page.locator('.channel-row[data-index="16"]');
    await row.hover(); await row.locator('.row-favourite').click();
    assert.equal(await read(() => saluStudy.state.current), 0);
    await page.waitForFunction(() => JSON.parse(localStorage.getItem('salu-channel-study:favourites:preview-provider.invalid:v1') || '[]').includes(saluStudy.state.items[16].tvgId));
    await page.locator('#favourites').click();
    assert.equal(await read(() => saluStudy.state.effectiveMode), 'category');
    assert.equal(await page.locator('#channel-count').textContent(), '48');
    assert.ok(await page.locator('.group-head').count() > 0);
  });
  await screenshot('favourites');
  await check('Search flattens without changing grouping/count and never searches URLs', async () => {
    await page.locator('#search').fill('Dhaka');
    assert.equal(await read(() => saluStudy.state.mode), 'category');
    assert.equal(await read(() => saluStudy.state.effectiveMode), 'flat');
    assert.equal(await page.locator('.channel-row').count(), 1);
    assert.equal(await page.locator('.channel-name').textContent(), 'Dhaka Now');
    assert.equal(await page.locator('#channel-count').textContent(), '48');
    await page.locator('#search').fill('preview-provider.invalid');
    assert.equal(await page.locator('.channel-row').count(), 0);
    assert.equal(await page.locator('#empty-state').isVisible(), true);
    await page.keyboard.press('Escape');
    assert.equal(await page.locator('#search').inputValue(), '');
    assert.equal(await read(() => document.activeElement.id), 'search');
    await page.keyboard.press('Escape');
    assert.notEqual(await read(() => document.activeElement.id), 'search');
    await page.keyboard.press('Escape');
    assert.equal(await read(() => document.getElementById('playlist-panel').inert), true);
    await page.keyboard.press('Control+l');
    assert.equal(await read(() => document.getElementById('playlist-panel').inert), false);
  });
  await check('Next ignores filtered/grouped order; Stop parks and Play resumes', async () => {
    await page.locator('#favourites').click();
    await page.locator('#next').hover(); await page.locator('#next').click();
    assert.equal(await read(() => saluStudy.state.current), 1);
    assert.equal(await page.locator('#channel-title').textContent(), 'Wild North');
    await page.locator('#stop').click();
    assert.equal(await page.locator('#channel-title').textContent(), 'SALU');
    assert.equal(await read(() => saluStudy.state.current), 1);
    assert.equal(await page.locator('#channel-count').textContent(), '48');
    assert.equal(await read(() => saluStudy.state.openGroup), null);
    await page.locator('#play').click();
    assert.equal(await page.locator('#channel-title').textContent(), 'Wild North');
  });
  await check('Off-screen playing channel is revealed at the nearest edge', async () => {
    await mode('flat');
    await page.locator('#viewport').evaluate(el => { el.scrollTop = el.scrollHeight; });
    await page.locator('#reveal-up').waitFor({ state: 'visible' });
    await page.locator('#reveal-up').click();
    await page.waitForFunction(() => document.getElementById('viewport').scrollTop < 100);
    assert.equal(await read(() => saluStudy.state.current), 1);
  });
  await check('Missing-data fixture stays Flat; unavailable modes remain visible and dim', async () => {
    await page.locator('[data-sample="missing"]').click();
    assert.equal(await read(() => saluStudy.state.mode), 'flat');
    await page.locator('#group-by').click();
    for (const m of ['category','language','country']) assert.equal(await page.locator(`[data-mode="${m}"]`).isDisabled(), true);
    assert.equal(await page.locator('[data-mode]').count(), 4);
  });
  await screenshot('no-metadata');
  await page.keyboard.press('Escape');
  await check('Category-only fixture enables only Category and Flat', async () => {
    await page.locator('[data-sample="partial"]').click();
    await page.locator('#group-by').click();
    assert.equal(await page.locator('[data-mode="category"]').isDisabled(), false);
    assert.equal(await page.locator('[data-mode="language"]').isDisabled(), true);
    assert.equal(await page.locator('[data-mode="country"]').isDisabled(), true);
    await page.locator('[data-mode="category"]').click();
  });
  await check('Clear + five-second Undo restores the in-memory list', async () => {
    await page.locator('#clear-playlist').click();
    assert.equal(await read(() => saluStudy.state.items.length), 0);
    assert.equal(await page.locator('#panel-header').isVisible(), false);
    await page.getByRole('button', { name: 'Undo', exact: true }).click();
    assert.equal(await read(() => saluStudy.state.items.length), 48);
  });
  await check('Favourites survive browser reload, but grouping returns to Flat', async () => {
    await page.reload({ waitUntil: 'networkidle' });
    assert.equal(await read(() => saluStudy.state.mode), 'flat');
    assert.equal(await read(() => saluStudy.state.isFavourite(saluStudy.state.items[16])), true);
  });
  await check('50,000 rows keep the DOM proportional to the viewport', async () => {
    await page.evaluate(() => saluStudy.loadSample('large'));
    assert.equal(await page.locator('#channel-count').textContent(), '50000');
    assert.ok(await page.locator('.channel-row').count() < 50);
    await page.locator('#viewport').evaluate(el => { el.scrollTop = el.scrollHeight; });
    // The viewport renders on requestAnimationFrame; observe the committed frame
    // instead of racing an isolated-world polling task after a document reload.
    await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
    assert.ok(await read(() => Number(document.querySelector('.channel-row')?.dataset.index) > 49000));
    assert.ok(await page.locator('.channel-row').count() < 50);
  });
  await check('Small viewport has no horizontal document overflow', async () => {
    await page.setViewportSize({ width: 390, height: 760 });
    assert.equal(await read(() => document.documentElement.scrollWidth <= innerWidth), true);
  });
  assert.deepEqual(errors, []); assert.deepEqual(failures, []); assert.deepEqual(external, []);
  console.log('PASS no page errors, failed requests or outside network lookups');
} finally { await browser.close(); }
