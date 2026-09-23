# REVIEW-PUMP-QWEN – an outside review of pump-display recognition

**You are a reviewer. This is READ-ONLY.** Change no file in the repo, train no model, write no
model file, commit nothing. Build and run tests only if you need a number that is not written
down, and say that you did. **Exactly one file is yours to write:** `agents/reviews/PUMP-REVIEW-2026-09-23-qwen.md`.

**Who asked, and why (product owner, 2026-09-23):** the goal is still the one set on 2026-09-22 –
*"improve the recognition of pump's photo, lift it and make it faster."* A previous whole-story
review exists (`agents/reviews/PUMP-DECIDE-2026-09-22-fable.md`). This one is a second, independent
look: read it, but you do not have to agree with it, and your answer must stand on its own.

This brief deliberately proposes **no solution**. It describes the problem, the pipeline as it
is, what has been measured and what has been tried. Deciding what to do is your job.

## The problem

A user photographs the fuel pump's display (no receipt – journey J4, `docs/JOURNEYS.md`) and the
app must pre-fill **litres, unit price and total** on the Confirm form. The display is almost
always seven-segment digits (LCD, LED or electromechanical), under glare, reflections, behind
scratched plastic, at an angle, often among printed labels, prices boards and stickers. A
pre-fill is a default the user edits (hard rules 13 and 15 in `CLAUDE.md`), but a **wrong**
pre-fill the user waves through is the most dangerous failure the app has (F2 in
`docs/JOURNEYS.md`), so precision matters more than coverage: the verified tier ships under a
**0.99 precision floor**.

Constraints that shape any answer:
- **On-device and local-first** (hard rule 1). A cloud path exists (`/extract`, the LLM gateway,
  `docs/API.md`), but a feature may not *require* the network.
- **iOS 18.0 deployment target, iPhone 12 floor** (`docs/VISION.md`). Core ML, Vision, Accelerate
  and Metal are available; any native code ships inside the app (Swift, C, C++ are all possible
  in the SwiftPM package `ios/Sources/TankbookCore`).
- **No secrets in the bundle** (hard rule 11), privacy rules for logs (hard rule 12).

## The pipeline as it is today

App entry: `PumpDisplayCapture.classify` (`ios/Sources/TankbookCore/Extraction/PumpReader/PumpDisplayCapture.swift`).
It decides first whether the frame is a pump display at all (fast path on the detector's own
rows, slow path on Vision text lines), then reads. Stages, in order:

| # | Stage | Where | What it is |
|---|---|---|---|
| 1 | Row detector | `PumpRowDetector.swift`, model `ml/pump-reader/.out/det/DigitRows.mlmodel`, trained by `ml/pump-reader/detector/train.swift` (Create ML object detection) | proposes **upright** rectangles around rows of large digits |
| 1b | Vision proposer | `PumpVisionProposer.swift`, `PumpPanelLocator.swift` | a fallback locator from Vision text/character boxes |
| 2 | Verifier | `PumpRowGeometry.swift` | model-free: keeps a row on cell count, pitch, ink band, width, keypad shape; drops with a named reason |
| 2b | Deskew (off in the app) | `PumpRowDeskew.swift` | row angle from the sharpest row-brightness profile; modes `.off/.onRefusal/.always/.level` |
| 3 | Role assignment | `PumpRowAssignment.swift` | which row is litres, price, total (and board cells) |
| 4 | Slicer | `PumpGlyphSlicer*.swift`, `PumpQuadWarp.swift` | cuts a row into glyph cells: pitch, blanks, decimal point |
| 5 | Classifier | `PumpSegmentsModel.swift`, model `ios/App/Resources/PumpSegments.mlpackage` (shipped = `train-r6-real`), trained by `ml/pump-reader/src/pump_reader/` | per cell: 7 segment sigmoids + decimal point |
| 6 | The law | `PumpReadingLaw.swift`, `PumpReadingTypes.swift` | decodes candidates and commits only when `litres × price = total` closes uniquely; a price-less pair tier (decision 11) commits total + litres when a shown price validates the implied one |
| – | Video frames | `PumpVideoFrameRead.swift`, `PumpFrameFusion.swift` | multi-frame read (not on the photo path) |

Wiring into the app: `ios/App/Sources/Capture/CapturePipeline.swift` (the rules receipt parser
fills a field the reader refused), `ios/App/Sources/ConfirmManual/` (the form),
`ios/Sources/TankbookCore/Config/PumpPhotoGate.swift` (the ship gate and its constants).

