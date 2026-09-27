# RESEARCH-KNIFE-EDGE – why the pump reader flips on re-encoded copies of the same photo

*Product owner, 2026-09-27: "explore this divergence. Why? What might the reason of that? Why has
it happened?" Research only - the answer is a written explanation with evidence, not a fix.*

## Where you may write

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **READ-ONLY except one file:
`agents/research/KNIFE-EDGE.md`** (your note), and scratch files under `/tmp/knife-edge/` (yours to
create). No code changes, no commits, no builds of the app. You MAY run the prebuilt reader
binary `ios/.build/opt/debug/pump-read` (rebuild it only with
`cd ios && swift build --product pump-read -Xswiftc -O --scratch-path .build/opt` if it is missing).
Another agent or the orchestrator may be working in this checkout.

## Write first, explore second

Create the note's skeleton in the first minutes and fill it as you go.

## What was observed (2026-09-27, the orchestrator, macOS, `pump-read` default mode)

21 photos exist both as the phone's original HEIC and as JPEGs: 13 Live-Photo key frames
(`Spike/ReceiptSpike/fixtures/pump-live/live-6228.heic` ... `live-6262.heic`, each paired with a
corpus JPEG `pump-097`..`pump-114`, the pairing is in `scripts/corpus_db.py sql "select name,
paired_fixture from media where kind='keyframe'"`) and 8 corpus stills stored as HEIC
(`Spike/ReceiptSpike/fixtures/pump/pump-001.heic`, `pump-011..017-*.heic`). Each was read with
`echo '{"rotationCW":0,"currency":"EUR"}' | ios/.build/opt/debug/pump-read <image>` and scored
against `Spike/ReceiptSpike/fixtures/pump/expected.csv` (the `appCommitted` fields, tolerance 0.005).

Variants, all in `/tmp/knife-edge/` (named `<heic basename>.<variant>.jpg`): `srgb100` (Display P3
converted to sRGB with ImageCms, JPEG quality 100), `srgb92` (the same at 92), `raw100` (no colour
conversion, quality 100). The corpus JPEG is the fourth variant (no colour conversion, quality 92).
The raw results are `/tmp/knife-edge/res.json` (HEIC vs corpus JPEG) and `res2.json` (all variants).

| Variant | Filled | Right | Same reading as the HEIC |
|---|---|---|---|
| HEIC original | 47 | 36 | - |
| corpus JPEG (no conversion, q92) | 45 | 33 | 18/21 |
| sRGB q92 | 47 | 38 | 19/21 |
| sRGB q100 | 46 | 35 | 19/21 |
| no conversion q100 | 46 | 38 | 18/21 |

The same four photos flip, with no monotone relation to quality or colour: `pump-103`, `pump-111`,
`pump-113`, `pump-114` (key frames `live-6239`, `live-6259`, `live-6261`, `live-6262`). Example:
`pump-114` is 3/3 right from the HEIC, sRGB q92 and raw q100, but commits one wrong field from the
corpus JPEG and from sRGB q100. The other 17 photos read identically in every variant. A separate
test (68 heldout stills re-encoded JPEG q92 -> q75) moved only digit-level cells, never roles.

## The pipeline (read, do not change)

`docs/EXTRACTION.md` -> "The pump reader" and its amendments; code in
`ios/Sources/TankbookCore/Extraction/PumpReader/`. In order: EXIF-upright image -> RowSeg PixelLink
locator (`PumpRowSegmenter`: 512 input, pixel >= 0.9, link >= 0.8, confidence >= 0.9, union-find,
min-area rectangles) -> the display decision (`PumpDisplayCapture`: a fast path on >= 2 sized rows;
a **slow path with a wall-clock budget**, `slowPathBudget`, and a Vision text-line count) ->
geometry verifier (`PumpRowGeometry`, slicer `PumpGlyphSlicer` with percentile thresholds, pitch and
ink-band limits) -> role assignment (`PumpRowAssignment`) -> homography warp -> row reader
(`PumpRowReader`, CRNN+CTC) and the cell classifier (`PumpSegmentsModel`) -> the law
(`PumpReadingLaw`: nats thresholds, the ambiguity window, the currency conventions; since PU.100
`resolveAcrossCurrencies` and an `unclosed` warned read). Orientation search 0/90/270.

## Questions the note must answer

1. **Is it the image at all?** First rule out non-determinism: read the SAME file 5-10 times
   (HEIC and one JPEG of each of the four photos) and report whether the reading ever changes.
   The default mode runs the slow path under the app's wall-clock budget, so machine load alone
   may change the outcome; `pump-read --trace-serve` accepts `"budget"` (seconds) to lift it -
   read the four photos with the budget lifted in every variant and say whether the divergence
   survives. This is the most important question: answer it before anything else.
2. **Where does each flip happen?** For each of the four photos, trace every variant
   (`--trace-serve`, one JSON request per line: `{"image": ..., "currency": "EUR", "budget": 60,
   "outDir": "/tmp/knife-edge/<name>"}`; the reply carries orientation scores, each attempt's
   decision, candidates, verdicts, verified rows, roles, reads and the law) and name the FIRST
   stage whose output differs between the HEIC and a variant that reads differently.
3. **How close is the margin there?** Give the numbers at that stage: the threshold, the value
   on each side (a pixel/link probability, a row confidence, a slicer percentile, a CTC or cell
   log-likelihood, a law nats score, a timing against the budget). Is the reader sitting within
   a hair of a hard threshold on these photos, and which threshold?
4. **Why these four?** What do they share (make, framing, glare, a board cell near a transaction
   row, a digit near a segment boundary, a size near the fast-path rule)? Compare with a few of
   the 17 stable photos.
5. **What would make the reader stable, ranked** - each with what it changes (`file:line`), the
   cost on the phone (iPhone 12 floor), and the cheapest experiment that would falsify it: e.g.
   hysteresis or a margin band around the flipping threshold, abstaining when a decision is
   within the margin, test-time augmentation or multi-scale voting, taking the budget out of the
   correctness path, fusing Live frames (decision 2 in EXTRACTION.md). What must NOT be done: any
   change that trades a refusal for a confident wrong value (hard rule: a wrong number is worse
   than none).

## Evidence rules

Every claim cites a number you measured (with the command), a `file:line`, or a trace field; label
inference as inference. Report counts as counts over these 21 photos, never as corpus scores. Do
not quote a domain value from a log beyond what the fixtures already name.

## Report back

The note's path, the answer to question 1 in one line, the first-divergent stage per photo, the
margin found, and the ranked stabilisers in two lines each.
