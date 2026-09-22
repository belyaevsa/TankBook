# PU.52-REVIEW-WHY-IT-LOWERED - why does every improvement cost the live path?

**Read-only.** You write exactly ONE file: `agents/reviews/PU.52-REVIEW-WHY-IT-LOWERED-qwen.md`.
No code, no edits to the corpus or the docs - name what you would change and why. No `/tmp`;
scratch, if you need any, is `ml/pump-reader/.out/review-why/`. Two build agents are live in this
checkout (PU.50 in `tools/pump-annotate`, PU.51 in the reader core) - read anything, write nothing
but your own review file, and do not be surprised by files changing under you.

## The question

Four times now, a change that made a component measurably better has made the **live path** - the
thing a user's phone actually runs - worse. The orchestrator can name the mechanism for the last
one but not the pattern. **Why does this keep happening, and what would stop it?** The review is
wanted as diagnosis, not as encouragement: if the honest answer is "the funnel is the wrong shape"
or "the abstention rule is miscalibrated" or "the corpus is measuring something else", say so with
the evidence that supports it.

## The measurements, in order (all on the held-out split, decision 9 + its 2026-09-21 amendment)

The two tiers everywhere below: **annotated** = the reader on the hand-drawn windows (the oracle's
boxes); **live** = the app's own path, no annotation (detector -> verifier -> row assignment ->
slicer -> classifier -> law). Precision is over committed cells; the floors are annotated 104 at
0.96 and live 43 at 0.99.

