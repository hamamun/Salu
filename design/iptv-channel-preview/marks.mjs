// Small hand-drawn monochrome marks, using SALU's rounded 1.7 px family stroke.
const drawings = {
  plus: '<path d="M12 5v14M5 12h14"/>',
  close: '<path d="m7 7 10 10M17 7 7 17"/>',
  minimise: '<path d="M6 12h12"/>',
  maximise: '<path d="M8 5H5v3m11-3h3v3M5 16v3h3m8 0h3v-3"/>',
  play: '<path d="m8 5 10 7-10 7Z" fill="currentColor"/>',
  pause: '<path d="M8 5v14M16 5v14" stroke-width="2.2"/>',
  stop: '<path d="M6 6h12v12H6Z"/>',
  previous: '<path d="M4 6v12m10-12-7 6 7 6m7-12-7 6 7 6"/>',
  next: '<path d="M20 6v12M10 6l7 6-7 6M3 6l7 6-7 6"/>',
  back: '<path d="m12 6-7 6 7 6m7-12-7 6 7 6"/>',
  forward: '<path d="m5 6 7 6-7 6m7-12 7 6-7 6"/>',
  volume: '<path d="M5 9h3l4-4v14l-4-4H5Zm10-1a6 6 0 0 1 0 8m3-11a10 10 0 0 1 0 14"/>',
  mute: '<path d="M5 9h3l4-4v14l-4-4H5Zm11 1 5 5m0-5-5 5"/>',
  group: '<path d="M5 4v14M5 7h5m-5 10h5M13 7h6m-6 10h4"/><circle cx="5" cy="4" r="1.4" fill="currentColor" stroke="none"/>',
  flat: '<path d="M4 6h16M4 12h11M4 18h14"/>',
  category: '<path d="M4 5h6m-6 14h6M7 5v14m0-7h8m0-5h5m-5 10h5m-5-10v10"/>',
  language: '<path d="M5 5h14a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2h-8l-5 4v-4H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2Z"/><path d="M7 9h10m-10 4h6" stroke-opacity=".6"/>',
  country: '<circle cx="12" cy="12" r="9"/><ellipse cx="12" cy="12" rx="4" ry="9"/><path d="M3 12h18"/>',
  bookmark: '<path d="M7 4h10v16l-5-3.5L7 20Z"/>',
  bookmarkFilled: '<path d="M7 4h10v16l-5-3.5L7 20Z" fill="currentColor"/>',
  search: '<circle cx="10.5" cy="10.5" r="6"/><path d="m15 15 5 5"/>',
  trash: '<path d="M5 7h14M9 4h6M7 7l1 13h8l1-13M10 10v7m4-7v7"/>',
  down: '<path d="m7 9 5 5 5-5"/>',
  up: '<path d="m7 15 5-5 5 5"/>',
  right: '<path d="m9 7 5 5-5 5"/>',
  reset: '<path d="M5 7a8 8 0 1 1-1 8M5 3v5h5"/>',
  dots: '<g fill="currentColor" stroke="none"><circle cx="7" cy="5" r="1.35"/><circle cx="17" cy="5" r="1.35"/><circle cx="7" cy="12" r="1.35"/><circle cx="17" cy="12" r="1.35"/><circle cx="7" cy="19" r="1.35"/><circle cx="17" cy="19" r="1.35"/></g>',
  partial: '<path d="M4 6h15M4 12h10M4 18h6"/><path d="M18 12h2m-6 6h6" stroke-opacity=".3"/>',
  missing: '<path d="M4 6h16M4 12h11M4 18h14" stroke-opacity=".3"/><path d="m17 11 4 4m0-4-4 4"/>',
};
export function icon(name, extra = '') {
  return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" ${extra}>${drawings[name] ?? drawings.flat}</svg>`;
}
export function nowRow(now = 0, count = 1) {
  const row = count > 0 && now >= 0 ? Math.min(2, Math.floor(now * 3 / count)) : -1;
  return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${[6.72, 12.48, 18.24].map((y, i) => i === row
    ? `<path d="m3.84 ${y - 1.92} 3.36 1.92-3.36 1.92Z" fill="currentColor"/><path d="M9.12 ${y}H${[20.64,16.32,18.72][i]}"/>`
    : `<path d="M3.84 ${y}H${[20.64,16.32,18.72][i]}" stroke-opacity=".55"/>`).join('')}</svg>`;
}