Measurement and tools: `ios/Tests/TankbookCoreTests/PumpReaderPipelineTests.swift` (annotated and
live floors), `PumpDisplayCaptureTests.swift`, `PumpReadingLawTests.swift`,
`ios/Sources/PumpReadTool/main.swift` (per-photo JSON: candidates, drop reasons, app decision,
timings), `tools/pump-annotate/` (the owner's annotator and compare view). Corpus:
`Spike/ReceiptSpike/fixtures/pump/` (`expected.csv`, `windows.json` hand quads, heldout split per
decision 9).

## What is measured (read, do not re-derive unless you doubt it)

On the **68 heldout stills, 183 numeric cells**:

| Path | Committed | Correct | Precision | Photos all right |
|---|---|---|---|---|
| Live – the app's `classify`, today | 45 | 45 | 1.000 | 15/68 |
| Live with deskew `.onRefusal` (measured, not enabled) | 54 | 54 | 1.000 | – |
| Annotated – hand quads, read stage only | 111 | 110 | 0.991 | 33/68 |

The funnel apportionment (PU.64, `docs/TASKS.md` and `ml/pump-reader/REPORT.md`): oracle 108 →
cells in a detected row 95 (−13) → kept by the verifier 78 (−17) → **the detector's framing 45
(−33)**; the same stills read from hand bounds drawn as upright rectangles commit **89 at 0.944**.
So the largest single loss is how the detector frames a row, not whether it finds it.

Other measured facts:
- **Role assignment** sat at **0.989** against a 0.99 floor after the corpus doubled (PU.60).
- The **unvalidated pair** (total + litres with no shown price near the implied one) was built as
  a cautioned commit (PU.59) and measured on the app path at **1 correct cell of 10** –
  pump-019, -032, -104, -120, -125, mostly rows given the wrong role. It was **held**, not
  shipped; unvalidated pairs abstain. The shown-price-differs caution (PJ.500) shipped.
- **Detector retrains** (PU.48, PU.66 rounds 1–3, including rotated and hand-only training sets)
  were all **refused** under decision 10's tight-IoU gate: best round median IoU 0.790, but
  wrong readings; seven detector candidates are tabulated in the PU.66 row.
- **Tilted stills** (20 of them): 0 committed at `.off`, 3 at `.onRefusal`; levelling the whole
  photo adds 0 on the app path (rows too small after rotation – widest 0.10 against a 0.18 rule).
- **Receipt leak**: 5 of 116 non-pump photos are routed as a pump display (unchanged).
- **Latency** (Release, device, `REPORT.md` → "decision ms"): pump decision 13–73 ms,
  `classify` + read 112–164 ms. Debug `swift test` numbers are 7–25× slower and are not latency
  facts. The live test path takes ~510 s for 68 stills in Debug on a Mac.
- Composite (reader + rules parser) gate constants are only measurable on macOS 26.

## Read these

1. `docs/EXTRACTION.md` → "The pump reader" in full, all eleven numbered decisions with their
   amendments (decision 11 now carries a "Measured before shipping, and held" note).
2. `ml/pump-reader/REPORT.md` (2259 lines, the round-by-round ledger) and `CORRECTIONS.md`.
3. `docs/TASKS.md` – every `PU` row (index first, then the rows) and `PJ.500`.
4. `agents/reviews/PUMP-DECIDE-2026-09-22-fable.md`, `PU.52-REVIEW-WHY-IT-LOWERED-qwen.md`,
   `PU.32-REVIEW-STEP-CHANGE-*.md`, `PU.14-REVIEW-DECODE-DESIGN.md`.
5. The code under `ios/Sources/TankbookCore/Extraction/PumpReader/` (18 files, ~4.4k lines), the
   training code under `ml/pump-reader/`, and the measurement files named above.
6. `CLAUDE.md` hard rules 1, 11, 13, 15; `docs/JOURNEYS.md` J4 and F2; `docs/DEFECT-PATTERNS.md`.

## Answer these five questions

1. **Evaluate the current solution** – the approach and architecture as a whole: a learned row
   detector, a model-free verifier, a geometric slicer, a per-cell segment classifier and an
   arithmetic law. What does it get right, where is it structurally limited, and does the
   evidence above support that judgement?
2. **Evaluate the implementation** – the code and the training/measurement machinery as written:
   correctness, robustness, numerical choices, hidden coupling between stages, what the tests do
   and do not prove, and anything that makes the measured numbers misleading.
3. **Other options worth exploring** for the issues we already know: detector framing, role
   assignment, tilt and rotation, glare and low contrast, the receipt leak, the price-less pair.
   For each, what it would take and how it would be measured on this corpus.
4. **Drastic improvements** – changes to the pipeline or architecture that could move the
   end-to-end number by a large step rather than a round, including restructuring or replacing
   stages. Say what each would cost and what would falsify it.
5. **Research that helps, down to the low level** – published work (papers, well-known
   algorithms, open implementations) that could make the logic more precise and faster, including
   at the level of a custom native (C/C++/Metal/Accelerate) package inside the app: e.g. line and
   angle estimation, rectification, segment-display reading, text/row detection, constrained
   decoding, calibration and abstention. **Cite each with title, authors, year and a link, and say
   whether you verified it exists.** A made-up or misattributed reference is worse than none; if
   you are unsure, say so.

## How to argue

Every claim cites a file and line, a fixture name, or a measured number. Separate evidence from
inference and label inference as such. Rank within each question, and for every recommendation
say which goal it serves – **precision, coverage (committed cells, photos all right) or speed** –
and where those trade against each other.

End the review with **"If I could do exactly three things"**, in priority order, one sentence each.

**Fences:** read-only; one output file; no commits; no edits to `docs/`, code, models or corpus
(`Spike/ReceiptSpike/fixtures/` is the owner's annotation work and is being edited live). Another
session works in this checkout at the same time, so the tree may change under you – that is
expected; do not revert anything.

**The standing fences appended below were written for build briefs.** Their "where you may write"
and "never stash/checkout" rules apply to you; their standing checks (`scripts/gate.sh`, the
UI suites, screenshots) do **not** – you change no code, so do not run the gate. A verification
run of the orchestrator may be using the simulator and the build directory while you work.
