# KNIFE-EDGE: why the pump reader flips on re-encoded copies of the same photo

Research note, 2026-09-27. Research only - no fix. Counts below are over the 21 dual-format
photos, never corpus scores.

## Setup

- Reader: `ios/.build/opt/debug/pump-read` (prebuilt, `-O`).
- Traces: `echo '{"image": ..., "currency": "EUR", "budget": 60, "outDir": ...}' | pump-read --trace-serve`,
  one per photo x variant (20 runs), in `/tmp/knife-edge/tr/<variant>.json` with strips in
  `/tmp/knife-edge/tr/<variant>/a0-v*.png`.
- Slicer math replication (exact `percentile`/`boxFilter`/`otsuThreshold` ports from
  `PumpGlyphSlicer+Primitives.swift`): `/tmp/knife-edge/replicate.py`, run against the dumped strips.
- Four flippers: pump-103 (live-6239), pump-111 (live-6259), pump-113 (live-6261), pump-114 (live-6262).

## Q1: Is it the image at all?

**Yes - it is the image, not noise, and not the budget.** The reader is bit-for-bit deterministic
per input file.

- 10 repeat reads of each of the four HEICs (`echo '{"rotationCW":0,"currency":"EUR"}' | ios/.build/opt/debug/pump-read <heic>`,
  outputs `/tmp/knife-edge/q1/`): exactly 1 distinct full JSON output (minus `timingsMs`) per photo.
- 10 repeat reads of each of the four corpus JPEGs: likewise 1 distinct output per photo.
- 5 repeat reads of `pump-114...jpg` under 8-way `yes` CPU saturation: 1 distinct output, identical
  to the idle-machine reading.
- Budget: all four photos take the **fast path** (`attempts[0].detection.path = "fast"` in all 20
  traces), where the wall-clock budget is never consulted: `decideAt` returns from the fast verdict
  at `ios/Sources/TankbookCore/Extraction/PumpReader/PumpDisplayCapture.swift:211-220`, *before* the
  deadline is created at line 224 (`budgetHit` is set only on the slow path, lines 224-234), and the
  fast path's own verify (`readDecision`, lines 387-395) is called with no deadline. Empirically,
  `--trace-serve` at `"budget": 60` reproduces the default-mode (1.5 s, `slowPathBudget`,
  PumpDisplayCapture.swift:110) outcomes on all 20 pairs.
- Reading subtlety: default-mode `appCommitted` is `reading.extraction`, which carries the
  **unclosed top read** when the law commits nothing (PumpDisplayCapture.swift:426-433, flagged
  `appUnclosed: true`). Every "wrong value" in the orchestrator's table is such an unclosed read -
  see "What actually diverges" below.

## Q2: Where each flip happens

In all four photos the RowSeg locator is stable across variants: detector confidences move by
<= 0.0004 and quads by <= 0.005 of the frame (one outlier: 0.30 on live-6259-srgb100's second row,
a re-oriented rect for the same row, which still verified and read correctly). The first stage
whose *decision* differs is the **geometry verifier's slicer verdict**
(`PumpGlyphSlicer` + `PumpRowGeometry.verdict`, called from `PumpReader.verify`), in every case on
exactly one row:

| photo | row | HEIC | flipping variants | check that flips |
|---|---|---|---|---|
| pump-103 (live-6239) | unitPrice row (v2) | 4 cells, kept | corpus JPEG: 3 cells, dropped | `pitch` |
| pump-111 (live-6259) | liters row (v1) | 6 cells, dp on cell 1, dropped | srgb92/srgb100/raw100: dp on cell 3, kept | `decimalMark` |
| pump-113 (live-6261) | top (total) row (v0) | layout D BB DDD, dropped | corpus JPEG: layout B DDDD, kept | `blankLayout` |
| pump-114 (live-6262) | total row (v0) | 8 cells, kept | corpus JPEG + srgb100: 9 cells, dropped | `cellCount` |

The downstream cascade is the same shape in every case: one row in or out of `verified` changes
`PumpRowAssignment`, which assigns the transaction column **purely positionally, top-down**
(`PumpRowAssignment.swift:118-124`: two surviving rows get `[.total, .liters]` regardless of what
they are). A dropped top row shifts every surviving row one role up; an admitted row shifts them
down. The mislabeled reads then reach `PumpReadingLaw`, which refuses every one of them:

- pump-103 JPEG: price row gone, total+liters read correctly, law `priceUnvalidated`, committed 0.
- pump-111 HEIC/JPEG: liters row gone, the 4-cell price row becomes "liters" and reads 1.999;
  law `priceOutOfBand` (100.87 / 1.999 implies ~50.4 EUR/l), committed 0.
- pump-113 JPEG: top row kept and read 10.51 (correct total), price row becomes "liters" = 2.014;
  law `priceUnvalidated`, committed 0. HEIC and the other variants keep only the price row, which a
  single-row column labels `liters` (PumpRowAssignment.swift:120): unclosed liters = 2.014.