| # | change | annotated | live |
|---|---|---|---|
| 1 | round 6 classifier (shipped) | 83 / 0.988 | 39 / 1.000 (later 43 after PU.34's law arbitration) |
| 2 | round 11 control: the pool rebalanced (per-fixture cap, hard-example weight) | **95** / 0.968 | **29** / 1.000 |
| 3 | round 11 + the new synthetic profile (step 3) | **97** / 0.959 | **36** / 0.972 |
| 4 | PU.48: the row detector retrained on 96 more train stills (recall@0.5 0.869 -> 0.877, photos-with-every-row 53 -> 55) | 104 / 0.990 | **43 -> 28** / 0.964 |
| 5 | PU.47: the verifier stops reading the classifier's margin and judges the slicer's geometry instead | 104 / 0.990 | 43 / 1.000 (unchanged; the SAME 216 rows kept under two different classifiers) |
| 6 | PU.48's detector re-scored through PU.47's verifier | 104 / 0.990 | **36** / 0.944 |

Read together: a better classifier pool costs 10 live cells; a better detector costs 15 and, once
the verifier is model-free, still costs 7 and takes precision below the floor. The verifier was
**half** the loss in (4) - (6) proves it - and removing it did not make the rest go away.

And the shape of the failure, measured 2026-09-22 over the 68 held-out stills under the shipped
detector: **53 find rows, assign fields and commit nothing**, 9 are fully right, 4 partial, 2
wrong. Rows are found and roles assigned on 66 of 68. The loss is almost entirely the read/law
stage refusing. Twelve of the 53 are clean, well-lit Circle K stills with no glare and no angle
(`pump-019`, `028`, `032`, `046`, `050`, `055`, `062`, `068`, `070`, `095`, `104`, `116`).

One concrete failure worth explaining: with PU.48's detector, `pump-092` (Scheidt & Bachmann)
commits `3.0` for 30.0 and `191.55` for 1915.5 - a dropped **leading** digit on both fields of the
same display, so the triple still closes (3.0 x 63.85 = 191.55) and the law commits a wrong answer
with full confidence. The box clipped a digit; the strip it produced is a valid row, one cell short.

## What to read, in this order

1. `docs/EXTRACTION.md` -> "The pump reader" and decisions 1-10 (the design and what was already
   decided); the 2026-09-21 amendment to decision 9 at the end of the decision.
2. `ml/pump-reader/REPORT.md`: rounds 5-11, the PU.33 detector section, PU.47, PU.48, and the
   dated "PU.48's candidate re-scored through PU.47's verifier". The round-11 seed table and its
   decomposition are the core evidence.
3. The code, in pipeline order: `ios/Sources/TankbookCore/Extraction/PumpReader/PumpPanelLocator.swift`,
   `PumpRowDetector.swift`, `PumpRowGeometry.swift` (new, PU.47), `PumpReader.swift` (`verify`,
   `read`), `PumpGlyphSlicer*.swift`, `PumpRowAssignment.swift`, `PumpReadingLaw.swift`,
   `PumpSegmentsModel.swift`.
4. `ml/pump-reader/src/pump_reader/`: `dataset.py` and `train.py` (the synthetic renderer and the
   training recipe), `realglyphs.py` (the real-cell pool, the per-fixture cap, the hard-example
   weight, the centred filter), `detdata.py` (the detector's export), `score.py`.
5. The tests that define "better": `ios/Tests/TankbookCoreTests/PumpReaderPipelineTests.swift`
   (both tiers and their floors), `PumpReaderHarnessTests.swift` (the slicer's count and dp
   agreement), `PumpReadingLawTests.swift`, `PumpRowGeometryTests.swift`,
   `PumpReaderTestSupport.swift` (`isHeldout` requires `reviewed`, decision 9's amendment).
6. `agents/reviews/PU.32-REVIEW-STEP-CHANGE-qwen.md` - your own earlier review of this reader, and
   `PU.13-REVIEW-ANNOTATIONS.md` for what the oracle's quads are and are not.

You cannot see images. You CAN measure them: `ml/pump-reader/.venv/bin/python` has pillow, numpy
and the corpus is a SQLite database (`scripts/corpus_db.py sql "..."`) plus JSON/CSV. Run
`ios/.build/opt/debug/pump-read <image> --classifier ... --detector ...` with `{"windows":null}` on
stdin to reproduce any live read yourself - the reply carries the rows, the per-cell margins, the
timings and the committed triple. Two detectors are on disk: `ios/App/Resources/DigitRows.mlmodel`
(shipped) and `ml/pump-reader/.out/det/pu48/DigitRows-pu48.mlmodel` (the candidate).

## A previous run's measurements are already on disk (2026-09-22, 17:12)

The first dispatch of this brief wedged after ~45 minutes (no network, no CPU, no log) without
writing its review. **Its measurements survived** in `ml/pump-reader/.out/review-why/`: a per-still
live sweep of the 68 heldout stills for four (classifier, detector) pairs - `live-s6d0.jsonl`
(shipped classifier + shipped detector), `live-s6d48.jsonl` (shipped classifier + PU.48 detector),
`live-par-s3d0.jsonl` and `live-par-s6d48.jsonl` - plus `sweep.py`, `score.py` and its own scorer's
summaries. **Read and reuse them** rather than re-running four sweeps; check `sweep.py` to see
exactly what was run before you trust a line, and say in the review which numbers are that run's
and which are yours. Its scorer is looser than `PumpReaderPipelineTests` (it counts the declared
truncated-total artefacts `pump-083`/`pump-106` as wrong), so its absolute precision is not
comparable to the suite's - the ordering between configurations is.

## What the review must answer

1. **The mechanism, named.** Why does a better component lower the live number? Give the causal
   chain for at least two of the six rows above, each pinned to a file, a threshold or a measured
   distribution - not a story. If the mechanism differs between the classifier case and the
   detector case, say so.
2. **Is the live tier measuring what we think?** The annotated tier improves monotonically while
   the live tier does not. Either the live tier has a coupling the annotated one does not, or it is
   measuring a different thing. Which, and how would you prove it in one experiment?
3. **The 53 that commit nothing.** Is this an abstention rule that is too strict, a slicer that
   miscounts, a classifier that is uncertain, or a law that cannot use partial evidence? The twelve
   clean stills are the discriminating set - name what you would measure on them, and predict the
   answer before you measure it if you can.
4. **The wrong-answer case.** `pump-092`'s clipped leading digit closes the arithmetic and commits.
   Where does the guard belong - the detector's box, the slicer's cell count, the law's triple, or a
   new invariant? What would that guard cost in coverage?
5. **What would you change, in order.** Ranked, each with: the change, the mechanism it fixes, the
   number that would move, the experiment that would confirm it in one run, and its cost in this
   codebase (S / M / L). Say plainly if the honest first item is "stop optimising components and
   change the pipeline's shape" - and what shape.
6. **What NOT to do.** Which of the obvious next steps (more training data, a bigger classifier, a
   second detector round, per-head thresholds, a cloud fallback) would you actively advise against
   here, and why.

## What NOT to do

- Do not propose a rewrite, a different framework, or a general-purpose OCR - the decision to build
  this reader is made (`DEVELOPMENT-TIMELINE.md`, 2026-09-18) and a review that re-litigates it is
  a wasted run.
- Do not pad with generic ML advice. Every claim names a file, a number, a fixture or a
  distribution you measured yourself.
- Do not treat the annotated tier as the goal: it is the oracle's boxes, and the phone never has
  them.

## Output

`agents/reviews/PU.52-REVIEW-WHY-IT-LOWERED-qwen.md`: a one-paragraph verdict, then the six
answers in order, then "the one experiment I would run tomorrow" in a short section of its own,
then the questions you could not answer from the repository (so the orchestrator can answer them).
