# Generated imagery - manifest

Every generated image on this site is listed here with its recipe and date, per
`docs/SITE.md` → "Imagery: what may be generated, and what may never be".
Generated pixels are base layers only: no text, no product UI, no people, no
social proof, no watermarks. Everything that carries meaning (screenshots, copy)
is real and composited on top as HTML.

**Provenance note (2026-08-28, W3).** No model-based image generator was
available in the environment that produced these files. The OG ground below
is **procedural**: deterministic, seeded Python/numpy code writing gradient
fields, light pools, sheen bands, grain and vignettes from the Night Drive token
values in `design/tokens.json`. It carries no claim by construction (nothing but
computed light), the palette is exact rather than sampled-and-hoped, and a
re-run reproduces the file byte-for-byte. The section grounds were procedural
too until 2026-10-10, when model-generated night and day photos replaced them
(below); every replacement is listed here and opened by a human at full size
before it ships.

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

### The photo grounds, night and day - 2026-10-10

Model-generated (imagegen, Gemini `gemini-3-pro-image-preview`, `--no-brand --no-watermark
--style photo`, two variations each, one picked after a human opened both at full size; rejected:
a day hero with a hard vertical seam and a day canopy with a warped roof). Every scene exists
**twice**: `-night` for the dark site, `-day` for the light one, chosen by `prefers-color-scheme`
in `.section--photo` (`site/assets/css/sections.css`) through `site/layouts/_partials/ground.html`,
which fails the build if either rendition is missing. They replaced the procedural
`hero-ground.png` and `check-ground.png` (2026-08-28, in git history).

Every prompt ends with the same block: *Abstract atmospheric photograph used as a website background behind text. Strictly no text, no letters, no numbers, no signs, no logos, no watermark, no people, no recognisable car, no object in sharp focus. Everything soft, shallow depth of field, out-of-focus bokeh. The LEFT 55% of the frame is calm, smooth, nearly uniform tone with no detail (text will sit there); all light and interest sits in the RIGHT 40%. Photorealistic, minimal, premium automotive mood, fine film grain.*

The day renditions use their own prompt block (the DAY block): *Photograph used as a website background behind text. Natural daylight exposure with real mid-tones and contrast - NOT high key, NOT washed out, NOT foggy. The subject on the right is clearly recognisable but softly out of focus (gentle lens blur, like f/2.8 background). Strictly no text, no letters, no numbers, no signs, no logos, no brand colours, no watermark, no people. The LEFT 45% of the frame is calm and plain (pale sky, clean wall or smooth asphalt) so dark text can sit on it; the subject sits in the RIGHT half. Photorealistic, minimal, premium automotive advertising mood.*

Contrast is measured on the page's own composite - the image cropped as CSS crops it at 1440 px
wide, under the `.section--photo` wash - as the worst pixel in the left half, where the copy sits.
On a phone the wash is an even 86% tint, which is stronger everywhere.

#### `site/assets/generated/hero-night.png`