- pump-114 JPEG/srgb100: total row gone, the 6-cell liters row becomes "total" = 69.87; law
  `priceOutOfBand`, committed 0.

**The law committed a wrong value in none of the 20 runs.** Every observed flip is one of: a field
dropped (benign), or a mislabeled value inside the *unclosed top read* that reaches the form under
the `.unclosed` caution. That is still user-visible: pump-111 shows "liters 1.999" and pump-114
shows "total 69.87", both wrong fields, both warned.

## Q3: The margins

All four checks sit a hair from their limits (verdict bounds: `PumpRowGeometry.swift:50-74`,
slicer options: `PumpGlyphSlicer.swift:35-109`):

1. **pump-103, pitch.** The corpus JPEG's autocorrelation gains a local peak at lag 61 that the
   HEIC does not have; the pitch-to-body guard doubles it to 122 px against a 96 px band:
   pitch/band = **1.271 vs limit 1.25 - 1.7 % over** (`maximumPitchToBand`,
   PumpRowGeometry.swift:51). The other four variants: 82/96 = 0.854. The underlying runs are
   near-identical across variants (my replication: identical run list except one endpoint moving
   1 px); what moves is the autocorrelation's first-local-peak-within-60 %-of-max choice
   (`autocorrelationPitch`, PumpGlyphSlicer+Primitives.swift:35-40, `harmonicTolerance` 0.6 at
   line 45) - a discrete argmax over a nearly flat curve (top lags 81-82 at 0.161-0.163 vs the max
   0.174 at lag 144 in the HEIC, per `/tmp/knife-edge/replicate.py 6239`).
2. **pump-111, decimalMark.** HEIC/JPEG: a phantom mark blob in the gap after the first digit,
   dp on cell 1 of 6 -> implied 4 decimals > `maximumDecimalPlaces` 3 (PumpRowGeometry.swift:68,
   95-98). srgb92/raw100: dp on cell 3 (the true one in "0050.46"), kept. The mark pass threshold
   is 0.5 x the Otsu run threshold (`markThresholdFraction`, PumpGlyphSlicer.swift:54; search in
   `PumpGlyphSlicer+Marks.swift:67-114`). Replicated mark-pass profile maxima per inter-digit gap
   (`replicate.py 6259`): the phantom gap sits at 1.86-1.87 vs threshold 1.48-1.49 (~25 % over) in
   HEIC and corpus JPEG; srgb92 raises the threshold to 1.58 and moves the blob geometry. The true
   mark's gap measures 1.28-1.41 against those same thresholds - i.e. the true mark and the phantom
   straddle the threshold from opposite sides, and a +-5 % perturbation swaps which one is seen.
   (Replication is a faithful port of the primitives but not bit-exact against the slicer's float
   path; treat these two numbers as approximate. The dp indices per variant are exact trace data.)
3. **pump-113, blankLayout.** The total row's leading edge carries faint ink at strip x 0-2
   (profile 2.8/2.2/1.8). HEIC Otsu threshold 1.62 -> run exists -> the first cell is occupied and
   the two following empty cells become an interior blank run of 2 > `maximumInteriorBlankRun` 1
   (PumpRowGeometry.swift:74, 99-101) -> dropped. Corpus JPEG: the warp shifts (quad moves 0.004),
   the strip gains contrast (profile max 6.85 vs 4.25), Otsu rises to 2.61, the same edge ink
   (2.4/2.0/1.8) falls *under* it -> the cell becomes a margin, layout B DDDD, kept. The deciding
   peak sits between the two thresholds: **the threshold itself moved 60 % with the re-encode**
   while the signal barely changed.
4. **pump-114, cellCount.** The total row "0144.91" slices to 8 occupied cells in HEIC/srgb92/
   raw100 and 9 in the corpus JPEG and srgb100; 9 > `maxCells` 8 (PumpReadingLaw.swift:458) ->
   `cellCount`. The 9th cell is one trailing pitch slot whose faint ink (~2.0-2.4 against an Otsu
   threshold of 2.34-2.53 that itself moves per variant) crosses the run/dim-recovery cut in two
   variants and not the other three (`replicate.py 6262`; the recovery pass works at 0.5 x Otsu,
   `dimGlyphThresholdFraction`, PumpGlyphSlicer.swift:90). One cell of nine.

So: yes, the reader sits within a hair of a hard threshold on these photos - and the threshold in
question is a different one each time (pitch ratio, decimal-place count, blank-run count, cell
count), all four downstream of one shared mechanism: **the slicer's hard, discrete decisions
(a run exists or not, a blob is a mark or not, a cell is blank or not) on continuous quantities
that JPEG re-quantisation perturbs by 1-2 gray levels.** The Otsu threshold moves with the encode
too, so signal and threshold shift in opposite directions (pump-113) or independently.

