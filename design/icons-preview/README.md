# SALU · Icon family & colour concepts — design preview

Static, preview-only page. **No implementation** — nothing here is wired into
`lib/`.

Open with any static server, e.g.:

```
cd design/icons-preview && python3 -m http.server 8076 --bind 0.0.0.0
```

## What it shows

1. **New marks** — proposed SALU-family marks (thin monochrome stroke, round
   caps, ~8.5%-of-size weight, per `follow.md` rule 6) for every remaining
   stock `Icons.*` slot in the app: settings dialog theme/block/warning/eye/
   translate rows, `fullscreen_control`, `home_screen` playlist-add,
   `video_screen` play ring, etc.
2. **Reuse** — stock slots that should point at marks the family already owns
   (`CloseMark`, `CountryMark`, `PadlockMark`, `RestartMark`, `BroomMark`,
   `StackedFramesMark`, `DownloadMark`, `TickMark`, `RevealChevronMark`,
   `FilmFrameMark`).
3. **The recipe, live** — hover lights the mark gray → white and scales 1.06;
   press scales 0.90; nothing is ever drawn behind it.
4. **Colourful app-icon concepts** — the double-loop + play mark in four
   colourways: *Tide* (blue→teal + alive-green), *Dusk* (violet/magenta +
   blue/cyan), *Ember* (coral/amber), *Signal* (today's monochrome with accent
   terminals). Colours are drawn from `AppColors` where possible
   (`accent #4C9EEB`, `statusAlive #57C777`, `statusDead #E05B5B`).

Colour lives only in the app identity; UI marks stay monochrome
(`follow.md` rule 7 — the IPTV-artwork exception aside).

## concepts2.html — minimal app-icon directions

Six different geometries (not recolours): **Orbit** (ring + triangle + accent
dot), **Lens** (two thin rings, gradient vesica as play), **Punch** (negative-
space play in a lit disc), **Script** (monoline S with accent terminal),
**Frost** (current mark as Win11 mica glass), **Spectrum** (brand gradient as
a single open line). Includes small-size rows and a taskbar comparison strip.

## concepts3.html — main-icon directions (owner picked Frost + Punch)

- **Frost II · Aura** — frosted ring + bright refraction arc + shadowed play.
- **Frost III · Prism** — mica pane tile, play as 3-facet cut glass.
- **Punch II · Eclipse** — play-shaped hole glowing accent from behind.
- **Punch III · Slot-S** — S carved as negative channel, gradient light beneath.
- **S · Grotesk** — bold monoline S + accent terminal dot.
- **S · Counter-play** — S with accent play in the lower bowl.
- **Wave ring** — circular waveform ticks around a quiet play.
- **Beam** — four speed-lines forming an implied play silhouette.
