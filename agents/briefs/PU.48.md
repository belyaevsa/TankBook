# PU.48 - Retrain the row detector on this week's records

Row: `docs/TASKS.md` -> PU.48. The detector is PU.33's (`ml/pump-reader/REPORT.md` -> PU.33).

## Where you may write

`ml/pump-reader/.out/det/` (the export and the candidate models), `ml/pump-reader/REPORT.md` (a
dated "PU.48" section), `ml/pump-reader/src/pump_reader/detdata.py` ONLY if the builder needs a
fix to read the current database (say what), `ml/pump-reader/tests/` (a test for the builder),
`ios/App/Resources/DigitRows.mlmodel` ONLY when the gate in (d) passes, and then
`PumpReaderPipelineTests.swift`'s live floor comment. Nothing under `Spike/` - read only.

## What exists (read first, in order)

1. `REPORT.md` -> PU.33: how the detector was built (`pump_reader.detdata`, `detector/train.swift`,
   `detector/measure.swift`), its numbers (rows found on 59/64, every row on 49/64, recall 0.86 @
   IoU 0.5, 0.72 @ 0.7, median IoU 0.80, 0.7 false rows a photo), the misses (Tatsuno LED, Topaz,
   two Tokheim).
2. `ml/pump-reader/src/pump_reader/detdata.py`: the builder - train stills with their windows,
   tracked Live frames (`--frame-step`), video frames, negatives; heldout stills to their own folder;
   the disjointness assertion. It reads `corpus.sqlite` (SQLite-first, PU.36).
3. `scripts/corpus_db.py sql "..."`: what is there now - `select split, count(*) from fixtures where
   kind='pump' group by 1` (68 heldout / 250 train), `select count(*) from media where kind='live'`
   (162), `select tracking, count(*) from entries group by 1` (records marked `bad` are skipped).
4. `Spike/ReceiptSpike/fixtures/pump-live/README.md` batches 6-9 - what arrived this week: night
   stills, Neste/Olerex/five-grade Circle K/`LIITRID` Wayne heads, 60 tracked records, 16 clips.
5. `PumpReaderTestSupport.isHeldout`/`isTrain` - decision 9 and its amendment: heldout = the split's
   `heldout` (measure only when reviewed); an unreviewed heldout still is NOT train either.

This brief's premise - the detector never saw this week's heads - is a hypothesis: `counts.json` in
the old export says what it saw; confirm before retraining.

## What to build

(a) **Re-export** with `detdata` on the current database, same `--edge 1024` and `--frame-step 5`
as PU.33 (the numbers must be comparable). Print the counts: train stills, train frames (Live and
video), negatives, heldout stills. Assert - in a pytest you add - that no heldout still and no frame
of a record paired to a heldout still reaches the train set, and that records with `tracking = bad`
contribute no frames.

(b) **Train** with `detector/train.swift` at 3 000 iterations to a candidate `.mlmodel` under
`.out/det/` (never over the shipped file). Note the wall time and the size.

(c) **Measure** with `detector/measure.swift` on the heldout stills at confidence 0.3, old model and
new, and report the six numbers side by side: recall @ IoU 0.5, @ 0.7, median IoU, false rows per
photo, photos with any row, photos with every row. Add a per-still line for the four heldout night
stills (`pump-275`, `277`, `280`, `281`) and for the PU.33 misses (the Tatsuno pair, the Topaz, the
two Tokheim): found / not found, before and after.

(d) **The gate**: ship the new model to `ios/App/Resources/DigitRows.mlmodel` only if recall @ 0.5
does not fall, photos-with-every-row does not fall, AND false rows per photo does not rise by more
than 0.2. Then run `PumpReaderPipelineTests` (heldout, with the runtime gate bypassed the way
round 11 did if this is not macOS 26 - say so) and record the live committed / correct / precision
against the floor (43 / 0.99): the floor holds or moves up; a fall is a finding, and the model does
NOT ship on a fall even if (c) passed.

Out of scope: the verifier (PU.47), the classifier (PU.41), any change to the export's edge or
frame step, the slicer.

## Tests you must add

pytest in `ml/pump-reader/tests/test_detdata_disjoint.py`: on a scratch copy of the database with
one heldout still and one Live record paired to it, the export's train folder contains neither;
with a record marked `tracking = bad`, no frame of it is exported. **Named mutation**: drop the
heldout filter in `detdata` (the `split == "heldout"` branch) - the first test must go red. Paste
red-then-green.

## Checks

`ml/pump-reader/.venv/bin/pytest -q ml/pump-reader/tests` exit 0 with count; `detdata` exit 0
with the counts printed; `train.swift` exit 0; `measure.swift` exit 0 twice (old, new); if the
model ships: `scripts/gate.sh` and `swiftlint lint` from the repo root exit 0, and the pipeline
suite's count > 0.

## Vacuous traps

Measuring on train frames. A recall gain bought with false rows (the false-rows column is part of
the gate). Comparing against PU.33's numbers instead of re-measuring the OLD model on today's
heldout set (68 stills, not 64 - the amendment added four; the old numbers are on 64). Shipping on
(c) alone without (d).

## Report back

Exit codes, counts, run-or-only-written, the mutation red-then-green, the export counts, the (c)
table with the per-still lines, the (d) verdict with the pipeline numbers, wall time and model size,
anything found and not fixed.
