# PU.52-REVIEW-WHY-IT-LOWERED (qwen) - why does every improvement cost the live path?

Read-only review. One file written: this one. No code, corpus or doc was changed. Where I
re-measured instead of quoting, the run is named; the four `live-*.jsonl` sweeps and their
`score.py` in `ml/pump-reader/.out/review-why/` are the previous (wedged) run's, and I read and
re-scored them rather than re-run them. Its scorer is looser than `PumpReaderPipelineTests` (it
charges the declared truncated-total artefacts `pump-083`/`pump-106` as wrong), so its absolute
precision is not comparable to the suite's; the ordering between configurations is, which is all
I use it for.

## Verdict

The live number is a **joint of components that each got better on its own proxy, where the proxy
is not the property the downstream stage consumes.** The classifier is measured on the annotated
tier (oracle quads, a fixed high-quality input), but the live path consumes it through the law's
hard nat-space thresholds (`readWindow`, `ambiguityWindow`, `decimalMarkPenalty`) on cells that a
loose detector box has already degraded - so a retrain shifts those cells across the close/no-close
cliff and the live number falls while the annotated one climbs. The detector is measured on
`recall @ IoU 0.5`, but the read stage consumes it through *tight* framing (round 4 measured a
framing change alone moves digit accuracy by a third); PU.48 raised recall@0.5 while *degrading*
the tight boxes (median IoU 0.797 -> 0.772, recall@0.7 0.734 -> 0.706, false rows 0.632 -> 0.824)
and clipping/pulling ink into strips the law then either refuses or, worse, closes on the
scale-invariant clip. The two mechanisms are different and both are real, and the pattern is not
"every improvement is bad" but "the live tier is the only place the couplings meet, and nothing
measures them there." The fix is not to stop improving components; it is to (a) add the two
missing invariants (a clip guard at the slicer, and the already-decided price-optional law), and
(b) make the live floor a per-reason, per-head ledger so a retrain that drops the live number is
diagnosed by which stills flipped and why, instead of reverted as a scalar regression.

---

## 1. The mechanism, named

There are two distinct mechanisms, one per component, and they do not share a cause.

