# PU.13-REVIEW-ANNOTATIONS - a second pass over the number-window oracle

Read-only review, 2026-09-19. One file written: this one. `windows.json` untouched; every change I
recommend is named with its evidence below. No repo source was modified (the uncommitted
`PumpGlyphSlicer.swift` / `dataset.py` / `train.py` / `.mlpackage` changes in the tree during this
review belong to the concurrent ML run and were not touched).

## Method (no image was "seen"; every image was measured)

All measurements ran with `ml/pump-reader/.venv/bin/python` (pillow 12.3.0, pillow-heif, numpy).
Each fixture was loaded EXIF-transposed, then rotated by its declared `rotationCW`; each quad was
warped to a native-resolution strip; ink was detected polarity-free as `|A - median| > max(18,
0.30 x p99)`; the band is the rows carrying >= 2 % ink; runs are column-density groups at a valley
threshold of 0.20 x peak (0.15 / 0.30 also recorded); pitch is `stripW / glyphCount(text)`; the
digit-periodicity check is an autocorrelation over the band's column profile in [0.55, 1.7] pitch.
Where a number alone could not settle a question I rendered the strip as an ASCII density map and
read the glyphs as text - that is how the string verdicts below were made, and every string claim
in this report was confirmed by such a reading, never by one statistic. Lateral extension probes
re-warp the quad grown by 0.25-1.6 strip-widths to test whether a digit row continues OUTSIDE the
annotation (the missing-leading-zero / missing-cell test).

Artifacts (scratch, gitignored): `ml/pump-reader/.out/review-ann/measure3.py` + `metrics3.jsonl`
(456 window records), `render.py`, `analyze.py` + `analysis.txt`, plus the earlier `measure.py` /
`metrics.jsonl` pass left by the first dispatch of this brief (kept, not overwritten; its
`rotate_points_cw` copy has the sign bug described in section 6, which is why `measure3.py` exists).
Baseline: `scripts/pump-windows-check.py --check` - **exit 0, "114 fixtures, 456 windows, 0
problems"**.

Corpus shape as measured: 456 windows = 114 total (109 text / 5 blank), 114 liters (114/0),
98 unitPrice (97/1), 130 board (113/17). 433 texted, 23 blank. Makes by filename attribution:
gilbarco 47 fixtures, wayne 40, tokheim 11, scheidt 10, adast 1, topaz 1, unknown 4 (`pump-001`
(Wayne per README), `pump-003` (Gilbarco KZ), `pump-067`/`pump-068` (Circle K Jarvevana)).
Windows per fixture: 3 x 75, 5 x 5, 6 x 32, 7 x 2. Strip size: median 484 x 202 px; smallest
`pump-002` unitPrice at **77 x 29 px** (19 px/glyph - the hardest cells in the corpus); largest
2601 x 645. Ink polarity: 354 windows dark-ink (LCD), 102 light-ink (emissive LED/VFD).
453 of 456 quads are exact axis-aligned rectangles; the 3 tilted ones are `pump-020` (perspective
correction on an angled shot - a feature, not a defect).

## Headline findings

1. **`pump-003` total is mis-transcribed**: the display shows `20886.3` (6 cells, measured) and the
   string says `20886.25` (7 cells). The fixture README has been saying `20886.3` all along.
2. **`pump-061`'s four board quads are misplaced ~1.2-1.5 cell heights low** - they frame the gap
   between the price row and the discount row, not the digits. The strings are right; the boxes are
   not. The only windows demonstrated misplaced by the measurement sweeps (bandFrac and solid-row
   scans over all 456).
