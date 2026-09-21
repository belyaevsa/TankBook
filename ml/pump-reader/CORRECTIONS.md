# Using the operator's corrections to improve the reader

The annotator writes `Spike/ReceiptSpike/fixtures/pump-live/corrections.jsonl`: one line per
field the operator changed against a tool's proposal, with the build the proposal came from
(`tools/pump-annotate/README.md` → the corrections ledger). Nothing is written for a field left
as proposed, so the ledger is the set of **disagreements between the tools and a human** – the
most valuable rows the corpus has, and the only ones that name where a tool is wrong today.
This is the instruction for turning them into improvements. It is a standing procedure, run at
the start of every reader round (classifier, slicer, tracker or locator), before deciding what
that round changes.

## 1. Read the ledger before choosing the round's lever

    scripts/corrections-report.py              # everything
    scripts/corrections-report.py --since 2026-09-21

Three sections come out; each points at a different tool, and the counts say which one the
round should be about:

| section | what it measures | the tool it indicts | the round it feeds |
|---|---|---|---|
| **Tracker** – IoU of the tracked quad vs the hand-placed one, per record and make | how far the homography drifted before a human fixed it | `pump_reader.track` | a tracker round (anchors, registrar features, plausibility) |
| **Reader pre-fills** – *mark or leading zero only* | the digits were right, the mark or a blank position was not | `PumpGlyphSlicer` | a slicer round |
| **Reader pre-fills** – *digits differ* | a cell read as the wrong digit, or the count was wrong | classifier (or the slicer's count) | a classifier round – with these frames weighted |
| **Tracking verdicts** – `bad` | the record was not usable at all | capture or tracker | the shoot list, or a tracker round |

A round's brief names the section that motivated it and the count it starts from. A round that
does not move its own section's count on the *next* ledger window did not work, whatever the
heldout says.

## 2. What the corrections are, and are not, allowed to do

- **They are diagnosis, never the yardstick.** The heldout split (`pump/split.csv`, decision 9)
  stays the only number a change is judged by. Corrected frames are where to *look*; a
  threshold tuned until the corrected frames pass is a threshold fitted to the diagnosis set,
  which is the mistake `PumpReaderHarnessTests`'s history records. Change a constant only with a
  geometric reason, then read the heldout.
- **A correction on a heldout still or its record refines the truth, it is not training
  data.** The record's `_split` decides: heldout records' corrections update the quads/texts the
  harness scores against (that is the annotator's normal job) and go nowhere else.
- **A correction on a train still, frame or video is a hard example** and is the one thing the
  training export should weight (§3).
- **Never log domain values outside the corpus.** The ledger lives in the corpus and carries
  amounts by design; it must not be copied into a log, a brief, or a doc outside
  `Spike/`/`ml/` (hard rule 12 governs the app and its telemetry; the corpus is the one place
  the values belong).

## 3. Classifier rounds: weight the hard examples

`pump_reader.realglyphs` cuts real cells from every labelled train window and frame with equal
weight, which is how 15 easy fixtures came to be 93 % of the real cells (REPORT.md, round 10).
The ledger's *digits differ* rows name the frames the shipped classifier got wrong; those are
the cells a retrain must see more of. The procedure:

1. `scripts/corrections-report.py` → the hard-example list (video/still + frame).
2. Export the train slices as usual (`PUMP_TRAIN_EXPORT=1 PUMP_TRAIN_EXPORT_VIDEOS=1 swift test
   --filter PumpTrainSliceExportTests`), then cut cells with the hard frames up-weighted:
   `python -m pump_reader.realglyphs --also ../../ios/.build/pump-reader-out/train/train-videos.json
   --hard <path-to-corrections.jsonl> --hard-weight 4` – a hard frame's cells appear four times in
   the sampler's pool (the option is the round's to add if it does not exist yet; keep the weight
   a command-line number, never a constant in the code).
3. Cap any single fixture's share of the real pool (the same round's other lever) so the weighted
   hard frames do not become the new skew.
4. Three seeds (round 10's protocol), scored with `PUMP_MODEL=` on the heldout; the round ships
   only if all three clear the floors and the annotated tier moves by more than seed noise
   (±2 cells).
5. Write the before/after of the *digits differ* count on the next ledger window into REPORT.md
   beside the heldout numbers.

## 4. Slicer rounds: the mark-or-zero rows are the fixture list

A *mark or leading zero only* row means the classifier read every digit and the slicer lost the
mark or a blank position. Each such frame is a slicer regression case:

1. Dump its strip: `ios/.build/debug/pump-read <frame> --dump-strips <dir> < request.json`
   (request: the frame's quads from its tracked `windows.json`) and look at it.
2. Reproduce with a synthetic strip in `PumpGlyphSlicerTests` (the dot's size and position, the
   band's contrast) – the real frame is the evidence, the synthetic strip is the test, so the
   test does not depend on the corpus being checked out.
3. The measurement is `PumpReaderHarnessTests`'s dp agreement and count agreement on the
   heldout, never the corrected frames.

## 5. Tracker rounds: the IoU histogram is the ratchet

The tracker has no ratchet of its own; the ledger's IoU histogram is it. A round that touches
`track.py` reports the histogram before and after over the same records (re-run the tracker on
the corrected records with the anchors *removed*, compare to the anchors – the anchors are the
truth the tracker is measured against). A make whose mean IoU sits under 0.7 with several
corrections is a tracker problem on that head (a reflective bezel, a display that changes
between frames), not an operator problem; a single low record is an anchor away from fine.

## 6. Locator rounds: which frames the detector never proposed

A `text` correction on a frame the live path could not locate says nothing about the locator;
but a `quad` correction whose IoU is low on a *still* (not a frame) is a hand quad the detector
was trained on and drew badly – the detector round's `detdata` set is exactly the stills' quads,
so a corrected still quad is a corrected training box. Re-run `detdata` and `measure.swift`
after a batch of still-quad corrections; recall@0.7 is the number that should move.

## 7. Regression across builds

Every line carries `build`. Corrections rising on frames that a previous build read right is a
regression that no ratchet caught (the heldout is 64 photos; the ledger is every frame the
operator touched). `scripts/corrections-report.py` groups the reader rows per build; compare
consecutive builds before shipping a classifier or slicer change to the bundle.

## 8. Hygiene

- The ledger is committed with the corpus, appended only, never edited by hand; a wrong line is
  corrected by the next save, which writes a new line.
- `scripts/corpus_db.py build` folds it into `corpus.sqlite` (table `corrections`) – queries
  across frames, makes and builds are easier there than in the JSONL.
- When the corpus moves to SQLite as its write store (filed as CO.x), the ledger becomes a table
  written by the same routes; this document does not change.