- 1376x768, RGB. Used by `site/layouts/_partials/sections/hero.html`.
- Prompt: *NIGHT. Wet asphalt after rain at night. On the right: out-of-focus red taillight bokeh (#F4503A) and a soft cool cyan street-light glow (#4FC3E8) reflecting on the wet ground. Left side almost black blue-grey (#101318).* + the common block.
- Sampled dominant colours: `#0E161E` 52%, `#3F4851` 17%, `#68A4B0` 16%.
- Contrast, worst case under the copy: ink 14.94:1, inkSoft 6.81:1, taillight 5.06:1. AA pass (inkSoft is body-size text, 4.5:1; the
  taillight accent is a large headline, 3:1).

#### `site/assets/generated/hero-day.png`

- 1376x768, RGB. Second round (2026-10-10): the first day set was high key and
  foggy, and the product owner could not make out a pump or anything else in it. This one uses
  the DAY block below instead of the common block: daylight mid-tones, a recognisable subject
  softly out of focus.
- Prompt: *DAY. A city street after light rain on a bright overcast day, one continuous photograph with no seams or panels. On the right third: a dark generic hatchback seen from a low rear three-quarter angle, softly out of focus, its red taillights on (#CE3422) reflecting in the wet asphalt. The car has NO badge, NO emblem, NO licence plate (the plate area is blank or hidden by blur). Buildings and trees softly blurred behind it.* + the DAY block.
- Sampled dominant colours: `#A5AAAD` 28%, `#33332F` 24%, `#747171` 23%.
- Contrast, worst case under the copy (the left 58%, under the light-mode wash): ink 12.72:1, inkSoft 4.96:1, taillight 3.94:1. AA pass.

#### `site/assets/generated/check-night.png`

- 1584x672, RGB. Used by `site/layouts/_partials/sections/crosscheck.html`.
- Prompt: *NIGHT. Very dark and quiet. A faint soft cyan glow (#4FC3E8) along the top right edge, like a distant canopy light, and a whisper of reflection on wet ground at the bottom right. Almost everything near-black blue-grey (#101318).* + the common block.
- Sampled dominant colours: `#0F191E` 35%, `#091215` 20%, `#080D11` 17%.
- Contrast, worst case under the copy: ink 15.55:1, inkSoft 7.09:1, taillight 5.26:1. AA pass (inkSoft is body-size text, 4.5:1; the
  taillight accent is a large headline, 3:1).

#### `site/assets/generated/check-day.png`

- 1584x672, RGB. Second round (2026-10-10): the first day set was high key and
  foggy, and the product owner could not make out a pump or anything else in it. This one uses
  the DAY block below instead of the common block: daylight mid-tones, a recognisable subject
  softly out of focus.
- Prompt: *DAY. A quiet road edge on a bright overcast day, wet asphalt with soft reflections; on the far right a softly blurred street lamp and roadside trees. Left side plain smooth pale asphalt and sky. Calm, low detail.* + the DAY block.
- Sampled dominant colours: `#C7CBD0` 25%, `#DEE3E8` 22%, `#6D6D61` 21%.
- Contrast, worst case under the copy (the left 58%, under the light-mode wash): ink 14.37:1, inkSoft 5.61:1, taillight 4.45:1. AA pass.

#### `site/assets/generated/pump-night.png`

- 1584x672, RGB. Used by `site/layouts/page.html` (banner of `pump-reading.md` / `pump-reading.ru.md`).
- Prompt: *NIGHT. Underside of a fuel-station canopy seen out of focus: soft rectangular white and cyan light panels (#4FC3E8) blurred into bokeh on the right, faint red reflection (#F4503A) on wet ground. Left side near-black blue-grey (#101318). No pump, no signage.* + the common block.
- Sampled dominant colours: `#0C1219` 36%, `#628996` 21%, `#162C37` 19%.
- Contrast, worst case under the copy: ink 14.90:1, inkSoft 6.79:1, taillight 5.04:1. AA pass (inkSoft is body-size text, 4.5:1; the
  taillight accent is a large headline, 3:1).

#### `site/assets/generated/pump-day.png`

- 1584x672, RGB. Second round (2026-10-10): the first day set was high key and
  foggy, and the product owner could not make out a pump or anything else in it. This one uses
  the DAY block below instead of the common block: daylight mid-tones, a recognisable subject
  softly out of focus.
- Prompt: *DAY. A modern, unbranded fuel station in daylight: a white canopy and two fuel pumps with hoses on an island, clearly recognisable but softly out of focus on the right, a dark car parked at one pump. Left side plain pale sky and clean concrete forecourt. No signage, no price board, no logos.* + the DAY block.
- Sampled dominant colours: `#DBDEDF` 27%, `#CBCECF` 21%, `#7E8184` 20%.
- Contrast, worst case under the copy (the left 58%, under the light-mode wash): ink 13.42:1, inkSoft 5.23:1, taillight 4.15:1. AA pass.

## Not generated, for the record

`site/static/icon.svg`, `site/static/apple-touch-icon.png` and
`site/static/favicon.ico` are hand-authored vectors (and raster renders of the
same geometry) following the app-icon spec in `docs/DESIGN.md`: taillight
fuel-nozzle silhouette whose hose draws a subtle checkmark, on midnight, no
text. They are drawn, not modelled - no prompt produced them.
