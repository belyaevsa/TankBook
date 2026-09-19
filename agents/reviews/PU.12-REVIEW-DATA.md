# PU.12-REVIEW-DATA - the training material, reviewed against the corpus it must survive

Read-only review. Evidence: `ml/pump-reader/REPORT.md` (all of it), `docs/EXTRACTION.md` -> "The
pump reader", the renderer (`profiles.py`, `glyph.py`, `row.py`, `augment.py`, `dataset.py`), the
Swift slicer (`PumpGlyphSlicer.swift`, `PumpQuadWarp.swift`, `PumpReaderHarnessTests.swift`),
`score.py`, the annotation (`windows.json`, `expected.csv`), `slices.json`, the committed sheets
(`train-sheet-after.png`, `held-out-cells-r2.png`), and the existing per-cell dump
(`.out/cells-r2`, filenames `<fixture>-<field>-<i>-<truth>-<read>`). No fixture image was opened;
the corpus stays held-out. Every corpus number below is computed from `windows.json` /
`expected.csv` / `slices.json` geometry and dump filenames only.

Headline state (REPORT.md round 2, shipped): per-glyph **0.400** on the 259 count-correct windows
(0.309 all 433), per-segment a .85 b .79 c .81 d .83 e .88 f .83 g .86 **dp .74**, per-window
0.004, synthetic validation 0.97 per-digit. The gap is entirely synthetic -> real.

## What the errors actually are (from the dump filenames, 1139 cells, 0.390)

- **45.5 % of all wrong cells read `?`** (316 cells): a thresholded segment pattern that is no
  digit. Segment losses dominate gains by ~5:1 (lost: c 369, b 369, a 311, d 283, f 263, g 249,
  dp 216, e 172; added: dp 64, g 42, a 14...). Under-detected lit segments = faint ink, strokes
  thinned by resampling, gaps closed by blur: a *surface and scale* failure, not a classifier one.
- **77 cells read `blank`** (11.1 % of errors), mostly `1`/`1dp`/`0`/`4`. The corpus contains
  **zero** blank cells (433 non-empty windows, **no leading space in any string**), so every blank
  read is an error: the blank class absorbs faint digits.
- **dp: 116 dropped, 64 added, 9 digit-lost-leaving-dp.** dp is in ~27 % of errors and per-window
  accuracy (0.004) is dp-bound: a window needs every glyph *and* its dp.
- Confusions that name a geometry: `0>8` 23 / `8>0` 8 (the middle gap closes or g dies: gap
  resolution at cell scale), `9>4` 11 (e dies), `0>7` 7, `4>1` 6.
- By field: board **177/241 wrong (73 %)**, unitPrice 169/269 (63 %), total 165/273 (60 %),
  liters 184/356 (52 %). The pylon grade boards are the worst cells in the corpus and are a
  different display family (distance shots, often dot-matrix LED).

## Findings, ranked by expected gain per unit of work

### 1. The training cell's aspect and horizontal phase are outside the real distribution (largest single gap)

`dataset.py:226-276` (`render_slicer_cell`). Measured, count-correct windows only:

| | crop aspect (pitch/band, before the 32x48 resize) | ink margin left / right (fraction of pitch) |
|---|---|---|
| real cells (`slices.json` rects x window quad aspect) | min 0.24, p5 0.46, **med 0.83**, p95 1.17, max 1.29 | right ~0 by construction, left = the pitch slack |
| synthetic (400-sample replay of the same code) | min 0.90, p5 0.93, **med 1.06**, p95 1.17, max 1.37 | med 0.22 / med 0.22 (centred) |

**57.8 % of real count-correct cells have an aspect below the synthetic minimum; 72.2 % below the
synthetic p5.** After the resize to 32x48 the median real glyph is ~25 % narrower relative to its
height than anything the model ever saw. Two causes, both in one function:

- `dataset.py:261-262`: `slack = pitch_px - CELL_W`, `lead = slack * U(0.2, 0.8)` centres the glyph
  in the pitch. The real grid is **phased on run ends**: `PumpGlyphSlicer.swift:263-282` computes
  the phase from the digit runs' right ends, so `rect.maxX ~= run end`, i.e. the ink's right edge
  sits at the cell's right edge and all the slack is on the left. The sheet confirms it (real
  digits hug the right border); `train-sheet-after.png` shows centred digits with slack both sides.
- `profiles.py:141,161,180,197,215` pitch ranges (1.15-1.55 x CELL_W) over a fixed 40 px ink band
  give aspect 0.90-1.37 only. Real pitch/band reaches 0.46: narrow-pitch heads, bands inflated by
  a comma below the baseline, and loose window quads (band fraction of window height: med 0.91,
  **p5 0.70**) all push the real aspect down. Synthetic band (`dataset.py:206-223`) is the exact
  ink band of a clean row, so it can never be inflated.

Proposal: in `render_slicer_cell`, (a) phase the crop on the rendered row's own right ink edge
(`lead = slack * U(0.85, 1.0)` plus +-1-2 px, i.e. right-aligned like the Swift grid) instead of
`U(0.2, 0.8)`; (b) widen the effective aspect support: sample pitch from ~(0.6, 1.6) x CELL_W per
row and, with p ~ 0.3, inflate the band downward/upward by 5-25 % (comma tail, loose quad, second
row ink) so the crop aspect spans ~0.5-1.3 with median ~0.85; (c) keep the +-6 % y jitter but let
the slack be one-sided (extra rows above *or* below), matching how a threshold band grows.
Testable: a 400-sample replay of the sampler must report an aspect distribution whose p5/med/p95
land inside the real [0.46, 0.83, 1.17] +-0.05, and a right-margin statistic near 0. This is the
same *kind* of change as PU.9 (framing alone moved count-correct 0.105 -> 0.215) and PU.10
(0.215 -> 0.400), aimed at the part of the real support the last two rounds never covered.
Moves: per-glyph 0.400 (cc) and 0.309 (all); expect the b/c/e segment losses (single thin strokes
at the cell sides) to shrink first.

### 2. The faint-display regime is still absent, and the augment that covers it is switched off

`dataset.py:328-343` ships `contrast_prob = 0.0`, so `apply_contrast_collapse`
(`augment.py:182-194`) never fires, and no LCD palette in `dataset.py:48-61` can draw below ~40-50 %
on/ground contrast (closest: dark olive ground (85..135) vs on (12..45)). The real sheet's fourth
row is exactly that regime (washed grey-on-grey at 10-20 %), and REPORT.md names the survivors:
`pump-004`, `pump-062`. 45.5 % of errors are `?` reads, the signature of ink the model has only
ever seen at full contrast. The PU.7 ablation that condemned contrast collapse
(REPORT.md:106-117) ran **before** the PU.9 framing and the PU.10 palettes; ablations do not
transfer across dataset regimes, and the round-2 sheet lists the faint heads among what is left.

Proposal: re-run the ablation in the current regime: `contrast_collapse` at 0.10-0.15 with target
range 0.10-0.30 (not 0.10-0.25 flat), plus a "faint panel" palette tail (on/ground luminance
difference 15-30 % of the normal families) sampled at ~10 %; keep the knob per-dataset so the
ablation is one command. Testable: `test_contrast.py` already asserts the collapse lands in range;
add a dataset-level test that ~10 % of samples have on/ground contrast below 30 %. Moves: the `?`
share (316 cells), per-segment b/c/f on faint makes, and `pump-004`/`pump-062` by name.

### 3. The dp is drawn as a dot in a fixed corner; the corpus draws a comma between cells

Real commas (sheet rows 1, 3, 4) sit **below the digit baseline**, carry a tail, and land in the
gap between cells - often with visible ink at the *left edge of the next cell*. The renderer draws
a round dot clamped to the cell's inner bottom-right corner (`glyph.py:228-231`), and
`dp_offset_frac` is sampled (`profiles.py:76,106`, `Resolved` field) but **never used** - a dead
knob, so dp position has zero variance beyond diameter. Consequences, all visible in the errors:

- a comma below the baseline extends the real ink band downward (the digit then occupies the top
  ~85 % of the cell); the synthetic band never extends, so dp-carrying real cells have a vertical
  layout no training cell has;
- comma ink at a cell's left edge teaches nothing today, because no synthetic cell ever shows it.
  The truth (`score.py:41-59`, `parse_cells`) puts the dp bit on the *host* digit, so the correct
  per-cell target for "comma ink at my left edge" is dp=0 here and dp=1 on the previous cell. The
  model currently adds dp when it sees comma-ish ink anywhere (64 added-dp errors: `4>4dp` 10,
  `0>0dp` 9, `8>8dp` 8, `3>3dp` 7);
- the slicer attaches a dp run by `run.start` (`PumpGlyphSlicer.swift:284`), which for a comma in
  the gap is the *next* cell - the same attribution question, on the Swift side.

Proposal: draw the dp as comma-with-tail with p ~ 0.4 (the corpus is 168 commas / 422 dps = 40 %),
place it with the dead `dp_offset_frac` (below baseline, extending the band, with p ~ 0.5), and let
it bleed 1-3 px into the next cell's left edge with p ~ 0.3 while the row-level parse keeps the dp
bit on the host - so the next cell's target is explicitly dp=0 with comma ink present. Testable: a
render test that a comma-below-baseline row's ink band is taller than the same row without dp, and
that the cell right of a bleeding comma carries target dp=0. Moves: dp bit 0.74, the 116+64 dp
errors, and per-window 0.004 (the number that is dp-bound).

### 4. Label priors disagree with the corpus on three axes, and two of them cost errors

`dataset.py:65-66,138-146` vs the corpus, measured over all 456 windows (1955 digit cells):

| | training | corpus |
|---|---|---|
| blank cells | 8 % | **0 %** (no leading space in any of 433 non-empty strings) |
| dp-only cells | 8 % | ~0 % (`parse_cells` always attaches dp to a host; dp-own-cell truth is unreachable in scoring) |
| dp on a digit | 50 % of digit cells (42 % of all) | **21.6 %** (422/1955; per field 0.19-0.25) |
| digit frequencies | uniform 8.4 % each | 0: 22.5 %, 1: 15.4 %, 9: 12.5 %, 4: 10.0 %, 8: 9.0 %, ... 6: 4.2 % |
| leading zeros | uniform digits, zero-pad 30 % of rows (`row.py:76-77`, unused by the dataset) | 102/433 windows zero-padded (~189 cells, 9.7 %), up to 3 leading zeros |

The blank prior is actively harmful: 77 blank reads on a class with zero test mass, concentrated
on faint `1`s and `0`s - the model's "nothing here" threshold is calibrated by 8 % of training mass
that the corpus never presents. The dp prior at 2x corpus rate inflates added-dp errors. The digit
skew is not exotic: money strings have Benford leading digits and zero-heavy tails (`.00`
endings, zero padding), which `row.py:70-81` (`sample_row_text`) already approximates - but the
dataset never uses it, sampling one uniform label plus uniform neighbours instead
(`dataset.py:145-152,248-249`).

Proposal: blank 8 % -> 2 %, dp-only 8 % -> 1 % (keep a floor for heads that blank-pad; say so in
the comment), dp-on-digit 50 % -> ~22 %; and draw the target *from a rendered money-like string*
(reuse `sample_row_text` with corpus-shaped constants: lengths 4/6/5/3 at 285/99/31/15, zero-pad
24 %, comma 40 %, no leading spaces) so digit priors, dp rate, zero padding and neighbour
correlation all fall out of one generator instead of four independent knobs. Testable: a 20 k-sample
draw's digit histogram within +-2 pts of the corpus row above. Moves: the 77 blank reads, the 64
added-dp reads, and the 0/8 and 9/4 confusions (the corpus's two most frequent digits are exactly
the pair the model swaps).

### 5. No compression, and noise at the wrong scale