## Q4: Why these four

Not the detector, not the CNNs: confidences and per-cell log-posterior margins on the kept rows are
healthy on both sides of every flip (e.g. pump-114's surviving rows read at margins 5.7-20.5 nats).
Not the pump family alone: the flippers are all Gilbarco CircleK EE, but so are stable pump-101,
102, 104, 105, 112. What the four share, measurably, is **one weak feature on one row**:

- pump-103: the unit-price row is the dimmest strip in the set (Otsu 0.51, profile max 1.84; the
  kept read's mean cell margin 0.65-0.73 nats is the lowest kept row in all 20 traces).
- pump-111: the liters row carries a decimal mark whose gap profile (1.28-1.41) is weaker than a
  phantom speck in another gap (1.86) - the true feature and the noise are the same strength.
- pump-113: the total row's leading digit is faint/cut at the strip's left edge (ink peak 2.4-2.8
  vs digit peaks ~6).
- pump-114: faint trailing ink past the last digit, one pitch slot wide.

Compare the stable photos (live-6228 and live-6242 traced as controls): every row lands far from
every limit - pitch/band 0.57-0.69 (limit 1.25), 4-6 cells (limit 8), no interior blank runs, marks
where expected, mean margins 1.2-4.8. The 17 stable photos have no feature near any of the four
cuts; the four flippers each have exactly one. The flip direction is random because the perturbation
(JPEG DCT re-quantisation, +-1-2 gray levels after LCN) is unrelated to which side of the cut the
feature sits on - hence no monotone relation to JPEG quality (q100 flips pump-114, q92 does not)
and no effect from the P3->sRGB conversion per se.

## Q5: What would make the reader stable, ranked

1. **Admit borderline rows to the law instead of dropping them at the geometry verdict.** The
   verdict is binary; the law is the smooth, redundant check (arithmetic closure + currency band),
   and in all 20 runs it already refused every misassigned reading. Change: in `PumpReader.verify`
   (the `PumpRowGeometry.verdict` call site), a candidate failing *exactly one* check by a small
   epsilon (pitch <= ~1.35, cells == 9, blank run == 2, one extra implied decimal) is read anyway
   and offered to the assignment/law as a lower-priority row, never displacing a fully-passing row.
   Cost: at most a couple of extra row reads; the whole classify+read of these photos is 0.6-1.2 s
   on this Mac with reads at ~13 ms (`timingsMs`), so the phone cost is small against the 3 s
   budget. Falsify: replay the 21 photos x 5 variants plus the 68 heldout stills with the admission
   on; expect all five variants of each flipper to agree, and zero new committed-wrong fields.
2. **Strip-level test-time augmentation on borderline rows only.** When a row's verdict margin is
   small, re-slice the same quad at +-1 px / a second strip height and keep the row only if the
   layouts agree (cell count, blank runs, dp position). Cheap: the slicer is pure arithmetic on a
   ~370x96 strip. Falsify: apply +-1 px quad jitter to the 20 traced pairs in the harness; the four
   flipped rows should flip under jitter and be excluded, making every variant agree with the HEIC.
3. **Live-frame fusion (decision 2 in docs/EXTRACTION.md).** These are Live-Photo key frames with
   the `.mov` beside them; a per-frame knife edge is outvoted by the other frames. Cost: several
   reads per capture on the iPhone 12 floor - the largest of the three. Falsify: read 5-10 frames
   from each of the four `.mov` files and count per-frame disagreement; if the flips are
   frame-local, fusion fixes all four.
4. **Margin telemetry in the trace.** Carry each check's distance to its limit (pitch - 1.25,
   cells - 8, blank run - 1, mark mass / threshold) in `PumpTrace`/`PumpTraceJSON.swift`, so a
   corpus run can rank photos by knife-edge-ness instead of discovering flips by re-encoding.
   Not a stabiliser by itself; it is what makes 1-3 measurable per release.

Not implicated, deliberately: **the wall-clock budget.** All four photos decide on the fast path
where no deadline exists (Q1). The slow path's deadline (`PumpDisplayCapture.swift:224-234`) is a
real nondeterminism source for detector-abstaining frames, but none of these four photos is one.

Must NOT be done: loosening the four bounds globally (maxCells 9, pitch 1.3, blank run 2, four
decimals). They are train-split false-positive cuts (PumpRowGeometry.swift:14-18); loosening admits
receipt and keypad rows, and once a junk row enters the transaction column the positional
assignment (PumpRowAssignment.swift:118-124) cascades every role. A refusal costs the user two
typed fields; a committed wrong value is the failure hard rule 15 and the law exist to prevent.
The current evidence says the backstop holds: 20/20 runs, zero committed-wrong values; the worst
observed outcome is a mislabeled *unclosed* top read shown under the caution.
