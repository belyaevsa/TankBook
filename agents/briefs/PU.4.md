# PU.4 - the digit slicer and the panel locator, in Swift (`TankbookCore/Extraction/PumpReader/`)

**Parent journey:** J4. **Row:** `docs/TASKS.md` → PU.4. **Authority:** `docs/EXTRACTION.md` → "The
pump reader". **Builds on:** PU.2's `Spike/ReceiptSpike/fixtures/pump/windows.json` (the oracle) and
PU.3's `ml/pump-reader/REPORT.md` → "Held-out score" (**read it first**: it shows, with a picture,
why the slicer is the whole difference between 12 % and a real number).

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios-pump-reader`:
`ios/Sources/TankbookCore/Extraction/PumpReader/` (new), `ios/Tests/TankbookCoreTests/PumpReader*.swift`
(new), and **one** Python file `ml/pump-reader/src/pump_reader/score.py` (add a `--boxes` input, see §4).
Nothing else in `ml/`, nothing in `ios/App/`, no `project.yml` change, no edits to `windows.json`
or `expected.csv`. Never `/tmp`; scratch is `ios/.build/pump-reader-out/`.

## Write code first, explore second

The slicer with its first test in the first fifteen minutes. The locator comes second and may
ship partial - the slicer is what unblocks the measurement.

## What already exists, so you do not rebuild it

- `windows.json` format (normalised [0,1] over the EXIF-oriented image; quad TL,TR,BR,BL; optional
  `rotationCW`; `text` is what the display shows, `,`/`.` = decimal point on the preceding glyph,
  leading space = blank cell; `field` ∈ total/liters/unitPrice/board; empty `text` = unreadable).
- `AccuracyRatchetTests.swift` shows how a package test finds `Spike/ReceiptSpike/fixtures` from
  `#filePath` and loads images through ImageIO (HEIC included) - copy that pattern.
- `PumpExtractor.swift` is the Vision-OCR pump parser. **Do not touch it**; the reader is a
  separate source alongside it.
- `swift test` baseline: **2117 tests in 259 suites** (Swift Testing) + 45 in 10 suites. Both must rise.

## What to build

### 1. `PumpGlyphSlicer` (the row the number depends on)

Input: a window image already warped to a straight strip (you write the warp: perspective from
the quad to a `H = 96` px strip, width proportional, via Core Image `CIPerspectiveCorrection` or
your own `vImage` homography - either, but one).

Algorithm, deterministic, no model:
1. Grayscale; **polarity** = decide dark-on-light (LCD) vs light-on-dark (LED/VFD) from the
   strip's median vs its 5th/95th percentiles; invert so ink is high.
2. Row-projection to trim to the glyph band (top/bottom margin removal).
3. **Column projection** → ink profile; smooth with a small box filter; threshold at a fraction
   of the profile's max to get ink runs; merge runs closer than a gap threshold.
4. **Fixed pitch**: seven-segment glyphs sit on a fixed advance. Estimate pitch as the median
   distance between run starts (ignore the narrowest runs - a `1` and a decimal point are
   narrow), then **snap** cells to the pitch grid so a `1` gets a full-width cell and a dp is
   assigned to the preceding cell rather than becoming its own. Leading blank cells: cells on the
   grid to the left of the first run, up to the strip's left edge.
5. Output `[GlyphCell]`: `rect` in strip coordinates, `hasDecimalPoint` (a narrow run sitting at
   the cell's lower right), `isBlank`.

### 2. `PumpPanelLocator` (may ship partial)

Input: the full oriented image. Output: candidate number windows as quads in normalised
coordinates, most likely first. Classical CV only: downscale to ~1024 px wide, local-contrast
normalisation, threshold, connected components, keep components whose bounding boxes are
horizontal (aspect 2:1 to 12:1), grouped into rows of similar height; a row of 3–8 glyph-sized
blobs at a common baseline is a window candidate. Do not spend the run polishing this - report
the corpus IoU honestly and stop.

### 3. `PumpReaderHarness` test (Swift Testing, `.visionMeasuredRuntimeOnly`-style opt-in trait
so CI without the fixtures skips)

For every fixture in `windows.json` with non-empty `text`: warp the annotated quad, slice, and
score:
- **glyph-count agreement**: `cells.count == glyphCount(text)` where `glyphCount` counts digits
  and leading spaces, not separators;