Every real cell passed through a photo-scale sensor and a JPEG/HEIC encoder at 30-60 px per glyph;
the sheet shows blocking in gradients and mosquito noise around strokes. The renderer adds
Gaussian noise sigma 2-10 **after** the 32x48 resize (`augment.py:197-199`, called from
`dataset.py:271-274`), which is white noise at cell scale - a different spectrum from aliased
photo-scale noise - and nothing ever compresses. Cheapest fix standalone: a JPEG encode/decode
cycle (quality 60-90, 4:2:0) on ~60 % of cells before the rest of the pipeline; the principled fix
is finding 6's chain, where noise and compression land at photo scale *before* the downsample.
Moves: the `?` share and the b/c stroke losses (chroma-subsampled, ringing-thinned verticals).

### 6. Perspective is applied at the wrong scale, twice over

`augment.py:19` fires perspective on 60 % of samples, and in `render_slicer_cell` it runs on the
**resized cell** (`dataset.py:271-274`). A real cell arrives already rectified: the quad warp
(`PumpQuadWarp.warpToStrip`) removed the panel's perspective, leaving only annotation residual
(a fraction of a degree). A +-12 deg warp inside a 32x48 cell is a distortion no real cell carries;
meanwhile the row-level warp that *would* be realistic (`row.py:141-151`, boxes transformed) is
switched off for slicer framing (`dataset.py:250`, `augment=False`). Proposal: move perspective to
the rendered row (mild, before slicing) and cut the cell-level probability to ~0.1 with half the
tilt. Nearly free; removes a training-only artefact the sheet still shows (sheared glyphs, clamped
edge smears).

### 7. One row per window; real bands sometimes span more

Real band fraction of window height: med 0.91, p5 0.70 - and the low-aspect tail (aspect < 0.5) is
consistent with bands that caught a second ink row or a unit label through a loose quad (the
annotation is +-1 % of the image edge, `windows.json` `_about`). `render_slicer_cell` renders one
row on clean ground, so a two-row band - partial digits above or below the target - is a cell
content class the model has never seen. Proposal: with p ~ 0.12 render a second row 1.2-1.6 band
heights away and let the band threshold (not the ink band) decide the crop, i.e. compute the band
the way the slicer does (15 % of the centred row profile, `PumpGlyphSlicer.swift:146-152`) instead
of the exact midpoint threshold in `dataset.py:206-223`. This also fixes a quiet contract drift:
the synthetic band and the Swift band are different functions of the same row. Subsumed by 8 if 8
lands first.

### 8. Generate training cells by running the Swift slicer on synthetic rows, not by imitating it

The imitation in `render_slicer_cell` already diverges from `PumpGlyphSlicer` in five places found
above (band function, phase, aspect support, band slack, dp-below-baseline), and PU.9's history
says a framing drift costs a third of the score. The brief's question has a clean answer: **the
same code, not a mirror.** `PumpReaderHarnessTests.swift:200-261` already does exactly this for
real fixtures - warp to strip, slice, write `slices.json` plus the strips. Point the same path at a
directory of *synthetic* strips (rendered rows at photo scale, warped by `PumpQuadWarp`), as a
small Swift CLI or a test-target mode: input = strips + labels.csv, output = cells.json (rects) or
cut 32x48 PNGs plus the 8-bit target per cell. Python training then consumes pre-cut cells
(32x48 uint8 PNG ~1-2 KB; 50 k cells ~75 MB in `.out/`, regenerated per renderer change, not per
epoch), and augmentation that is genuinely cell-local (noise, compression, exposure) runs in
Python on the cut cell while everything geometric happens in Swift. Cost: one CLI target plus a
render loop; benefit: findings 1, 3 (band), 7 and the strip-height question below stop being
two-implementation problems. The oracle is the slicer itself, so any future slicer change
re-frames the training set for free - which is also the insurance against the next PU.9 shock.
Guard: a pytest that renders N rows, cuts them through the CLI, and asserts the label round-trips
(target bits from labels.csv, not from the slicer) so the oracle cannot leak into the labels.

### 9. Strip height is a three-way disagreement waiting for PU.5

