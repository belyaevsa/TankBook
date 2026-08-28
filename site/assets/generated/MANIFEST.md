# Generated imagery - manifest

Every generated image on this site is listed here with its recipe and date, per
`docs/SITE.md` → "Imagery: what may be generated, and what may never be".
Generated pixels are base layers only: no text, no product UI, no people, no
social proof, no watermarks. Everything that carries meaning (screenshots, copy)
is real and composited on top as HTML.

**Provenance note (2026-08-28, W3).** No model-based image generator was
available in the environment that produced these files. All three grounds below
are **procedural**: deterministic, seeded Python/numpy code writing gradient
fields, light pools, sheen bands, grain and vignettes from the Night Drive token
values in `design/tokens.json`. They carry no claim by construction (nothing but
computed light), the palette is exact rather than sampled-and-hoped, and a
re-run reproduces the file byte-for-byte. If a model-generated ground replaces
one of these later, keep the same filename, update this manifest, and have a
human open it at full size before it ships.

## Files

### `site/assets/og/og-base.png` - 2026-08-28

- 1200x630, RGB, seeded RNG `45201`.
- Prompt (procedural recipe): *night-forecourt ground for the OG card - midnight
  `#101318` sky shelf blending down to dash `#1A1F27` tarmac; a faint headlight
  `#4FC3E8` canopy glow high up; a headlight wash pooling low in the left third;
  a taillight `#F4503A` pool low in the right third; low ink sheen bands across
  the lower half like street light on wet tarmac; luma grain against banding;
  mild corner vignette.*
- Sampled dominant colours: `#1F2127` 15.9%, `#0E1318` 15.8%, `#141A20` 15.0%,
  `#1B1C22` 12.2%, `#13171C` 12.0% - all within 7/255 (max channel) of
  `midnight`/`dash`. Brightest pixel RGB(51,82,96), relative luminance 0.0758.
- The real screenshots (`P1.4-home.png` / `P1.4-home-ru.png` from
  `design/screenshots/`) are composited over this by
  `site/layouts/_partials/head/seo.html`. No text is baked in.

### `site/assets/generated/hero-ground.png` - 2026-08-28

- 1920x1080, RGB, seeded RNG `45202`. Referenced by
  `site/layouts/_partials/sections/hero.html` as a CSS background (never a raw
  `<img>`).
- Prompt (procedural recipe): the OG ground, dimmed for use behind live copy -
  same structure, lower pool intensities and grain.
- Sampled dominant colours: `#181B21` 16.8%, `#0F1318` 13.6%, `#14181D` 13.1%,
  `#1B2027` 12.6%, `#0D1116` 11.5% - all within 6/255 of `midnight`/`dash`.
- Contrast, measured over every pixel (worst case = brightest pixel in the
  image): ink `#EAEDF2` 10.81:1, inkSoft `#98A2B3` 4.92:1, taillight accent
  headline (large text floor 3:1) 3.66:1. All at or above AA.

### `site/assets/generated/check-ground.png` - 2026-08-28

- 1920x640, RGB, seeded RNG `45203`. Referenced by
  `site/layouts/_partials/sections/crosscheck.html` as a CSS background.
- Prompt (procedural recipe): *the dimmest ground - midnight-to-dash gradient,
  one low headlight shelf along the top edge, a faint taillight glow in the top
  right corner, a whisper of sheen at the bottom; nothing bright behind the
  arithmetic card.*
- Sampled dominant colours: `#14181E` 17.2%, `#10151B` 15.4%, `#12161B` 13.9%,
  `#191D24` 13.9%, `#151920` 13.8% - all within 7/255 of `midnight`/`dash`.
- Contrast, worst case over all pixels: ink 12.97:1, inkSoft 5.91:1. AA pass.

## Not generated, for the record

`site/static/icon.svg`, `site/static/apple-touch-icon.png` and
`site/static/favicon.ico` are hand-authored vectors (and raster renders of the
same geometry) following the app-icon spec in `docs/DESIGN.md`: taillight
fuel-nozzle silhouette whose hose draws a subtle checkmark, on midnight, no
text. They are drawn, not modelled - no prompt produced them.