- **dp agreement**: the cell index carrying `hasDecimalPoint` equals the index of the digit
  before `,`/`.` (windows without a separator expect none).
Print a per-make table and the totals; assert **count agreement ≥ 0.80** of windows (a ratchet
constant in the test, moved only upward), and dp agreement ≥ 0.70.
For the locator: IoU of the best candidate against each annotated non-board window; assert the
corpus **median IoU ≥ 0.7** - if you cannot reach it, lower the constant to what you measured,
say so in the report, and PU.6 files the row.

### 4. Feed the classifier the real cells (`score.py --boxes`)

Write `ios/.build/pump-reader-out/slices.json` from the harness test: per fixture, per window,
the warped strip as a PNG path plus each cell's rect. Extend `score.py` with `--boxes
slices.json`: when given, it slices from those rects instead of the equal-width fallback. Then
run:

```
cd ml/pump-reader && .venv/bin/python -m pump_reader.score --model .out/train-2026-09-19/segmentnet.pt \
  --windows ../../Spike/ReceiptSpike/fixtures/pump/windows.json --fixtures ../../Spike/ReceiptSpike/fixtures/pump \
  --boxes ../../ios/.build/pump-reader-out/slices.json --dump .out/cells-pu4
```

and put the per-segment / per-glyph / per-window numbers in the report **next to** PU.3's
0.596 / 0.123 / 0.000. That pair of numbers is the deliverable.

## Tests you must add (each names its oracle)

1. `PumpGlyphSlicerTests`: a PU.1 row render (generate one with
   `ml/pump-reader/.venv/bin/python -m pump_reader.render --count 1 --seed 3 --rows --out
   ios/.build/pump-reader-out/synth` and read its `rows.json`) slices into exactly its box count
   with each cell centre inside the matching box. Oracle: PU.1's boxes. **Mutation named by this
   brief:** replace the pitch snap with raw runs (step 4 → skip) - the `1`-glyph fixtures
   (`pump-001`, `pump-063`, `pump-072`) must lose count agreement and the test must go red.
2. Polarity: an LED strip (light on dark) and an LCD strip (dark on light) from PU.1 profiles
   both slice to the same count. Oracle: the same input string.
3. Harness ratchet as in §3, with the constants.
4. Locator: on `pump-078` (clean, straight-on) the best candidate's IoU with the annotated `total`
   quad ≥ 0.5. Oracle: `windows.json`.

## Vacuous traps, named

- A count-agreement metric that counts separators as glyphs (it inflates agreement on every
  Gilbarco window).
- Snapping to a pitch estimated **including** the dp run - every pitch comes out short.
- A harness that silently skips fixtures it cannot load; print the skipped list and assert it is
  empty except HEIC on a platform without the codec.
- Asserting the locator's IoU on the union of candidates instead of the best single one.

## Out of scope

Row assignment, decimal recovery, the Core ML call from Swift, `PumpPhotoGate`, any change to
`PumpExtractor`, any retraining. Do not "fix" `windows.json`: if a quad is wrong, name it in the
report.

## Checks (by exit code)

- `cd ios && swift build` → 0; `swiftlint lint` **from the repo root** → 0 (from `ios/` it exits
  2 with ~5000 phantom errors).
- `cd ios && swift test` → 0, counts above the baseline, harness suite count non-zero (check the
  COUNT: a filter matching nothing prints 0 passed and exits 0).
- The app target does not change (no file under `ios/App/`), so `xcodebuild` is not needed for
  this row - say so.
- `cd ml/pump-reader && .venv/bin/pytest -q` → 0, still 14 (the `--boxes` change adds a test only
  if you change slicing behaviour without boxes - you must not).

## Standing fences

Never stash / `git checkout` / move files; never `git add` or commit. `pgrep -x` only. You are not
alone in the checkout. No `/tmp`.

## Report back

Exit codes (`echo $?`), test counts before/after, run-or-only-written per test, the red-then-green
output for the pitch-snap mutation, the harness per-make table, the locator median IoU (and the
constant you set), and the **before/after** scorer line (PU.3's 0.596 / 0.123 / 0.000 vs yours),
plus **anything you found and did not fix** - including any `windows.json` quad you believe is wrong.