3. **`pump-009` board[6] reads `072,88`, not `072,80`** (the README agrees; the last cell's centre
   bar is lit at exactly the density of the window's confirmed `8`).
4. **`pump-026` unitPrice is missing its comma**: comma ink measured in the gap after cell 0,
   matching the control `pump-028` (`1,924`, same station, same value). The dp-bit ground truth for
   that window is wrong.
5. **`rotationCW` is set on 5 fixtures, not 3** (the brief's count is stale): `pump-019`/`020` = 90,
   `pump-021`/`022`/`023` = 270. The annotation is **correct** - but every shipped consumer warps
   these fixtures from the wrong image region or as vertical strips (section 6). 23 windows (14 of
   them texted) are currently unscorable garbage in `score.py`, the Swift slicer path,
   `calibrate.py` and PU.4's `slices.json`.
6. **The 0.99 precision gate is arithmetically unreachable for a fully honest reader**: 4 of the
   178 scored cells (2.2 %!) assert CSV values their displays physically cannot show
   (`pump-003`/`031`/`065`/`073` totals, all beyond the scorer's 0.005 tolerance). Precision caps
   at 174/178 = **97.8 %** unless the scorer grows a display-value channel or a rounding tolerance.
7. **Scheidt-RN zero padding is internally inconsistent**: `pump-107`/`108` transcribe the leading
   zero (`02049.0`), `pump-087`/`088`/`090` - the *same 3000 L x 68.30 fill* - do not (`2049.0`).
   Measurement says `pump-087`'s display lights 6 cells including the leading zero.
8. **No string in the oracle has a leading space** (0 of 433). The brief's ` 40.00` example does not
   exist; `glyphCount`'s space branch is dead on this corpus (PU.12 noted the same). Unlit leading
   cells are simply not transcribed - which is exactly why finding 7 matters.
9. Gilbarco Circle K EE zero padding is **flawless**: 42/42 totals 6 digits, 43/43 liters 6 digits,
   42/42 prices 4 digits (incl. the rotated Sikupilli pair). Wayne: no padding anywhere, consistent.
   The digit-count outliers are confined to Scheidt-RN; the Gilbarco price rows have a separator
   question instead (7 of 42 prices transcribed without a comma - one of them provably wrong).
10. The 23 blank-text windows are **all justified**: none carries periodic structure (autocorr 0,
    no runs). Nobody gave up on a readable window.

## 1. Quad tightness and bias

Ink band as a fraction of strip height (`bandFrac`), texted windows:

| | n | min | p5 | median | p95 |
|---|---|---|---|---|---|
| gilbarco | 147 | 0.27 | 0.90 | 1.00 | 1.00 |
| wayne | 199 | 0.15 | 0.80 | 1.00 | 1.00 |
| tokheim | 33 | 0.86 | 0.90 | 1.00 | 1.00 |
| scheidt | 30 | 0.58 | 0.90 | 1.00 | 1.00 |
| unknown | 18 | 0.71 | 0.84 | 1.00 | 1.00 |
| adast / topaz | 6 | 0.95 | - | 1.00 | 1.00 |
| by field: board | 113 | 0.15 | 0.77 | 1.00 | 1.00 |
| by field: unitPrice | 97 | 0.27 | 0.76 | 1.00 | 1.00 |
| by field: liters | 114 | 0.58 | 0.91 | 1.00 | 1.00 |
| by field: total | 109 | 0.86 | 0.92 | 1.00 | 1.00 |

The quads are **vertically tight**: median band fraction 1.00 everywhere - the ink touches both
quad edges in the typical window. The oracle therefore offers a locator no vertical slack, and the
slicer must derive the band itself (PU.9's band-trim framing is the right response; a detector
graded on IoU >= 0.5 against these boxes is being held to a tight standard). The sub-0.6 tail is
not looseness but two defects and two hard images: `pump-061` board[4]/[5] (0.20/0.15 - misplaced,
finding 2), `pump-049` unitPrice (0.27 - the "faint-lcd" fixture, contrast 0.10, digits below any
threshold I could set; ASCII rendering shows nothing - string unverifiable, plausible from its
`pump-048` sibling at the same 1,889 price), `pump-093` liters (0.58 - the "faded" fixture).

Margins between strip edge and first/last ink column, in pitch fractions (`stripW / glyphCount`):

| | L median | L p95 | L mean | R median | R p95 | R mean | (L-R) median | (L-R) mean |
|---|---|---|---|---|---|---|---|---|
| all texted | 0.05 | 0.67 | 0.18 | 0.00 | 0.30 | 0.08 | 0.00 | **+0.11** |
| gilbarco | 0.03 | 0.60 | 0.15 | 0.00 | 0.35 | 0.11 | 0.00 | +0.03 |
| wayne | 0.01 | 0.56 | 0.14 | 0.00 | 0.28 | 0.06 | 0.00 | +0.09 |
| **scheidt** | **0.34** | **1.52** | **0.56** | 0.00 | 0.31 | 0.04 | **+0.34** | **+0.52** |
| tokheim | 0.11 | 0.48 | 0.15 | 0.07 | 0.21 | 0.08 | +0.02 | +0.08 |
| by field: unitPrice | **0.28** | 0.78 | 0.30 | 0.00 | 0.34 | 0.10 | +0.28 | +0.20 |
| by field: total | 0.01 | 0.47 | 0.13 | 0.00 | 0.32 | 0.08 | 0.00 | +0.05 |
| by field: liters | 0.04 | 0.52 | 0.13 | 0.00 | 0.27 | 0.10 | 0.00 | +0.03 |

**Yes, the left bias is there, and it is structural, not noise.** Ink touches the right quad edge
in 353/433 windows (81.5 %) and the left in 298/433 (68.8 %); the right margin's median is 0.00
and its p95 is 0.30 pitch - there is essentially no trailing-slack population. The left slack
concentrates exactly where a fixed-cell display leaves unlit leading cells inside the digit field:
Scheidt (median +0.34, up to +1.74 pitch - the quads honestly frame the display's cell field with
its dark leading cell, see section 3) and the unitPrice field across makes (median +0.28 - price
rows sit right-aligned in a wider field). The slicer's leading-blank logic and PU.12's proposal to
phase synthetic crops on the right ink edge are both consistent with this oracle: slack is a
left-only phenomenon. Training data that centres glyphs in the pitch pays for a distribution the
corpus does not have.

Outliers worth an eye (details in the fix list): `pump-008` total lm = 3.29 pitch (the quad frames
the video-overlay banner, the stylised digits occupy its right half); `pump-039` total rm = 2.35
(the trailing cells of `0021,09` fall below the ink threshold - ASCII shows only 4 of 6 cells at
normal threshold while the autocorrelation still finds the 6-cell periodicity across the full
width, so this is most likely a faint-ink right side, not a loose quad); `pump-020` liters
rm = 1.75 and `pump-038` total rm = 1.58 (glare/reflection washing the row's right end);
`pump-002` unitPrice lm = 1.04 on the corpus's smallest strip (77 x 29 px).

## 2. Strings vs ink (crude glyph count)

`runs(0.20 x peak valley) - glyphCount` over the 433 texted windows:

| delta | -5 | -4 | -3 | -2 | -1 | 0 | +1 | +2 | +3 |
|---|---|---|---|---|---|---|---|---|---|
| windows | 5 | 16 | 47 | 58 | 75 | **139** | 71 | 20 | 2 |

**|delta| >= 2 on 148 windows (34 %)** - and that number is a property of the counter, not of the
annotation. The disagreeing population splits cleanly by run-width evidence into two artifacts:
*fused* runs (one run of width ~g pitch: LED bloom and LCD ghost segments raise the inter-digit
valleys above any fixed threshold - 5 single-run `width=[g.0]` windows at d = -(g-1), ~2/3 of the
negatives) and *fragmented* runs (a `0`/`4`/`9` splitting into its vertical-bar pair at high valley
thresholds - the positives, e.g. `pump-030` up `68,44` = 6 runs at corr 0.84, `pump-073` total
`2249.9` = 7 runs). A single-threshold run counter cannot adjudicate strings on this corpus - the
same wall PU.4's slicer hit at count agreement 0.60. Every |delta| >= 2 window is classified in
`analysis.txt` section 4 with its widths, contrast and correlation; the ones whose evidence did not
reduce to an artifact were individually examined - ASCII-rendered: `pump-003` (3 windows),
`pump-008` total, `pump-009` boards[3][6], `pump-013` liters, `pump-016`/`017` totals + a board
row each (extensions), `pump-019`/`020`/`021` totals (rotated, both rotation hypotheses),
`pump-023` board[5], `pump-026`/`028` prices, `pump-034`/`036`/`038`/`039` totals, `pump-049`
price, `pump-061` boards (original and shifted), `pump-073` total, `pump-087`/`088`/`089`/`090`/
`107` totals (extension probes), `pump-094` price, `pump-098` liters; numeric-profile only:
`pump-030` total+price, `pump-063` price, `pump-091`/`092`/`093`/`108` totals, `pump-104` price.
**All confirm their strings except
`pump-003` total (finding 1), `pump-009` board[6] (finding 3), `pump-026` price (finding 4), and
`pump-087` total (finding 7).** The digit-periodicity cross-check (autocorrelation, 200 windows at
corr >= 0.5, 59 with |cells - g| >= 0.75) flags the same single genuine case: `pump-003` total at
ratio 0.80 with clean uniform runs; the other 58 are half-lag/double-lag locking (cells ~ 2g or
~ g/2) or fusion, and the individually-read ones above all resolve in the annotation's favour.

The `pump-003` total evidence in full, because it is the one transaction-string error: runs at
starts [0.16, 1.45, 2.69, 3.91, 5.13, 6.52] pitch-units (pitch = w/7) - spacing 1.22-1.29, i.e.
**6 cells of width w/6**, not 7 of w/7; widths [0.90, 0.88, 0.88, 0.85, 0.81, **0.48**] - five
full digits then a narrow cell, exactly the shape of a `3` (no left vertical); separator ink in
the gap at x 5.94-6.52, centroid at 0.67 of band height (a low-hanging comma, i.e. after the 5th
digit: `20886,3`); a faint duplicate row in the top of the window shows the same 6-cell
periodicity; and the fixture README states "displayed as `20886.3`". The string `20886.25` is the
computed truth, not the displayed one - which is precisely what `_about` forbids ("text is what the
display SHOWS").

## 3. Zero padding and leading blanks

Leading spaces: **none, anywhere** (finding 8). Leading zeros: transcribed whenever lit. Per
family (texted transaction windows; digits = `nDigits`):

| family | total | liters | unitPrice | verdict |
|---|---|---|---|---|
| gilbarco Circle K EE (incl. `circlek-gilbarco`, sikupilli pair) | 6 digits x 42 | 6 x 43 | 4 x 42 | **perfectly consistent** |
| gilbarco LUKOIL RU (`pump-002`/`007`) | 6 x 2 | 4 x 2 | 4 x 2 | consistent |
| gilbarco RU zero-pad (`pump-009`) | 7 x 1 | 7 x 1 | 5 x 1 | consistent (bigger RUB amounts, own head) |
| gilbarco Tatneft (`pump-018`) | 5 x 1 | 4 x 1 | 4 x 1 | unpadded head, fine |
| scheidt-RN (`087`-`093`, `107`, `108`) | **5 x 7, 6 x 2** | **4 x 7, 6 x 2** | **4 x 7, 5 x 2** | **INCONSISTENT - finding 7** |
| scheidt preset (`pump-010`) | 6 x 1 | 4 x 1 | 4 x 1 | different head (2-dp totals), fine |
| wayne (all) | 3-6 natural | 3-4 natural | 4 x 24 | consistent, never padded |
| tokheim | 4 x 2, 5 x 6, 6 x 3 | 4 x 11 | 3 x 4, 4 x 7 | two conventions, each consistent within its head (1-dp truncators vs 2-dp exact; `71,3` vs `71,30` are different stations) |

The Scheidt-RN split, with the measurements: `pump-107` (`02049.0`) shows **6 lit cells** on a w/6
grid (runs at 0.15/1.23/2.19+2.60 ("0" bar pair)/3.23+3.59 ("4")/4.20/5.14, corr 0.75) - the
padding is real and correctly transcribed. `pump-087` (`2049.0` - the same 3000 L x 68.30 fill,
same station, day shots with `088`/`090`): run starts at 0.41(fused to 1.52)/1.82/2.65/3.45 in
pitch-5 units - spacing 0.80-0.87 = **w/6**, with a digit-width run in the leading-cell position
discrete from the reflection wing that ends at x = 0.02. Read: six lit cells, leading zero on -
the string is missing it. `pump-088`/`090` are unreadable under reflection (single fused runs).
By contrast `pump-089` (`1024.5`) and `pump-091` (`1427.0`) - different fills, different price
points, likely different heads - measure 5 lit cells on a w/6 grid with the leading cell **dark**
inside the quad (1.36-1.4 cells of blank slack left of the first digit): their unpadded strings are
correct as written. So the family splits honestly by head, and the oracle currently transcribes one
head two different ways. `pump-092`/`093` (6385 price = yet another station) show no lit leading
zero either (`pump-092` runs start 0.45 pitch inside a tight quad; `pump-093`, the "faded" shot,
is inconclusive); leave both as written.

The Gilbarco price comma question (all 7 no-separator prices tested): `pump-011`/`012` `1789` - gap
ink sits at the TOP of the band (centroidY 0.03-0.06), not low: no comma rendered, strings right
(and the check script's docstring documents `1789 (no point shown)`). `pump-026` `1924` - gap after
cell 0 carries 241 px of ink at centroidY **0.77** (low = comma tail), against the control
`pump-028` `1,924` (same station family, same value): 280 px at 0.62. The ASCII rendering of
`pump-026`'s strip shows the same low blob. **`pump-026` should read `1,924`.** `pump-020` `1859`:
246 px at 0.75 in the cell-0 gap - weak but same signature; eyeball it with `pump-019` `1754`,
`pump-032` `1759`, `pump-040` `1849` (all too faint, contrast 0.11-0.22, to call). The value is
unchanged either way (the check script scales x1000), but the dp-bit ground truth that PU.11 found
dead-on-real-cells (AUC 0.52) is poisoned by every wrong one of these.

## 4. The declared exceptions - and the undeclared ones

Declared and verified: `pump-031` csvDisagrees (display `0032,58` = 16.80 x 1.939, CSV holds the
receipt's post-discount 32.50) - the only entry with the key; `pump-072` notOnDisplay (loyalty
1.894, board shows 2.059-2.119) - the only entry with that key; `pump-067` total legibility
"partial" (`99,59` through glare; band 0.92, contrast 0.52, fused runs - consistent with partial).
`pump-windows-check.py --check` exits 0.

Full CSV-vs-string classification (script in scratch, same `normalise`/`matches` logic as the check
script): **285 exact**; **24 "equal value, display renders fewer decimals"** (the KZT integer heads
`pump-004`/`006` total+price; the 1-dp truncated-total family `pump-018`/`044`/`083`/`085`/`086`/
`087`-`093`/`106`-`110` - all numerically equal to their CSV cells, none a trap); **7 x1000 scale**
(the point-less Gilbarco prices: `1789` twice, `1754`, `1859`, `1924`, `1759`, `1849`); **2
display-rounding cells** (`pump-065` `3765,7` vs 3765.65; `pump-073` `2249.9` vs 2249.92); **1
CSV-blank-but-
display-legible** (`pump-074` total `1984,8` - internally consistent: 29,00 x 68,44 = 1984,76,
rounded to 1 dp; the blank's reason is recorded nowhere); 6 blank-text windows all matching blank
CSV cells; the 16 fixtures without a unitPrice window all matching blank/notOnDisplay CSV cells.
There is **no** 3-decimal-price-on-a-2-decimal-display case: Gilbarco's 3-dp prices are rendered
either in full (`1,944`) or point-less (`1789`), and the RU/KZ heads only ever hold 2-dp values.

So: the declared exceptions are not the only ones, but the undeclared ones are all benign notation
differences - **except at the gate**. `CorpusPumpScorer` scores `abs(got - want) < 0.005` against
expected.csv (`CorpusABScorer.swift:150`, used at `CorpusPumpScorer.swift:67`). Four cells hold
receipt values their displays never showed, beyond tolerance: `pump-031` total (0.08 - *declared in
windows.json, which the scorer does not read*), `pump-065` total (0.05), `pump-073` total (0.02),
`pump-003` total (0.05, once its string is corrected to `20886.3`). A reader that commits the
displayed value on all 178 cells scores at most **174/178 = 97.8 % precision - below the 0.99 gate
- for being honest**. Its only escapes are abstaining on exactly those cells (unknowable from the
photo) or committing the cross-check product instead of the display (which the corpus's own
`pump-010` ruling forbids: "do not correct a value to make the cross-check close"). The oracle
already contains the repair - the display strings - but nothing consumes them at score time, and
`matches()` in the check script silently absorbs the same cases with a rounding tolerance, so the
two files disagree about what "correct" means. One adjacent note: the idle pumps `pump-016`/`017`
(CSV `0.00` liters+total) are *winnable* by committing zero - the B1 README calls that reward
backwards, yet under precision a committed `0.00` still counts as committedCorrect.

## 5. The `board` windows

130 board windows on 39 fixtures: 37 Wayne-family heads (the horizontal 4-cell grade row) plus
`pump-007`/`009` (Gilbarco RU **vertical** price lists - the y-spread is the column, correctly
annotated). No Gilbarco Circle K EE fixture carries board windows (no grade prices in frame).
Labelling convention as actually applied: on a Wayne row, the cell matching the transaction is the
`unitPrice` window and the other three are `board` (`pump-005`: boards at x 0.075-0.615, the
`52.56` unitPrice window at x 0.655-0.810, all four at y 0.810-0.900 - one row, four cells,
verified from the quads); where a dedicated transaction-price line exists (Gilbarco RU), all list
cells are `board` and the line is `unitPrice`. That is consistent - but it contradicts `_about`'s
definition ("board - a grade-price board cell that is **not the transaction price**"): `pump-007`
board[6] `76,24` and `pump-009` board[4] `050,95` ARE the transaction price. The definition needs
one line of repair, not the labels.

Four-cell completeness: every Wayne four-price head has all four cells (3 boards + in-row
unitPrice, or 4 boards where the price is off-board/blank) **except three**: `pump-021` (3 board
quads, all glare-blank, no unitPrice window - its same-station siblings `pump-022`/`023` carry 4,
and the extension render left of board[2] shows digit-shaped structure beyond the three quads:
probably a missing fourth cell); `pump-016` and `pump-017` (3 boards each, consistent across the
two independent shots of the same idle head - either a 3-grade head or the fourth cell hid under
glare; the extension renders show only blown-out regions where a fourth would sit). `pump-024`/
`025` are 3-cell by name and by CSV ("three-grade-prices", Neste) - correct. Idle heads carry no
unitPrice window and the CSV agrees (blank) - consistent.

Board strings have **no validator**: the check script scores only total/liters/unitPrice. That is
how `pump-009` board[6] could ship `072,80` against the README's `072,88` (finding 3 - measured:
last cell's centre-band density 0.34, identical to the same window's confirmed `8` at 0.34, against
`0` controls at 0.15-0.24 in the same and the sibling board). One more board pair deserves an
eyeball for the same reason: `pump-013` board `1.984` vs `pump-014` board `1.884` - adjacent
fixtures of one visit whose four-cell sets differ in exactly one digit (8<->9, the classic glare
confusion); both windows are too low-contrast (0.21/0.23) to settle by measurement. Boards are
excluded from the 178-cell gate but they ARE scored in the PU holdout numbers (113 of the 433
scored windows; 241 of the 1139 cells in PU.12's per-field dump), so board-string errors do move
the published metrics.

## 6. Rotation

`rotationCW`: `pump-019` = 90, `pump-020` = 90, `pump-021` = 270, `pump-022` = 270, `pump-023` =
270 - **five fixtures** (the brief says three; stale). Aspect census after correct geometry (image
rotated CW, quad points mapped CW, corners re-sorted): **all 456 strips have aspect > 1** (texted
minimum 1.40); the 23 rotated windows land at aspect 2.21-4.05. Under the shipped consumers'
geometry, all 23 come out **taller than wide** (0.247-0.718) - the brief's missed-rotation
heuristic fires on exactly these five fixtures and on nothing else. `pump-069` ("rotated90" in its
name) correctly carries no `rotationCW`: EXIF Orientation = 6 and `exif_transpose` uprights it;
its quads are wide in the transposed frame. EXIF census: no other fixture carries an orientation
tag; the five rotated ones genuinely need `rotationCW`.

**The annotation is right; every consumer is wrong.** Three independent facts:

- **The point mapping has the wrong sign.** `img.rotate(-90, expand=True)` moves content clockwise
  (verified numerically in-session: a mark at (5,4) in a 40x20 image lands at (15,5) = (H-1-y, x)).
  Points must therefore map (dx,dy) -> (-dy,dx). `score.py::rotate_points_cw` and
  `PumpQuadWarp.rotatePointsClockwise` (documented as "numerically identical", and they are)
  compute (dx,dy) -> (dy,-dx) - the counter-clockwise map. The polygons land at the mirrored
  positions: bbox IoU between the shipped and the correct polygon is **0.0 for 21 of the 23
  windows** (0.53 / 0.47 for `pump-019`/`pump-023` liters by coincidence of near-central quads).
  `score.py` therefore warps strips **from a different part of the photograph** for these windows.
- **The corner order is never re-sorted.** The JSON corners are physical EXIF-space TL,TR,BR,BL
  (verified on all 456; the tilted `pump-020` quads too). After any 90/270 rotation the list is a
  rotated permutation of the upright corners, so even with the sign fixed the warp's
  dst-corner correspondence (and `_quad_size`'s width/height) stay wrong. The Swift slicer path
  (`PumpReaderHarnessTests.slice` -> `loadRGB` = EXIF only, quad unrotated) never rotates at all
  and warps **vertical strips with the text running down the strip**; `PumpQuadWarp`'s header claim
  that "the homography un-rotates it" is false for a 90-degree image-space rotation with
  physical-order corners. `calibrate.py` multiplies unrotated quad aspects (0.25-0.7) with
  slices.json rects from those vertical strips.
- **The declared rotations themselves verify.** ASCII-reading the corrected strips: `pump-020`
  total at rot = 90 renders `0020,00` upright and readable (at 270 it renders structureless
  smear); `pump-021` total at 270 renders `15.00` upright with the decimal point low in the band;
  `pump-019` total at 90 shows six clean periodic cells (lag ~ pitch, ink width exactly 6.00
  pitch); comma/dp blobs sit at band bottom (centroidY 0.67-0.98) in the rotated frames - upright,
  not flipped.

Blast radius, since none of this is the oracle's fault but all of it consumes the oracle: PU.4's
`slices.json` cell rects for the 23 windows, the slicer count-agreement denominator (433), the
locator's corpus-median IoU (10 of the 12 rotated non-board texted windows score IoU 0 against
correctly-rotated locator candidates, the other two 0.47-0.53), every committed held-out number in
`REPORT.md` that says "all 433" (14 texted
rotated windows scored from wrong-region or vertical strips - free errors charged to the
classifier), and PU.12's real-cell aspect distribution (its min 0.24 lines up with these fixtures'
unrotated quad aspects of 0.25-0.72 - the vertical strips are in that population).
A fix needs one harness assertion to stay fixed: **every warped strip must have aspect > 1** - a
test that would have failed from the day `rotationCW` was introduced.

## Every window I would re-draw or re-type

| # | window | problem | evidence | action |
|---|---|---|---|---|
| 1 | `pump-003` total | string `20886.25` is the computed truth, not the display | 6 uniform runs at w/6 spacing, narrow last run (a `3`), low comma ink after cell 5, README says `20886.3` | re-type to `20886.3`; glyphCount 7 -> 6; becomes a display-rounding cell (section 4) |
| 2 | `pump-061` board[2..5] | quads ~1.2-1.5 cell heights LOW - they frame the gap above the discount row | strips contain no digit structure (board[4]/[5] bandFrac 0.20/0.15; board[2]/[3] mask-flooded to bandFrac 1.00 by the bright discount line, single fused run); shifting the quad up 1.2 x height renders readable `1.874`/`1.974`/`1.894`/`1.834` rows | re-draw the four quads; strings stand |
| 3 | `pump-009` board[6] | string `072,80`, display shows `072,88` | last cell centre-bar density 0.34 = the same window's confirmed `8`; `0` controls 0.15-0.24; README says `072,88` | re-type last digit to `8` |
| 4 | `pump-026` unitPrice | string `1924` drops the rendered comma | comma-blob ink after cell 0 (241 px, centroidY 0.77) = control `pump-028` `1,924` (280 px, 0.62); fixture named "comma-decimal" | re-type to `1,924` (dp-bit truth changes) |
| 5 | `pump-087` total (then `088`/`090`) | string `2049.0` likely missing the lit leading zero | w/6 run spacing with a digit-width run in the leading cell, discrete from the reflection wing; same fill as `pump-107` (6 lit cells, measured) | eyeball; if confirmed re-type to `02049.0` and settle `088`/`090` in the same pass |
| 6 | `pump-021` boards | 3 quads where siblings `022`/`023` carry 4 | digit-shaped structure in the extension left of board[2] | eyeball; add the fourth (blank-text) quad if the cell exists |
| 7 | `pump-016`/`017` boards | 3 cells on a Wayne head whose Circle K siblings show 4 | consistent 3 across two independent shots; wings glare-blown | eyeball once; if the head shows a fourth cell, add blank-text quads |
| 8 | `pump-013` board `1.984` vs `pump-014` board `1.884` | one digit differs between adjacent fixtures of one visit (8<->9) | contrast 0.21/0.23 - below measurement | eyeball both cells |
| 9 | `pump-020` unitPrice `1859` (with `pump-019` `1754`, `pump-032` `1759`, `pump-040` `1849`) | comma present but untranscribed? | `pump-020`: 246 px low gap ink (0.75) - weak; others inconclusive at contrast 0.11-0.22 | eyeball as one batch; `pump-011`/`012` `1789` verified comma-free, leave |
| 10 | `pump-074` total | display reads `1984,8`, CSV blank, nothing declares why | string internally consistent (29,00 x 68,44 -> 1 dp) | record the reason (a `csvDisagrees`-style key or README line) or score the cell |
| 11 | `pump-039` total | rm = 2.35 pitch: trailing cells below ink threshold | periodicity still spans the full width (corr 0.72) - faint ink, not a loose quad, most likely | eyeball; tighten only if the quad truly overshoots |
| 12 | `pump-008` total | lm = 3.29 pitch: quad frames the whole overlay banner, digits fill its right half | ASCII render; README documents the doubled value | decide: tighten, or document that overlay windows frame the banner |
| 13 | `_about` | "board ... not the transaction price" is false (`pump-007` board[6], `pump-009` board[4]); the three-state convention (no window = field not on display; empty text = window found, unreadable; leading spaces never transcribed) is implicit | section 5, section 3 | one-paragraph doc repair inside `windows.json` |
| 14 | consumers, not the oracle | `score.py::rotate_points_cw`, `PumpQuadWarp.rotatePointsClockwise` (+ no corner re-sort anywhere), harness `slice` path never rotating, `calibrate.py` | section 6 | new PU row: CW map + corner re-sort + rotate in the slicer path + aspect > 1 assertion; re-run `slices.json` and the held-out scores afterwards |

## Verdict: is the oracle good enough to measure a 0.99 gate?

**As the locator/slicer/string ground truth: yes, after a two-hour repair pass.** The quads sit on a
0.5 % grid (444 windows at 0.005, 12 at 0.001 - tighter than `_about`'s claimed ±1 %), are tight on
the ink vertically (band median 1.00) and horizontally (right margin median 0.00), carry an honest,
now-measured left-slack bias that matches the slicer's model of the world, and their strings
survive every measurement I can apply: of 433 texted windows, 1 transaction string is measured
wrong (`pump-003` total), 1 separator is missing (`pump-026`), 1 board digit is wrong
(`pump-009`), 1 padding inconsistency is probable (`pump-087`), 4 quads are misplaced
(`pump-061`), and a handful need one human eyeball each (table above). The 23 blank windows are
all genuinely structureless. The rotation data is correct - the pipeline misreads it, which is a
consumer bug with a build-failing test as its cure, not an oracle defect.

**As the arithmetic under the 0.99 gate: no - and this is the part that must change first.** The
gate compares against expected.csv at 0.005, and 4 of the 178 cells (2.2 %) hold values no honest
reader can produce: a perfect pump reader that commits everything caps at 97.8 % precision, and one
of the four (`pump-031`) is even declared in a file the scorer never opens. Until the scorer either
(a) consumes the display strings from `windows.json` for cells where display != CSV, (b) grows a
display-rounding tolerance for the truncated-total family, or (c) those cells move to a declared
unscored list - the gate measures a reader's willingness to guess receipts, not its precision. Fix
order: `pump-003` string (it is one of the four), then the scorer decision, then the table above,
then the consumer rotation fix before the next held-out re-score (its 14 texted windows are
currently charged to the model as free errors).

## What I would need to know or have (ranked)

1. **One human eyeball session, ~20 minutes, on the 12 window questions in the table above**
   (`pump-003` total, `pump-061` boards, `pump-026` price, `pump-087`/`088`/`090` totals,
   `pump-021` board count, `pump-016`/`017` board count, `pump-013` vs `pump-014` `1.984`/`1.884`,
   the four faint Gilbarco prices, `pump-039` total, `pump-008` total). Every one is a yes/no at the
   screen; my measurements have already narrowed each to a single question. This is the cheapest
   accuracy the oracle can still buy.
2. **A product-owner decision on the 4 precision-trap cells** (display-string channel vs rounding
   tolerance vs unscored declarations) - without it the 0.99 number is not measurable, whatever the
   annotations say. This decision owns a scorer change, not an oracle change.
3. **A second annotator on a stratified subset** - 30 windows: 10 board cells (no independent
   ground truth exists for board strings anywhere, and one is already proven wrong), 10 glare/blank
   or faint windows (the `legibility` vocabulary has exactly one use in the whole file), 10 rotated
   or Scheidt (fixed-cell grids make "what the display shows" a convention). What I want from it is
   an inter-rater string-error rate; one annotator + one reviewer found 3-4 string defects in 433
   (~1 %), and that estimate is the number every downstream metric inherits.
4. **A PU row for the rotation-consumer fix** (`score.py`, `PumpQuadWarp`/harness, `calibrate.py`,
   plus the aspect > 1 assertion and a `slices.json`/held-out re-run). Nothing in `docs/TASKS.md`
   owns it today; PU.11 reviewed the implementation and missed it, PU.12 reviewed the data and
   missed it - it is only visible from the annotation side, which is what this brief was for.
5. **Glyph-level boxes: not yet, and not broadly.** The oracle's jobs are locator boxes + strings,
   and it nearly does both. If cell-level boxes are ever funded (for slicer IoU rather than count
   agreement), spend them on the two places where cell boundaries are genuinely ambiguous: the 5
   rotated fixtures and the Scheidt fixed-cell heads (dark leading cells inside the quad - the
   `pump-089` case). Everywhere else a fixed w/N grid over a corrected quad reproduces the cells to
   within the annotation's own 0.5 % grid.
6. **The blank-cell policy, written down**: `pump-074` (legible display, blank CSV, silent) is the
   only cell of its kind; `_about` should say when a CSV cell stays blank while the window is
   readable, and what a scorer must do with a committed value there (today: invisible - the scorer
   skips blank-expected cells, so a wrong commit on an unscored cell costs nothing).
7. **Which Wayne heads are 3-grade?** One line in the pump README for `pump-016`/`017`/`021` would
   end the recurring "missing fourth cell" question either way.

## Checks run (exit codes and counts)

- `scripts/pump-windows-check.py --check` - exit **0**, "114 fixtures, 456 windows, 0 problems".
- `ml/pump-reader/.venv/bin/python ml/pump-reader/.out/review-ann/measure3.py` - exit 0, **456**
  window records in `metrics3.jsonl`.
- `analyze.py` - exit 0, full distributions in `analysis.txt` (sections 1-7 as cited).
- PIL rotation-direction probe (mark at (5,4) under `rotate(-90)` lands at (15,5) = the CW
  prediction; the shipped mapping predicts (4,34) and is wrong).
- No repo file was created or modified except this report; no Swift/Python source, fixtures, or
  docs were touched, so the standing build gates are not applicable to this change (nothing that
  runs is different). The concurrent ML run's uncommitted files were left alone.