**Classifier case (rows 1-3, and REPORT.md rounds 8-11).** The law's commit is a hard decision in
posterior-nat space, and the verifier's keep decision *used to be* another one. `PumpReadingLaw`
commits a triple only when exactly one close sits within `readWindow = 6.0` nats of the plain top
read (`PumpReadingLaw.swift:38`) and no second close sits within `ambiguityWindow = 3.0` nats
(`:33`), with `maxSubstitutions = 1` (`:232`) and the dp hint priced at `decimalMarkPenalty = 4.0`
(`:43`). A single misread cell costs ~3.5 nats, so the arithmetic is deliberately tuned to pass
one substitution and refuse two. A classifier retrain shifts each cell's runner-up posteriors by
fractions of a nat; that is invisible to the annotated tier (its oracle quads yield clean, high
top-read cells whose closes sit comfortably inside the windows) but decisive on the live tier,
whose cells are already near the close/no-close boundary because a loose detector box has degraded
them. The per-still evidence is my re-score of the previous run's sweep, shipped detector, shipped
classifier (`s6d0`) against the round-11 step-3 classifier (`par-s3d0`): the step-3 model loses
the *correct* commits on `pump-080`, `pump-119`, `pump-139`, `pump-180` (all three fields under
s6, total or price abstains under s3) and `pump-083` (all three -> nothing), while it gains wrong
commits on `pump-031` (total 32.58) and `pump-096` (713 / 14260 / 20). The lost stills were
committing cleanly; a few hundredths of a nat moved their best close across the window. This is the
same slide REPORT.md round 8 recorded verbatim ("the live number is a verifier number, not a
classifier number", `REPORT.md:494`), except the verifier half of it is now gone: `PumpReader.swift:257`
keeps `minimumMeanMargin = 1.0` only for the diagnostic and no branch reads it.

**Detector case (rows 4 and 6).** The detector is gated on the loose metric, but the read stage
consumes the tight one. PU.48's own measure table (`REPORT.md:1610-1617`) is the smoking gun:

| metric | shipped PU.33 | PU.48 |
|---|---|---|
| recall @ IoU 0.5 | 0.869 | **0.877** (rose - this is what "better" means) |
| recall @ IoU 0.7 | 0.734 | **0.706** (fell) |
| median IoU | 0.797 | **0.772** (fell) |
| false rows / photo | 0.632 | **0.824** (+0.191, on the 0.2 edge) |

The extra recall is bought from the false-row budget and the tight-box budget. The read stage is
framing-sensitive, so worse-tight boxes become clipped digits and pulled-in neighbour ink. My
re-score of `s6d0` vs `s6d48` (shipped classifier, detector changed) shows the shape: PU.48 gains
four correct stills (`pump-019`, `pump-076`, `pump-201`, `pump-277`) but loses nine it previously
nailed (`pump-014`, `062`, `080`, `112`, `119`, `139`, `165`, `186`, plus partial losses on `030`,
`031`, `167`), and its two "gains" `pump-092` and `pump-096` are the wrong-commit clip class. The
row strings make the clip concrete: `pump-080`'s total reads `002015` (6 cells) under the shipped
detector and `1002015` (7 cells, a spurious leading `1` from outside the box) under PU.48;
`pump-112`'s total reads `001014` -> `001.014` (the box moved where the slicer sees the mark);
`pump-062`'s total reads `39.55` -> `7.99` (the left half of the `3` became a `7`). The verifier
cannot catch any of these because `PumpRowGeometry` (`PumpRowGeometry.swift:76-103`) checks count,
pitch, band, mark position and blank layout - all internally consistent for a one-cell-short or
one-cell-widened row. That is why row 6 (geometry verifier) recovers only half the loss (28 -> 36)
and, critically, drops precision to 0.944: the geometry verifier keeps the clipped rows the margin
gate used to discard, and the law closes on them.

**Why the two differ.** The classifier case is a *threshold-coupling*: a scalar (nats) moves a
fixed decision boundary. The detector case is a *geometry-coupling*: the box changes what the
slicer sees, and the read error is content, not confidence. Row 5 proves the verifier was half the
detector loss and is now model-free; the surviving 43 -> 36 is the read stage deciding differently
on boxes the verifier keeps either way - the same conclusion the report already reached
(`REPORT.md:1192-1196`).

---

## 2. Is the live tier measuring what we think?

It is measuring the right thing (the phone's path), but it is **one number that is the joint of
two couplings the annotated tier does not have**, and it is being read as if it were a function of
whichever component was just retrained. The annotated tier improves monotonically (83 -> 95 -> 97
-> 104) because it is the classifier measured in isolation on a fixed high-quality input; the live
tier does not, because its input (the detector's box) and its decision boundary (the law's nat
windows) both move underneath it. The live tier is not measuring a *different* thing - it is
measuring the *same* thing with two extra degrees of freedom that the per-component metrics never
expose.

**One experiment to prove which:** run the live path once with the detector's row *selection* and
role *assignment* unchanged, but each kept row's quad replaced by the nearest oracle quad from
`windows.json` (the "live-with-oracle-boxes" tier). If the live number jumps from 43 toward the
annotated 104, the gap is box geometry and everything downstream (slicer, classifier, law) is
healthy on the live selection; the residual would be row-selection/assignment error. If it does not
jump, the gap is the read/law stage even on the rows the detector picks correctly. I would predict
the box is the dominant term, because PU.34 already measured the leading-glyph cut as the detector's
(`REPORT.md:547-550`) and the clean-still result below shows the read stage is far from healthy even
on oracle boxes - so the honest prediction is a jump to roughly 60-80, with the shortfall being
slicer miscounts and the law's price requirement, not the detector.

---

## 3. The 53 that commit nothing

It is not one of the four - it is two, and the clean stills name both. The twelve clean Circle K
stills are the discriminating set precisely because the detector, slicer and classifier are all at
their best on them; if they still abstain, the cause is systematic, not scene difficulty.

**Cause A is the law requiring a price (the "cannot use partial evidence" half).** Decision 11 is
already signed but not yet in the code: `PumpReadingLaw.resolve` still requires a price window and
returns `boardFoundNoPrice` (`PumpReadingLaw.swift:52-66`), and `docs/EXTRACTION.md:946-965`
records that **26 of the ~52 stills that commit nothing refuse for exactly this reason** - total
and volume are a complete `FillUp`, and the price is derived from them everywhere else. This is
the largest single refusal and it refuses a fill the user could have logged. It is an abstention
rule that is too strict in the specific sense that it treats a missing price as fatal when the
product owner has already ruled it optional.

**Cause B is the read stage, on the clean stills themselves.** I read the previous run's
`clean12-r6.jsonl`/`clean12-s3.jsonl` (the annotated path, oracle quads, no detector): of the
twelve clean stills, **six commit nothing on the annotated path** (`pump-028`, `032`, `050`,
`055`, `070`, `104`) and two more are partial (`062`, `095`). These are Gilbarco Circle K
six-digit zero-padded rows, and the strings show the failure is slicer miscounts and single-digit
misreads, not glare: `pump-028`'s total reads `00908` (the `004` collapsed), `pump-032`'s reads
`002` (three cells dropped), `pump-050`'s reads `7002033` (seven cells, a split glyph), `pump-055`'s
reads `10808` (the 0->6 confusion, digit outside the beam - `REPORT.md:561`). So the 53 that commit
nothing are dominated by (a) the price requirement and (b) a slicer that miscounts the zero-padded
Gilbarco rows the classifier is otherwise best at - which is exactly the population PU.34's READ
table already classified (28 of 117 rows miscounted, 25 value-changing, `REPORT.md:527-552`).

**What I would measure on the twelve, and the prediction before measuring:** for each, print the
slicer's per-field cell count against the oracle `glyphCount`, and the law's per-field abstention
reason. Prediction: fewer than half have all three fields counted right (I count six of twelve
abstaining on the annotated path already), and of the six abstaining stills, three or more name
`cellUnknown`/`nothingClosed` from a miscounted total rather than `boardFoundNoPrice`. If instead
they were all `boardFoundNoPrice`, cause B would be a mirage - it is not; the strings already rule
that out.

---

## 4. The wrong-answer case: pump-092

My re-measurement refines the brief's gloss. The d48 row strings are `total 19165` (5 cells),
`liters 30.0` (3 cells), `unitPrice 63.85` (4 cells), and the oracle is `1915.5` / `30.00` /
`63.85` (`windows.json`). The digits are mostly present; what happened is a *conspiracy of three
small failures assembled by the law's dp freedom*: the box clipped the trailing digit of liters
(`30.00` -> `30.0`, one cell short - the d48 liters box is 0.4629..0.6797 against the oracle's
0.5035..0.6939, cut at the right edge), the total's dp mark was missed (`19165`, no mark), and the
total's last digit read `6` for `5`. The law then placed the decimals to close: liters `3.0` (dp
after the first of three digits), total `191.55` (the 6 repaired to 5, dp after the third), and
`3.0 x 63.85 = 191.55` closed. Scale-invariant arithmetic is exactly what the PU.32 review already
named as the structural blind spot (`agents/reviews/PU.32-REVIEW-STEP-CHANGE-qwen.md` §6: "cannot
see scale"); the clip class is the same "consistent shrink" as `pump-106`.

**The guard belongs at the slicer, not the detector's box, not the cell count alone, and not the
law's triple.** The detector cannot see a sub-pixel clip (it is an object detector); the cell count
is self-consistent (3 cells is a legal liters row for a 2-decimal currency); the law is scale-blind
and its dp-placement freedom is a legitimate feature for recovering missed marks. The one signal
that survives all three is **edge ink**: a clipped glyph leaves ink running off the strip's edge.
`PumpReader.sliceDetectedOrOriginal` already has the recovery half of this - it widens by
`detectedMarginHorizontal = 0.1` and keeps the widened slice only when it finds at least as many
cells (`PumpReader.swift:140-145`) - but when the widened slice does *not* recover, the code
silently falls back to the clipped plain slice. The missing branch is the abstention: **if the
plain slice's leftmost or rightmost edge column carries glyph ink above threshold, and the widened
slice does not recover a cell, refuse the row.** That is a new slicer/verifier invariant, one line
of "else", and it converts a wrong commit into an abstention, which hard rule 13 mandates ("a
confident wrong value is worse than nil").

**Cost in coverage:** only the rows whose box actually clips a glyph. From my re-score, that is
`pump-092` (2 cells) and `pump-096` (2 cells) - a handful of cells, all of which are *wrong* today,
so the guard costs zero *correct* commits and buys the 0.99 floor back (0.944 -> 1.000 by removing
the only wrong commits). The risk to measure is that edge ink also fires on a legal window whose
glyph genuinely touches the strip edge; the PU.13 review measured right-edge ink touching in 81.5 %
of windows (`PU.13-REVIEW-ANNOTATIONS.md` §1), so the threshold must be tuned on the *leading* edge
of a *detected* (not oracle) strip, and the experiment in §7 is what would confirm it does not
over-abstain.

---

## 5. What I would change, in order

Each: change, mechanism it fixes, number it moves, the one-run experiment, cost.

1. **The clip guard: refuse a strip whose edge carries clipped-glyph ink, when the widened slice
   did not recover a cell.** Fixes the detector-case wrong-commit class (rows 4/6, `pump-092`/`096`).
   Moves live precision 0.944 -> 1.000 on the PU.48 candidate by turning the only two wrong commits
   into abstentions; costs ~4 committed cells, all wrong today. Experiment: run the live path under
   PU.48; assert the `WRONG` lines are empty and precision is 1.000, and print the new `cellsPerRow`
   per still to confirm no correct still flipped. Cost: **S**.

2. **Implement decision 11: total + volume may commit without a price, guarded by the implied
   price band (`total / volume` in `FuelPriceBand`).** Fixes the largest single refusal, not the
   regression pattern, but it is the biggest lever on the live *number* and it is already the
   product owner's ruling. Moves ~26 of the 53 abstaining stills from `boardFoundNoPrice` to
   committing total+volume; the plumbing is present (`priceBand` is threaded into
   `PumpReadingLaw.resolve` and unused on this path, `PumpReadingLaw.swift:69-70`). Experiment: run
   the live path once, diff the `boardFoundNoPrice` count before/after; it should fall from ~26 to
   near zero and the committed count should rise by roughly that many stills. Cost: **S**.

3. **Make the live floor a per-reason, per-head ledger instead of a scalar.** Fixes the *pattern*:
   the scalar live floor is non-monotonic in the components, so every retrain that shifts a coupling
   reads as "regression, revert" and the actual coupling goes unmeasured. Concretely: keep the 43
   / 0.99 gate, but require every change to the classifier or detector to report, from
   `PumpReaderPipelineTests`' own histograms (already printed, `PumpReaderPipelineTests.swift:143-153`),
   which stills flipped and which `PumpAbstentionReason`/`WRONG` line they moved to - so a drop that
   is all `boardFoundNoPrice` (law) is distinguishable from one that is box-clip (detector) or
   `cellUnknown` (slicer). Moves no cells; makes the ratchet steppable and ends the false-revert
   loop. Experiment: none needed - the mechanism is the report the suite already emits. Cost: **S-M**
   (test/protocol only).

4. **Re-gate the detector on the metric the read stage consumes (IoU >= 0.7 and median IoU), not
   recall@0.5.** PU.48 "passed" on recall@0.5 while degrading tight boxes; the gate (c) is the
   wrong proxy. Fixes the detector-case *refusal* half (rows 4/6) by refusing to call a looser-box
   detector better. Moves nothing by itself, but stops the next detector round from shipping a
   regression. Experiment: re-score PU.48's `measure.swift` output and show recall@0.7 and median
   IoU both fell while recall@0.5 rose - the gate should have failed it. Cost: **S**.

5. **Fix the slicer's zero-padded-row miscount (the clean-still failure), not by more data but by
   attacking the six clean stills' strings.** Six of twelve clean Circle K stills commit nothing on
   the annotated path with miscounted totals (`pump-028` -> `00908`, `pump-032` -> `002`,
   `pump-050` -> `7002033`). This is the read-stage half of the 53, and it is a slicer problem on
   exactly the head family the corpus holds most of. Moves annotated and live both (a miscounted
   total blocks the whole triple). Experiment: run the slicer on the twelve and diff `count` vs
   `glyphCount`; the fix is measured by how many of the six come back. Cost: **M**.

The honest first item is not "stop optimising components." The components are the right ones and
the pipeline shape (detector -> slicer -> classifier -> law) is right. What is wrong is the *metrics
and the two missing invariants*: items 1 and 2 are the invariants the live path is missing, item 3
is the metric that would have caught all six rows the day they happened, item 4 is the detector's
wrong gate, item 5 is the read stage's own gap. Items 1-4 together are the answer to "what would
stop it"; item 5 is what raises the ceiling afterward.

---

## 6. What NOT to do

- **More classifier training data, and specifically the rebalanced pool, is not the lever.** Round
  11's control (pool cap + hard-weight) moved annotated 83 -> 95 while live fell 39 -> 29
  (`REPORT.md:1290-1307`); the PU.32 review already measured the real set is 93 % near-duplicate
  Live frames of two head families. The bottleneck on the live path is not classifier accuracy, it
  is the couplings and the slicer miscounts.
- **A bigger classifier** - the classifier is not capacity-bound; the oracle run already commits
  526/611 at 0.998 on perfect strings, so the ceiling is pixels and slicer, not the model.
- **A second detector round judged by recall@0.5** - PU.48 is the proof: recall@0.5 rose and the
  live path fell. The detector's gate must move to tight IoU first (item 4) or the next round
  repeats the same trap with more data.
- **Per-head thresholds** - every added threshold is another constant fitted to one component's
  distribution, which is exactly the disease (the verifier's `minimumMeanMargin = 1.0` fitted to
  round 6 was the mechanism of the rounds 8-11 slide). The geometry verifier and the clip guard
  are model-free and head-free by design; do not reintroduce per-head tuning.
- **A cloud fallback** - hard rule 1 (local-first) and it answers a capacity problem the reader
  does not have; the loss is structural (boxes, thresholds, slicer), not compute.

---

## The one experiment I would run tomorrow

The **live-with-oracle-boxes tier**: one run of `PumpReaderPipelineTests.livePath`'s loop with the
detector's row *selection* and role *assignment* intact, but each kept row's quad swapped for the
nearest oracle quad from `windows.json` (by IoU), everything else identical. It costs one ~16-minute
suite pass and splits the live gap into three named terms - box geometry (the dominant one, by my
re-score), row selection/assignment, and the read/law stage - and it also carries the clip guard's
control: the same run with and without the edge-ink abstention shows whether the guard over-fires
on legal windows whose glyph touches the strip edge (the PU.13 81.5 % right-edge-ink fact is the
risk). Every claim in sections 1, 2 and 4 is a prediction this one run either confirms or kills.

---

## Questions I could not answer from the repository

1. **Which verifier the round-11 rows 2-3 were measured under.** The round-11 seed table
   (`REPORT.md:1290`) and PU.47's re-score (`REPORT.md:1187`) disagree on the shipped detector's
   live number (39 vs 43), and I could not determine from the tree whether the 29/36 live numbers
   of rows 2-3 ran the margin gate or the geometry verifier. It does not change the mechanism (both
   cases are threshold-couplings), but it changes how much of rows 2-3 the verifier owns versus the
   law.
2. **The exact digit-level provenance of `pump-092`'s committed `3` and `191.55`.** My row strings
   show the digits are present and the dp marks are the assembly point; the brief's "dropped leading
   digit" gloss does not match the strips I read. Whether the trailing-digit clip and the missed
   total mark are one defect or two is an image-level question I cannot settle without seeing the
   strip, and it decides whether the clip guard (item 1) alone closes `pump-092` or needs the dp
   mark's placement to be constrained as well.
3. **Whether the edge-ink guard over-fires.** The PU.13 review measured ink touching the right edge
   in 81.5 % of *oracle* windows, but those are hand-drawn tight quads; the distribution on
   *detected* strips (looser, clipped) is unmeasured, and it is the number that decides item 1's
   coverage cost. This needs the one-run experiment above, not a code read.
4. **Why the shipped detector's clean-still commits (`pump-062`, `080`, `112`, `119`, `139`, `165`,
   `186`) are lost by PU.48 at all** - recall@0.5 rose and these stills are clean, so a looser-but-
   more-recall detector should not lose rows it previously read correctly. My row strings show the
   boxes moved (widened left, clipped right), but nothing in the tree explains *why* retraining on
   96 more stills moved a clean still's box in the wrong direction; that is a detector-training
   question (anchor/NMS/scale), not a reader question, and it is the thing a tight-IoU gate (item 4)
   would have surfaced.
5. **The per-head breakdown of the 53 abstentions** - the PU.51 histogram names `boardFoundNoPrice`
   as the largest but the tree does not break the remaining refusals down by head and reason; the
   twelve clean stills are my proxy for that population, not the population itself.