The harness warps strips at **96** (`PumpReaderHarnessTests.swift:269`), `score.py` re-warps the
same quads at **48** (`score.py:116-117`) and applies the normalised rects there, and the synthetic
row renders glyphs at native 48 with a 40 px ink band (`glyph.py:19-22`, `dataset.py:252-270`).
Normalised rects survive the height change, but the resampling chain does not: a 96-strip cell is
cut from twice the pixels of a 48-strip cell, and the shipped model was scored on the 48 chain
while the slicer's own ratchets were measured on the 96 chain. Whichever height PU.5 ships becomes
the framing the model must match; the dataset must be built at that height, and the choice should
be written in one place (`docs/EXTRACTION.md` pump section) with the reason (photo digit heights
30-60 px say 48 is a downsample-then-upsample, 96 is closer to 1:1 - measure, do not guess).
Moves: nothing today; prevents the next framing-only third-of-the-score swing.

### 10. Board cells drag the headline and may not belong to it

Board windows are 130 of 456 and are 73 % wrong - pylon grade signs, shot from metres, frequently
dot-matrix LED rather than seven-segment. The five make profiles are all pump-head geometries;
nothing in the renderer draws a dot-matrix digit or a distance-aliased sign. Two honest options:
(a) PO rules board out of the ship gate (PU.5 consumes total/liters/unitPrice; the board field
exists in the annotation as context) and the headline becomes the three transaction fields
(liters 52 % wrong is the honest number to chase), board reported separately; or (b) board stays,
and the renderer gains a sixth profile family (dot-matrix or segmented sign, small-on-strip scale,
long-distance blur) plus board-shaped strings (4 cells, 40 % comma). Either way the per-field split
should enter REPORT.md's standing table, because a single per-glyph number currently averages a
near-field LCD problem with a far-field sign problem.

### 11. Make and technology priors vs the corpus mix

Filename-token counts over the 114 fixtures: gilbarco ~45, wayne/dresser ~37, scheidt ~10, tokheim
~8, lukoil ~2, adast/topaz ~2, unmarked ~10; currencies EUR 80 / RUB 31 / KZT 3. Training samples
makes uniformly (`dataset.py:364`) over five geometries, so scheidt and tokheim geometries are
over-represented ~2-2.5x and gilbarco under-represented ~2.3x against the corpus, while the
technology prior (lcd .85 / led .10 / vfd .05, `dataset.py:42`) is about right if the corpus heads
are LCD and the boards are not scored. Recommendation: weight makes by corpus share with a floor
(e.g. gilbarco .35, wayne/dresser .30, scheidt .12, tokheim .10, rest .13) *if* the PO accepts
corpus-mix calibration (see questions); otherwise keep uniform and say the gate measures
robustness, not the field mix. Note also that `score.py:62-68` (`make_of`, third dash token)
mislabels makes (`pump-004-...-tokheim` -> "kz", Circle K fixtures -> "circlek", "gpn"), so the
per-make table in REPORT.md and in `held-out-r2-cc.json` is not a make table; any make-level
decision should use token search over the whole filename.

### 12. Small things, cheap to fix while the renderer is open

- Occlusion (`augment.py:210-222`, p 0.08) draws thin dark *lines*; real occluders at cell scale
  (nozzle, finger, hose) are broad soft dark blobs entering from one edge. The sheet still shows
  the lines. Make them edge-anchored blobs or drop the op.
- `_draw_dp` ignores `dp_offset_frac` (finding 3); until then it is a sampled field with no effect
  and a test cannot catch its misuse.
- `sample_row_text` (`row.py:70-81`) adds leading spaces with p 0.25; the corpus has none. If it
  becomes the target generator (finding 4), drop or floor that branch.
- Segment ends: the sheet's boldest real heads (dark navy on cream) show near-square ends with
  tiny gaps; `_hseg`/`_vseg` (`glyph.py:129-152`) always chamfer to a point. Add a square-end
  variant to one bold profile.

## What I checked and found right

The round-2 fixes hold up against the sheets: the LCD ghost now steps from ground toward ink and
the real grey LCDs show the same faint off-segments; the six palette families cover the sheet's
grey-blue, olive, cream-navy and amber families; bold + slant match the real stroke weights and
the italic Gilbarco/Wayne heads; the pitch-wide cell with neighbour edges at the borders matches
the real cells' left-edge partial strokes. The dp bit is load-bearing and correctly kept in the
target (REPORT.md's named mutation). Nothing here proposes touching `SegmentNet`.

## What I would need to know or have

Ranked; each is the cheapest thing that unblocks a finding above.

1. **Is `board` in the ship gate?** One sentence decides finding 10: whether the headline number is
   the three transaction fields or includes 130 pylon-sign windows the renderer was never built
   for. Zero cost to answer, largest effect on what "0.400" means.
2. **A calibration policy for synthetic geometry.** Findings 1 and 4 want priors (crop aspect,
   phase, digit mix, comma rate) that can only come from the corpus's aggregate geometry
   (`slices.json` rects, `windows.json` strings) or from head datasheets and public head photos.
   PU.10 set the palettes "by eye from the cell sheets"; I need the same explicit sign-off for
   geometry, or a ruling that geometry stays datasheet-only. The overfitting risk is real (114
   fixtures) and should be owned, not discovered later: calibrate on aggregate shape statistics
   only, never on pixels or per-fixture labels, and keep the gate on all 114.
3. **Glyph-level annotation for ~30 windows** (per-glyph boxes plus "which cell owns this comma"),
   orchestrator-authored like `windows.json`. It separates the two errors the cc subset currently
   conflates - slicer cell placement vs classifier read - and validates finding 3's attribution
   contract against truth rather than against the slicer's own opinion.
4. **The shoot list, in order:** Scheidt & Bachmann +20 (10 today) and Tokheim +15 (8) to fill the
   two thin make families; Lukoil/Adast +10 specifically to answer whether any corpus head is
   dot-matrix (finding 10 hinges on it); night +25 and wet/rain +15, because every augmentation in
   `augment.py` for those regimes is currently unvalidated guesswork; KZT +10 (3 today). Keep
   full-resolution originals.
5. **Burst or short video at capture time.** If the app may keep 3-5 frames of the panel, per-cell
   median-over-frames turns single-frame noise and glare into a solvable problem and gives a
   stability measurement the corpus cannot; if capture is one still, the renderer must carry all
   of the noise budget alone. This changes what "precision >= 0.99 on committed cells" costs.
6. **Three zero-padded fixtures looked at by someone who can see** (`pump-009`, `pump-011`,
   `pump-012`): are the leading zeros drawn dimmer than the significant digits? Dim zeros are a
   contrast class between ghost and ink that the renderer cannot draw today, and 189 corpus cells
   are leading zeros. I am not allowed to open the fixtures; the sheets did not settle it.
7. **RAW or uncompressed frames for ~10 heads**, to calibrate the photo-scale MTF and noise that
   findings 5 and 8 imitate; JPEG quality of the existing fixtures, if known, is the cheap version.
8. **A second annotator pass over dp/comma placement in `windows.json`.** dp truth flows straight
   into training targets through `parse_cells`; 422 dps of which 168 are commas, and finding 3 says
   comma attribution is the subtle part.
9. **The pseudo-label decision, before anyone builds it.** A self-training loop over future user
   captures needs: consent and a retention ruling (the 30-day precedent in `CLAUDE.md` rule 9
   covers the ledger, the import file and the outbox - a fifth store of user content needs its own
   written decision), an on-device label filter (per-cell posterior margin *and* the
   `volume x price = total` cross-check agreeing, else the sample is dropped), and a held-out
   corpus that stays untouched so the gate still measures anything. My recommendation: not yet.
   The synthetic chain above has not been exhausted, and a pseudo-label loop trained on the
   reader's own mistakes will cement exactly the confusions (0/8, 9/4, dp attribution) that this
   review says are framing artefacts, not knowledge.

*Method note: no fixture image was opened; the real-cell evidence is the committed derived sheets
and the dump filenames, as the brief allows. Corpus statistics are from `windows.json`,
`expected.csv` and `slices.json` geometry. The synthetic statistics are a 400-sample replay of
`render_slicer_cell`'s own arithmetic under seed 7, and a 20-sample visual pass over
`train-sheet-after.png`.*
