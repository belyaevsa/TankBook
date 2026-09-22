# PUMP-DECIDE (fable, 2026-09-22) - what to do next about pump-display recognition

Read-only review of the whole PU arc: `docs/EXTRACTION.md` (the pump-reader section and decisions
1-11 with both amendments of 11), all 2101 lines of `ml/pump-reader/REPORT.md`, the 54 PU rows in
`docs/TASKS.md`, the PU.52 diagnosis, `docs/DEFECT-PATTERNS.md`, the eight reader sources, the
pipeline test, `pump-read`'s instrumentation, the corpus files (`split.csv`, `windows.json`), and
the two uncommitted worktrees (`tb-pu53`, `tb-pu58`). Nothing was run that writes a model, and no
timing below is one I generated; every number is quoted from a file, with its location. Where I
infer, I say so. One file written: this one.

The product owner's question: *"improve the recognition of pump's photo, lift it and make it
faster."* The short answer is in the next section; the evidence follows in the order the brief asks.

---

## 0. The verdict in one page

1. **The direction is right and the evidence has strengthened it, not weakened it.** On the
   corpus, the trained reader is the only pump path that has ever met the precision bar: the live
   path commits **47 of 183 asserted heldout cells at precision 1.000** (`REPORT.md` PU.54), against
   the Vision-plus-rules parser's **53 of 865 at 0.946** on macOS 26 and **13** hits on macOS 27
   (`PumpPhotoGate.swift:39-64`, `docs/TASKS.md` RV.295), and the cloud model's 31/46 with a
   factor-of-ten shift and 6.5-8.3 s median latency (`docs/EXTRACTION.md` -> "The P4.12
   measurement"). With oracle boxes the same read stage commits **112 of 183 (0.612) at 0.991** -
   which is above BOTH numbers in the ship gate (0.99 precision, 0.60 coverage,
   `PumpPhotoGate.swift:71,81`). The reader already clears the gate on the read stage; what keeps
   it off is the box geometry between the detector and the slicer. That is a solvable, measurable,
   bounded problem, and it is not the problem the last eleven classifier rounds worked on.

2. **The shape of the work is wrong, and has been since 2026-09-20.** Since round 6 shipped that
   day, **at least 15 trained candidates (13 classifiers, 2 detectors) have been measured and 0
   shipped**, while every live-path gain - 0 -> 47 - came from geometry (the detector, the margin
   rule, the verifier), the slicer (pitch, body, marks, dim glyphs) and the law, with the classifier
   frozen (section 3 has the ledger). The classifier is not the lever and the ledger has said so
   four separate times (rounds 9, 10, 11; PU.52 §6). Stop retraining it.

3. **"Faster" is solved at the pipeline level on the only evidence that exists** (13-73 ms
   decision, 112-164 ms classify+read, Release, 12 MP stills, `REPORT.md` -> PU.38 "Release build"),
   and **unmeasured on a phone** - RV.295 is open and PU.39's Capture Lab was built for exactly this
   and has not been run. The J4 latency the user experiences is not the reader's: it is the reader
   plus the receipt OCR arm that `CapturePipeline` runs serially after it, plus their own editing.
   Nothing in the backlog makes the experienced path faster, and three rows (PU.53's search in the
   app, PU.49's retry, PU.19's fusion) would make it slower for zero measured cells. Accuracy is the
   only axis left that a code change can move.

4. **The 112 vs 47 gap is box framing, mostly vertical, and one read-only run apportions it.** The
   funnel already measured (`REPORT.md` PU.35: candidate hit 61 -> verified 60 -> two rows 52 ->
   roles right 45 -> photos committing 14, on 64) says detection and verification lose 12 photos,
   assignment 7, and **the read on a correctly selected, correctly assigned detector box loses 31**.
   PU.55's four-quadrant swap on `pump-092` showed the loss follows the box's vertical extent alone.
   The experiment that settles it at corpus scale reuses the oracle quads and the diagnostic that
   already computes IoU per candidate (section 5).

5. **PU.6 cannot be closed "ship" today and should not be closed "ship off"**: the live coverage is
   0.257 against 0.60, but decision 7 already ships the reader in every build behind the alpha
   notice, and on the heldout it has produced zero wrong pre-fills. What is missing before PU.6 can
   be answered is not another model round; it is four cheap things listed in section 12, the first
   of which is that **the gate the app reads is measured on the wrong pipeline** - `PumpPhotoGate`'s
   constants are the rules parser's, asserted against the rules corpus
   (`AccuracyRatchetTests.swift:278-286`), so the reader could reach 0.99/0.60 and the notice would
   stay up.

6. **PU.59 will cost more than its ruling assumes.** The six stills it commits with a caution are,
   on PU.54's own measurement, the six confident-wrong stills of the band-only run (`REPORT.md` PU.54:
   59 committed / 49 correct with six wrong stills, all role-assignment misses or misreads). The
   cautioned tier's precision on the heldout will be near 0.2 by that arithmetic (section 11). The
   ruling stands; the number to print and watch is that one, and PU.60 should land before it.

---

## 1. The origin, and whether its reasoning still holds

**What was believed on 2026-09-18** (`docs/EXTRACTION.md` -> "The pump reader", `HANDOVER.md` ->
"The pump-reader tranche"): Vision reads a seven-segment display as text and that is the wrong
abstraction - it returns a `4` for a `9` at confidence 1.00 (`pump-004`) and drops the decimal dot,
so a factor-of-ten volume is invisible to the arithmetic. The rules parser's pump path
(`PumpExtractor`, B2) was measured at **1/46** on the first corpus, then **24/178 (13 %)** when hard
rule 15 was written, then **53/865 hits, 56 committed, 53 correct (0.946)** on macOS 26
(`PumpPhotoGate.swift`, `docs/EXTRACTION.md` -> "Measured reality, 2026-09-18"). The crop-and-re-read
experiment (B3) was measured and closed: 7 correct of 148 separator-less runs, ten wrong. The cloud
model read 31/46 but with a decimal shift on `pump-009`, non-determinism on `pump-005`, and 6.5-8.3 s
median (P4.12). So the owner decided: *"we need to develop our own library to recognize pump photos.
Not rely on OCR solely"*.

**Does it hold?** Yes, and on three counts the evidence is stronger now than then:

- **The read stage works.** On the oracle strings the law commits 763 cells at 0.9987
  (`REPORT.md` PU.54, "The oracle ratchet"); on real pixels with hand boxes it commits 112/183 at
  0.991 (PU.54). Nothing built on Vision text ever got near 0.99 on pumps.
- **It is runtime-stable where the rules parser is not.** RV.295 records the rules parser's pump
  hits falling **53 -> 13** between macOS 26 and 27 because Vision's text recognition changed. The
  reader's read is Core ML on its own slicer's cells; Vision enters only as the text-line count that
  guards classification and as the slow-path proposer (`PumpDisplayCapture.textLineCount`,
  `PumpPanelLocator.locate`). I infer from the code that a Vision drift of that size would not move
  the reader's committed count the way it moved the parser's - this is inference, and RV.295 on a
  phone is what would prove it.
- **It is the only path that satisfies rule 1 and the 3 s budget at once.** The cloud model is a
  late-answer path by measurement (P4.12, 6.5-8.3 s median, 40 s max); the reader is 112-164 ms in
  Release on the Mac (PU.38).

What the origin got wrong, and has been paid for: "a detector only if the corpus proves it
necessary" (item 1 of the design) and "no character segmentation model" (item 2) put the locator
last and the classifier first. The corpus proved the detector necessary within two days (PU.24's
classical locator: median IoU 0.008; PU.33's detector: 0.80), and the classifier turned out to be
the component with the least leverage on the end-to-end number. Section 3 has the accounting.

**J4, what the user is promised** (`docs/JOURNEYS.md` -> J4): a display runs the reader, arrives at
Confirm as `.pumpPhoto` with the committed fields pre-filled and the rest empty, with the alpha
notice while the build is below the gate, typing beside it. That is what ships today. J4 also says
the journey *"must feel as reliable as J3 or not exist"* and is *"unowned by any competitor"*
(`docs/VISION.md` line 38) - both are arguments for finishing it, and both are arguments against a
cautioned tier that pre-fills wrong numbers (section 11).

---

## 2. The end-to-end number by round, PU.3 to now

The table that does not exist anywhere. Every number is quoted from `REPORT.md` (the section named
in the first column) or the PU row in `docs/TASKS.md`. **Read the "basis" column before comparing
two rows**: the yardstick changed four times (all 114 fixtures held out -> the 64-still heldout of
decision 9 -> 68 after the night amendment -> 68 with every entry `reviewed`, plus corpus commits
that moved the annotated number between rounds with no ledger entry). A number is comparable only to
the row above it when the basis is the same.

Columns: **annotated** = oracle hand quads through slicer + classifier + law (the read stage alone);
**live** = the app's own path end to end (`PumpReaderPipelineTests.livePath`). Both as committed /
correct / precision / photos-all-right.

| date | round / row | what changed | basis | classifier-tier metric | annotated | live | shipped |
|---|---|---|---|---|---|---|---|
| 09-19 | PU.3 | first `SegmentNet`, naive equal-width slicer | 114 fx, 433 windows, all held out | per-glyph **0.123**, per-window 0.000 | – | – | yes |
| 09-19 | PU.4 | Swift slicer + classical locator | same | count agreement 173/433 (0.40); 0.175 on count-correct; locator median IoU **0.008** | – | – | yes |
| 09-19 | PU.7 | render realism, ablated | 245 count-correct | bold+slant 0.170; all four gaps **0.086** (spill and contrast hurt) | – | – | bold+slant only |
| 09-19 | PU.8 | Otsu, LCN, retry, split-merge; anchored grid | count 259/433 (0.598) | shipped recipe on anchored grid **0.105** (the anchor lowered 0.170 -> 0.105: framing alone moves the number by a third) | – | – | yes |
| 09-19 | PU.9 | train on the slicer's own framing | 259 cc | **0.215** (all 433: 0.177) | – | – | yes |
| 09-19 | PU.10 (round 2) | training material reviewed against real cells | 259 cc | **0.400** (all: 0.309); 15 k steps over 6 k bought 1.3 pt | – | – | yes |
| 09-19 | PU.16 (round 3) | constrained decoder, no retrain | 259 cc | digit-only **0.666**; windows every digit right 0.321 | – | – | yes |
| 09-19 | headline = transaction fields | boards out of the gate | 320 tx windows, 192 cc | 0.698 cc / 0.569 all | – | – | – |
| 09-19 | PU.17/18 (round 4) | comma drawn as displays draw it; calibrated cells; one 96 px strip | 192 cc | **0.717**; dp bit 0.793 | – | – | yes |
| 09-19 | PU.27 (round 4) | contrast collapse on; interior blanks kept | 205 cc; count 273/433 | 0.753 / **0.732** | – | – | yes |
| 09-19 | PU.28 (round 4b) | oracle second pass; rotation the consumers never applied | 214 cc; count 282/433 | 0.728 cc / 0.609 all | – | – | yes |
| 09-19 | PU.20 (round 5) | five-crop TTA + label smoothing | 214 cc | **0.762**; 0.99 precision holds to 25 % coverage | – | – | yes |
| 09-19 | PU.21 / PU.23 | the law on oracle strings | 320 tx windows | – | oracle strings 284/320 @ 0.996 -> **294 @ 0.997** | – | yes |
| 09-19 | PU.22 (round 5) | the reader on real cells, annotated windows | 114 fx, 320 cells | – | 32 / 0.938 / 9 -> **39 / 37 / 0.949 / 12 of 114** | – | yes |
| 09-19 | PU.24 (partial) | Vision proposals + margin verifier | 114 fx | locator median IoU 0.008 -> **0.62** | – | **3 cells, 1/114 photos** | partial |
| 09-20 | **decision 9** | **basis change: 64 heldout stills, 175 cells; train split created** | | | | | |
| 09-20 | round 6 (PU.31) | + 30 % real glyphs from the train split | 64 hx, 175 | – | synthetic-only 18/17/0.944/4 -> **44/42/0.955/12** | **0** | **yes - the last classifier ever shipped** |
| 09-20 | PU.24 round 2 | 48 candidates, height/edge/aspect rules, margin 1.0, duplicate suppression | 64 hx | – | 44 | 0 -> **7 / 7** | yes |
| 09-20 | slicer: fundamental pitch | shortest local autocorrelation peak | count 177 -> 184/238 | – | 44 -> **52 / 0.962 / 14** | 7 -> **4** | yes |
| 09-20 | slicer: pitch vs glyph body | halve/double against the widest run | count 184 -> 210/238 | – | 52 -> **66 / 64 / 0.970 / 18** | 4 -> **11 / 11** | yes |
| 09-20 | round 7 | same recipe, fixed-slicer export | 64 hx | – | 48/47/0.979/13 (r6 re-measured 52/50/0.962/14) | 4 / 4 | **no** |
| 09-20 | round 8 | body-checked export | 64 hx | – | 69/67/0.971/17 (r6 66/64/0.970/18) | **4 / 4** (r6 11/11) | **no** |
| 09-20 | round 9 | + video labels | 64 hx | – | 62/60/0.968/15 | **2 / 2** | **no** |
| 09-20 | **PU.33** | **learned row detector** as the locator's first source; detected rows kept on count and size | 64 hx | recall@0.5 0.86, recall@0.7 0.72, median IoU 0.80, 0.7 false rows/photo | 66 | 11 -> **22 / 22 / 1.000 / 5**; **15 s -> 2.4 s a photo** | yes |
| 09-20 | PU.34 | law: total in the repair tier; exact beats slack-only | 64 hx | – | 66 -> **67** / 0.970 / 19 | 22 -> **23 / 1.000 / 6** | yes |
| 09-21 | PU.34b | slicer marks (the second look) | count 209/238 held; dp **9 -> 128/237** | – | **73 / 0.986 / 22** | **25 / 1.000 / 7** | yes |
| 09-21 | round 10 | 3 seeds, mark-aware export | 64 hx (**basis moved: r6 now reads 79 / 29**) | – | r6 79/78/0.987/22; seeds 79-80 @ 0.962-0.988 | r6 **29/29/1.000/8**; seeds 33-35 @ **0.914-0.971** | **no (x3)** |
| 09-21 | detector retrain (926 images) | more frames | 64 hx | recall@0.5 0.861 -> 0.870, median IoU 0.796 -> **0.779**, false rows 42 -> 44 | – | noise | **no** |
| 09-21 | **PU.35** | margin 0.1 sideways kept only when the count holds; stacked-row rescue; keypad rule | 64 hx | funnel 61 -> 60 -> 52 -> 45 -> **14** | – | 29 -> **37 / 1.000 / 11** | yes |
| 09-21 | PU.37 | split-merge body guard | count 209 -> 211/238 | – | 79 -> **80** / 0.988 / 22 | 37 held | yes |
| 09-21 | PU.38 | classification from the detector alone | 6 heldout pumps, 8 receipts | classification 4/6 -> **5/6**, 0/8 leaked; decision 3349 ms -> 435 ms Debug, **13-73 ms Release** | 80 | 37 | yes |
| 09-21 | PU.19 | Live Photo per-cell fusion | 17 heldout records | still 23/22 -> fused 24/23 at **45x** the time | – | – | measured, not wired |
| 09-21 | **decision 9 amended** | **basis change: 68 heldout (4 night stills), measured once `reviewed`** | | | | | |
| 09-22 | round 11 (PU.41) | material fixes, 3 seeds, 7 models | 68 hx, 186 cells, **PU.42's uncommitted slicer in the tree** | – | r6 83/82/0.988/23; best candidate 97/93/0.959 | r6 **39/39/1.000/11**; candidates **19-36** | **no (x7)** |
| 09-22 | **PU.42** | dim-glyph recovery | count 223 -> **236/251**; dp 129 -> 131/250 | – | 83 -> **106 / 102 / 0.962 / 28** | 39 -> **43 / 43 / 1.000 / 13** | yes |
| 09-22 | corpus session (`82398950` and before) | owner's hand quads, texts, reviewed flags | **basis moved with no ledger row**: annotated 106 -> 104/103/0.990/30; live 43/14 | | | | – |
| 09-22 | PU.47 | verifier on slicer geometry, never the classifier | 68 hx | verifier kept rows **216** for both models | 104/103/0.990/30 | **43/43/1.000/14** (r11 step 3 through the same verifier: 35) | yes |
| 09-22 | PU.48 | detector retrained on 249 stills | 68 hx | recall@0.5 0.869 -> 0.877; **median IoU 0.797 -> 0.772; recall@0.7 0.734 -> 0.706; false rows 0.632 -> 0.824** | 104 (unchanged by construction) | 28/27/0.964/7 (margin) -> 36/34/0.944/9 (geometry) -> 41/39/0.951 (later tree) | **no (x2)** |
| 09-22 | PU.51 | the law names its refusal | 68 hx | – | 104 | 43; histogram over 52: boardFoundNoPrice **26**, nothingClosed 23, priceOutOfBand 2, noLitersWindow 1 | yes (pure addition) |
| 09-22 | PU.57 | tight-IoU detector gate | – | PU.48 **refused** on all three primaries | – | – | yes, no model |
| 09-22 | PU.55 | clip guard | 68 hx under PU.48 | edge-ink guard: 41 -> **3**; bar+gutter: fires on nothing | – | – | **nothing** |
| 09-22 | PU.53 (worktree `tb-pu53`) | orientation search | 68 hx | – | 104 | annotation 43 / upright 43 / search **43** | built, unmerged |
| 09-22 | **PU.54** | price optional; pair validated by a shown price within 5 % | 68 hx, 183 cells | oracle strings 741 -> **763 @ 0.9987** | 104 -> **112 / 111 / 0.991 / 34** | 43 -> **47 / 47 / 1.000 / 16**; boardFoundNoPrice 26 -> **0**; priceOutOfBand 2 -> 11; priceUnvalidated 6; noTotalWindow 6; cellUnknown 3; noLitersWindow 1 | yes |
| 09-22 | PU.58 (worktree `tb-pu58`) | trim the strip to its ink band | – | – | – | running | – |

Two basis notes the table forces. (a) Round 11's section says "68 heldout stills / 186 cells" while
PU.51 prints "coverage 0.235 of 183" and PU.54 counts on 183; the three cells are a `csvDisagrees`
or corpus-session difference nobody recorded. (b) Between PU.42 (annotated 106, live photos 13)
and PU.47's baseline (104, 14) the corpus commits moved both numbers; the ledger has no row for it.
Neither changes a verdict, both are the "measurement drifts silently" shape of
`docs/DEFECT-PATTERNS.md` §7.

---

## 3. What the pattern actually is

Reading the table by **which stage moved the live number**, heldout basis (decision 9 onward):

| stage | live moves attributable to it | net |
|---|---|---|
| locator / detector / verifier geometry | 0 -> 7 (PU.24 r2), 11 -> 22 (PU.33), 29 -> 37 (PU.35) | **+26** |
| slicer | 7 -> 4 (pitch), 4 -> 11 (body), 23 -> 25 (marks), 39 -> 43 (dim) | **+13** |
| law | 22 -> 23 (PU.34), 43 -> 47 (PU.54) | **+5** |
| classifier (rounds 7-11, 13 candidates) | – | **0 shipped, every candidate refused** |
| detector retrains (round 10, PU.48) | – | **0 shipped, both refused** |
| basis moves with no code change | 25 -> 29, 37 -> 39, photos 13 -> 14 | ~+6, unattributed |

So of the ~47 live cells, roughly **55 % came from geometry, 28 % from the slicer, 11 % from the
law, 0 % from any model trained after 2026-09-20**. Meanwhile the row count by stage in
`docs/TASKS.md` is the reverse: the classifier and its data got PU.1, 3, 7, 9, 10, 16, 17, 18, 20,
27, 31, 41 (twelve rows) plus rounds 7-11; the locator got PU.24, 33, 35, 48, 57 (five, two of them
refusals).

The ledger names this itself, four times, and the work continued anyway:

- round 9: *"the live number is a verifier number, not a classifier number"* (`REPORT.md`, Round 9);
- round 10: *"the next classifier round needs a different lever ... not more of the same cells"*;
- round 10's detector: *"the locator's next lever is geometric, not more frames"*;
- PU.52 §6: *"More classifier training data ... is not the lever"*, *"A bigger classifier"* is not
  the lever, *"A second detector round judged by recall@0.5"* is not the lever.

Round 11 (seven models) and PU.48 (two detectors) were dispatched after the first three of those.
PU.41's row still plans "Round 11b". **That is the pattern: the component with the best-instrumented
metric (a training loss, a synthetic validation, a per-glyph score) keeps getting rounds, and the
component where the cells are lost has a ratchet nobody re-ran since PU.35.**

A second pattern, on the no-ops. The rows that moved the number all started from a **measured
table of the population they targeted** and fixed its largest class: PU.34 (117 rows, 28 miscounted,
classified), PU.37 (the 29 by class), PU.42 (the twelve by profile), PU.51 -> PU.54 (the histogram).
The rows that moved nothing started from a **hypothesis about a mechanism** and built the fix first:
PU.7's spill and contrast (real on the corpus, hurt held-out), PU.19's fusion (+1 at 45x), round
11's dp crop (the brief's own A/B picked the variant that cost 33 annotated cells), PU.55 (the
signal did not exist), PU.53 (correct, ceiling two stills, moved zero). Section 10 turns this into a
rule.

A third pattern, on precision. The precision floor has held at 1.000 live since PU.33 because the
**law refuses** what it cannot close - not because any component is accurate. Every candidate that
raised coverage was refused on precision (round 10: +4-6 cells, 1-3 wrong each seed; PU.48: 0.944
and 0.951; band-only pairs: 0.831). The floor is doing exactly its job. PU.56's thesis that the
scalar floor *causes* the no-ops is not supported by the table: the floor refused fifteen candidates
that would have shipped wrong numbers, and the no-ops were no-ops under any floor.

---

## 4. The PU.52 diagnosis, graded

PU.52's five ranked fixes and what happened (`agents/reviews/PU.52-REVIEW-WHY-IT-LOWERED-qwen.md` §5):

| # | fix | claimed move | outcome | grade |
|---|---|---|---|---|
| 1 | clip guard: refuse a strip whose edge carries cut ink | 0.944 -> 1.000 under PU.48, ~4 cells | PU.55: the signal does not exist; the clipped strip's edge is *quieter* (0.028/0.018 vs 0.009); the loss follows the box's **vertical** extent; edge-ink guard drops 41 -> 3 | **refuted** |
| 2 | decision 11: pair commits guarded by the band | "~26 of the 53 abstaining stills" | PU.54: **+4 cells, +2 photos**; the population was 9 stills with a read pair, 3 validated; band-only precision 0.831 | **directionally right, ceiling over-estimated 6x** |
| 3 | per-reason, per-head ledger instead of a scalar floor | "ends the false-revert loop" | PU.56 unstarted | not graded - but see section 3 on its premise |
| 4 | re-gate the detector on tight IoU | "moves nothing by itself" | PU.57 shipped; PU.48 refused | **as claimed** |
| 5 | fix the zero-padded slicer miscount on the clean Circle K stills | annotated and live both | not filed; PU.42's dim-glyph row (filed before the review) covered most of that class | superseded |

Its **one experiment** ("live-with-oracle-boxes", §2 and the closing section) was the most valuable
thing in it and was not run. Its **§6 "what not to do"** was right on every line and was not
followed (round 11 ran anyway; PU.48 was already in flight). Its **§1 mechanism** for the classifier
case (nat-space thresholds, loose boxes degrading cells) is consistent with everything measured
since. Its **§4 mechanism** for `pump-092` (horizontal clip) was wrong in the direction PU.55
measured. Score: two mechanisms named, one right; five fixes, one shipped as claimed, one shipped at
a sixth of the claimed size, one refuted. **The lesson is not that the review was bad - it was
better than the rows it produced. The lesson is that the fixes were ranked by plausibility, and the
one action that would have ranked them by measurement (the oracle-box run) was not taken first.**

---

## 5. The 112 vs 47 gap: verdict and the cheapest experiment

**Verdict.** The gap is dominated by **the read stage on detector boxes whose vertical framing
differs from the hand quads**, not by row selection and not by assignment. Evidence, in order of
weight:

1. **The funnel** (`REPORT.md` PU.35, 64 stills): candidate hit on a true row 61, verified 60, two
   rows verified 52, roles right 45, photos committing 14. Detection + verification lose 12 photos,
   assignment 7, and the read on correctly selected and assigned boxes loses **31 of 45**. On the
   annotated path the same stills commit 30-34 photos. So on photos where selection and assignment
   are both right, the detector's boxes cost roughly half the photos.
2. **The slicer miscounts three to four times more often on detector boxes than on hand quads.**
   On hand quads: 236/251 windows counted right (0.94, PU.42). On detector boxes with the right
   role: 28 of 117 rows miscounted (0.76, PU.34 - an older slicer, so not exactly comparable; the
   direction is not in doubt). PU.34 named the largest class: *"the leading glyph cut by a detector
   box a few percent narrower than the row"*, and expanding the crop *"measured 22 -> 17 with
   precision 0.71 (it pulls in the neighbouring row)"*.
3. **Vertical extent is the axis.** PU.35's sweep: a 0.15-height vertical margin on detected boxes
   collapsed the live read from 29 to 3-15 cells; any sideways margin above 0.1 did the same.
   PU.55's four-quadrant swap on `pump-092`: oracle height + detector left/right recovers the cell,
   oracle left/right + detector height does not. The raw box was 21 % taller than the hand quad and
   its ink band ran rows 6..95 of 96.
4. **The detector's box is as tight as its labels allow, and the labels are noisy.** `REPORT.md`
   -> "The hand quads' own noise": adjacent-frame hand quads differ by up to a quarter of the row
   height at the top edge, meeting each other at IoU 0.75-0.79; *"The detector's median IoU (0.80)
   is that noise, learned."* This is the sentence that closes the detector-retrain question: no
   retrain on these labels will produce boxes tighter than 0.80, so the read stage must become
   insensitive to a box that is 20 % tall, or the labels must be made consistent first.
5. **What the abstention histogram says after PU.54** (50 stills commit nothing): nothingClosed 23
   and priceOutOfBand 11 are reads that produced wrong digits (the band catches the implied price
   of a misread); noTotalWindow 6 + noLitersWindow 1 are detection/assignment; cellUnknown 3 is a
   row the slicer could not count; priceUnvalidated 6 is section 11. Roughly **37 of 50 are the
   read stage on degraded boxes, 7 are the locator, 6 are the pair tier.**

Assignment on hand quads is 1265/1279 (PU.60) - a 1 % term on oracle boxes. On detector boxes it
loses 7 photos of 52, and those 7 are mostly a missing or extra row, which is the detector again.

**The cheapest experiment** - two read-only runs of the suite, no code beyond a test:

- **Run A, oracle-box tier**: `PumpReaderPipelineTests.livePath`'s loop with the detector's row
  *selection* and role *assignment* unchanged, but each kept row's quad replaced by the hand quad
  it overlaps at IoU >= 0.5 (the match `PumpLivePathDiagnosticTests.bestTruth` already computes).
  Prediction, stated before measuring: **80-100 committed** (annotated 112 x the ~0.7 of photos
  where roles are right, PU.35's 45/64). If it lands there, the whole gap between 47 and ~90 is
  box geometry and PU.58-class work is the only thing worth doing on the locator; the remaining
  ~20 is selection/assignment. If it lands under 60, the read stage is unhealthy on the live
  selection even with perfect boxes and PU.58 is deprioritised. **Falsifier: a number, not a story.**
- **Run B, vertical-only swap**: the same, but the kept row keeps the detector's left/right and
  takes the hand quad's top/bottom - PU.55's quadrant test at corpus scale. This directly prices
  PU.58 before PU.58 lands: if B recovers most of A, a band trim is the right shape; if B recovers
  little, the horizontal edges matter too and a trim will not be enough.

Cost: one suite pass each (~minutes in Debug, contended on this machine, so run them when the
verification suite is done). Both reuse the oracle quads, the split, the scorer and the diagnostic.

---

## 6. Is a trained seven-segment reader still the right architecture?

Against the corpus, the four alternatives:

| path | pump accuracy, measured | precision | latency | rule 1 | verdict |
|---|---|---|---|---|---|
| **Vision OCR + rules** (`PumpExtractor`) | 53/865 hits on macOS 26; **13** on macOS 27 (RV.295) | 0.946 (3 wrong of 56) | fast | yes | dead end, measured three times (1/46, 24/178, 53/865), plus the B3 crop experiment closed |
| **Cloud model** (`/extract`, `kind: "pump"`) | 31/46 (P4.12) | unmeasured in the gate's terms; a factor-of-ten shift on `pump-009`, non-deterministic on `pump-005` | **6.5-8.3 s median, 40 s max** | network, money per call (the ledger) | already the late-answer path (F4 inbox); never a synchronous peer |
| **Trained reader** (this) | live **47/183 (0.257)** at **1.000**; annotated **112/183 (0.612)** at 0.991 | 1.000 live | 112-164 ms Release (Mac) | yes, offline | the only path that has met the precision bar; the read stage already clears the gate's coverage floor on oracle boxes |
| **Nothing** (ship pump capture off) | – | – | – | – | J4 is "unowned by any competitor" (`VISION.md`); the reader already produces zero wrong pre-fills on the heldout; typing stays the peer door; there is no evidence the alpha door harms the user today |

A **hybrid** already exists and is the right one: the reader is synchronous and local, the cloud
model is the late answer through the same inbox as receipts (`docs/JOURNEYS.md` F4, RV.288). The
one hybrid I would not build is "Vision OCR as the pump fallback": its precision is below the gate
and it is the component most exposed to OS-version drift.

**What the pump door has to be worth.** Hard rule 15 says a capture is a head start, never the
whole entry. A head start is worth offering when it (a) never pre-fills a wrong number the user
would not notice, and (b) saves typing often enough to be reached for. On the heldout the reader
delivers (a) exactly - 47/47 - and (b) on 16 of 68 photos fully and 47/183 cells overall. Against
the receipt door's 85 % of cells (hard rule 15's re-measurement) that is a weak head start, but it
is the only pump head start in the market, it costs the user nothing when it abstains (the form is
the ordinary form), and the alpha notice tells them so. The door earns its place as long as (a)
holds. **The threat to (a) is not the reader; it is the two things that fill fields underneath it**
(section 11).

**So: the architecture is right; the unit of work is wrong.** The rest of this review is about the
unit of work.

---

## 7. "Faster": an explicit answer

**Pipeline latency is solved on the evidence that exists.** `REPORT.md` -> PU.38 "Release build":
the pump decision is **13-73 ms** and classify+read **112-164 ms** on the 12 MP heldout stills, on
the Mac; receipts are refused in 102-1630 ms. The device budget is 3 s (P4.12). PU.33 took the
per-photo time from 15 s to 2.4 s in the test build; PU.38 took the classification decision from
3349 ms to 435 ms in Debug and under 100 ms in Release. There is no measured stage above 200 ms
in Release. Nothing on the backlog would move a number a user could perceive.

**Two caveats, both measurement gaps, not code gaps:**

1. **No number exists from a phone.** RV.295 ("measure on a device") is open; PU.39's Capture Lab
   was built on 2026-09-21 precisely to record capture ms, pipeline ms and path per preset on a
   device, and PU.40 says *"Open: the production preset, decided by PU.39's lab sessions"* - the
   sessions have not been run. The only device-adjacent figure is the preview detector at ~80 ms a
   frame on the simulator (PU.40b). The iPhone 12 floor is a hard requirement (`docs/VISION.md`);
   the 30.3 MB `DigitRows.mlmodel` (PU.48's size note; `ios/App/Resources/DigitRows.mlmodel` is
   31 751 101 bytes) runs through `VNCoreMLRequest` and its cold-start on a 2020 phone is unmeasured.
   **One lab session on a phone answers "faster" completely and costs no code.**
2. **The J4 latency the user experiences is not the reader's.** `CapturePipeline.process`
   (`ios/App/Sources/Capture/CapturePipeline.swift:47-83`) awaits `readPumpDisplay` and THEN awaits
   `recognize(box:source:)` - the full Vision receipt OCR arm, which on a `.pump` source runs
   `PumpExtractor` - serially, then assembles, then the Confirm sheet. I infer from the two sequential
   `await`s that the pump read adds its 112-164 ms on top of the receipt path every photo pays, and
   the receipt path is the larger term; I have no measurement of the receipt arm's own duration in
   this tree. Then the user edits. `docs/PHASES.md`'s M-check is *"median capture-to-save < 15 s"*,
   which is a journey number, not a pipeline number. If "faster" ever needs a code change, the
   candidate is running the two arms concurrently or skipping the receipt arm on a fast-path
   display - **but measure first**, because the merge at lines 76-83 depends on the rules arm's
   fields (section 11 says why that merge is itself a risk).

**Where "lift" and "faster" trade against each other**, so the owner can see the trade: PU.53's
search adds two detector passes and a second read whenever the seeded read commits nothing - on
this corpus that is 50 of 68 photos, for zero cells. PU.49's tilt retry is the same shape. PU.19's
fusion is 45x the still read for one cell. Every one of these is "slower for no lift" on the
evidence, and section 9 cuts them. Conversely PU.58 (a strip trim before the pitch) is a few
per-row array operations and is "lift, no slower" if it works.

**Answer: latency is a solved problem at the pipeline level and an unmeasured one at the device
level; accuracy is the only axis a code change can move. Spend the "faster" budget on one PU.39
session, not on the pipeline.**

---

## 8. Ranked: what to do next

Each item names the number it moves, the measured evidence it will, roughly how much, and what
falsifies it. An item with no falsifier is not here.

**1. The oracle-box tier and the vertical-only swap (section 5, runs A and B). Read-only.**
Number: none directly - it apportions the 65-cell gap. Evidence it is worth running: PU.35's funnel
(31 of 45 role-right photos lost at the read), PU.55's quadrant table, the hand-quad noise section.
Prediction: A lands at 80-100, B recovers most of A. Falsifier: A under 60 (the read stage is the
problem even with perfect boxes) or B far below A (the horizontal edges matter as much as the
vertical). **This is the first thing because every row below is priced by it**, and it costs two
suite passes. Write the result into `docs/EXTRACTION.md` decision 10 as its own amendment.

**2. PU.60 - the assignment floor is red in `main`.** Number: `PumpRowAssignmentTests` 1265/1279
back over 0.99 with the 14 named; live and annotated printed beside it. Evidence: the test is red
now (PU.53's and PU.54's reports both hit it); role assignment is upstream of the pair tier, and
`pump-032`'s price-row-as-litres is the exact shape that makes a cautioned pair wrong. Size of the
live move: I expect **0-3 cells** on the heldout (the live histogram has 7 stills at
noTotalWindow/noLitersWindow, most of them the detector's, not the assigner's) - inferred, and the
row's own print will say. Falsifier: the 14 turn out to be annotation errors (then the corpus is
fixed, the rule is not) or the fix costs a live cell. It goes before PU.59 because PU.59 makes the
law more dependent on assignment (PU.60's row says so, and PU.54's six wrong stills confirm it).

**3. PU.58 - trim the strip to its ink band, with one correction to its brief.** Number: live under
the shipped detector (47 -> ?) and under the PU.48 candidate (41/39/0.951 -> `pump-092` correct or
abstained); slicer count agreement (237/251). Evidence: items 3 and 4 of section 5. Ceiling: PU.34's
25 value-changing miscounts on 117 role-right rows, so up to ~20 cells on the live path if every one
recovered; a realistic move is **+5 to +15**, inferred. **The correction**: PU.55 measured that on
`pump-092` the slicer's *own* ink band already runs rows 6..95 of 96 - the band computation is what
the bezel poisons. A trim "to the band it already computes for polarity" (the brief's words) is
therefore a **no-op on the motivating still**. PU.58 must estimate the band from something the
bezel does not lift - the LCN'd ink at a stricter row threshold, or the glyph-body statistic the
slicer already has - or it will reproduce `PumpBoxRefiner` (PU.33: box tightened to its ink band
before slicing, measured 22 -> 21, deleted in PU.35). Falsifiers: the padded-strip test's break
ratio; `pump-092` unchanged; live under the shipped detector moving by less than 3 (inside seed
noise; then close it as PumpBoxRefiner was closed).

**4. PU.59 - the ruled caution tier, with the risks in section 11 written into its brief.** Number:
verified tier >= 47 at 1.000 (must hold), cautioned tier committed / correct / precision printed
with the six stills named. Evidence it moves: by construction, exactly the 6 `priceUnvalidated`
stills (12 cells). Falsifier for the *ruling's premise*: the cautioned precision. If it is near
0.2 (section 11's arithmetic), the caution tier is the app's largest source of wrong pre-fills and
the owner should see that number before the sheet ships.

**5. PU.56, scoped down to the instrument.** Number: none; it is what makes ceilings computable.
Build the per-still JSON ledger (committed triple, per-field correct/wrong, reason, make, split) and
`pump-live-diff.py`; skip the protocol prose. Evidence: PU.53's ceiling was 2 stills (the row said
5), PU.54's was 9 (the review said 26), PU.55's was 2 cells - all three were computable from a
per-still ledger before dispatch. Falsifier: the differ's tests. I would NOT put PU.56 *before*
items 1-3, because those three are already priced; I would require it before any further classifier
or detector round, because those are the rows whose ceiling nobody has computed.

**6. Re-point the ship gate at the reader.** Number: `pumpAlpha` and `PumpPhotoGate.allowsPumpPhoto`
read the reader's verified tier. Evidence: `PumpPhotoGate.swift:39-64` carries 53/56/865 - the rules
parser's score - and `AccuracyRatchetTests.swift:278-286` asserts those constants against the rules
parser's corpus run; `CapturePipeline.swift:95-96` decides the alpha notice from it. The reader's
tiers live only in `PumpReaderPipelineTests`. This is `docs/DEFECT-PATTERNS.md` §3 exactly: a
constant that names a behaviour with no call site to the thing that runs. Falsifier: a test that the
gate's coverage equals the pipeline test's live coverage (0.257 today) - the gate then says
*"off, 0.257 < 0.60"* for the right reason. Without this, PU.6 cannot flip on evidence.

**7. One Capture Lab session on a phone (PU.39 exists; RV.295 is the row).** Number: capture ms,
pipeline ms, path, per preset, on an iPhone 12 if one exists. Evidence: none exists from a device,
and the rules parser's 53 -> 13 across macOS versions says the runtime matters. Falsifier: a
pipeline time over 1 s on the floor device - then "faster" is a real problem and its stage is named
by `timingsMs`. Owner's action, no code.

**8. A second frozen heldout draw, for the owner to decide.** Number: the sampling noise on the
yardstick. Evidence: PU.32's review computed that at 175 cells *"+-13 cells is the noise band"*,
and the whole recent history (37 -> 39 -> 43 -> 47) is inside it - exact on the fixed set, but not
evidence the app got better for a user. Decision 9 says a still a model trained on never moves to
heldout; batches 6-9 (`pump-242`..`318`, ~100 stills) have not been trained on by any *shipped*
model (round 6 trained on the 2026-09-20 export of 148 stills; PU.33 on 153). A second frozen draw
of ~60 from them, never redrawn, doubles the yardstick under decision 9's own rule. Falsifier: the
live coverage on heldout-2 within a few points of 0.257 confirms the first set is representative;
a large difference says it is not, which matters more. This is the owner's call because decision 9
is the owner's.

Not on the list, deliberately: any classifier or detector retrain (section 9).

---

## 9. What to stop or cut

| row | status today | verdict | why |
|---|---|---|---|
| **PU.41** Round 11b (classifier retrain) | `[~]` | **close unbuilt** | 13 classifier candidates since round 6, 0 shipped; live rose 0 -> 47 with the classifier frozen; annotated precision sits at 0.991 against a 0.99 floor, so a retrain that buys coverage at any precision cost is refused by construction (round 10: every seed +4-6 cells, 1-3 wrong). Reopen only when the oracle-box tier says the read stage, not the box, is the bottleneck. |
| **PU.48** detector retrain | `[~]` | **close as measured** | refused twice (margin and geometry verifiers), and by PU.57's gate; round 10's detector on 926 images also moved nothing; the detector's IoU ceiling is the annotation noise it learned (0.80 = the hand quads' own 0.75-0.79). A future retrain needs consistent boxes first (the annotator's "keep shape" rule is the start), not more frames. |
| **PU.53** orientation search | `[ ]`, built in `tb-pu53` | **merge the test half, do not wire the search into the app** | 43 -> 43 at every arm; the app already receives an upright frame (RV.49) so the case is a sideways *display* in an upright frame: **2 of 68 heldout, 5 of 318 corpus**; the search adds two detector passes and a second read on every photo whose seeded read commits nothing (50 of 68). Keep `livePath` not reading the annotation's rotation - that is the honest-floor fix and it is worth having. |
| **PU.55** clip guard | `[ ]` | **close; already refuted** | `REPORT.md` PU.55: the signal does not exist; both literal guards fail. Its re-scope is PU.58. |
| **PU.49** tilted display | `[ ]` | **park until a corpus of angles exists; fix the id collision** | two oblique stills, no measurement; the fix shape is a detector retrain (refused twice) plus a retry (latency for the failing photos). The row's own text says it needs the angle set first. Also: `PU.49` is used twice - the cut hanging-comma row (`docs/TASKS.md:635`, `TASKS-DONE.md:704`) and this one (`docs/TASKS.md:143`). |
| **PU.19** fusion | closed | keep closed | +1 cell at 45x (`REPORT.md` PU.19). |
| **PU.5** end to end | `[ ]` | **close as delivered** | delivered by PU.22, 24, 29, 33 (row rot, `DEFECT-PATTERNS.md` §5). |
| **PU.34** read stage | `[ ]` | **close as delivered** | `REPORT.md` PU.34 records both fixes shipped and measured (22 -> 23). |
| **PU.36a/b/c** SQLite-first | `[ ]` x3 | **re-status** | `REPORT.md` PU.36b is a shipped section with counts reproduced; `HANDOVER.md` treats the database as the write store. Whatever is genuinely left of 36c should be the only open row. |
| **PU.24** | `[x]` but text says partial | fine | closed 2026-09-21 in its own text. |
| **PU.40** production preset | `[~]` | not cut - it is the owner's lab session | section 7. |

And two things to stop that are not rows:

- **Stop calling the package suite's red "pre-existing".** Every PU checks table since PU.47 records
  `swift test` exit 1 (PaddleOCR, CorpusAB, RV.277, RV.49, `pump-300`, and now PU.23's floor). A
  ratchet whose red is normal catches nothing (`DEFECT-PATTERNS.md` §7): PU.60 sat red and unfiled
  until two agents tripped on it from unrelated rows. Hard rule 14 says exit 0 or it is not done.
- **Stop dispatching a fix row before its population is counted.** Section 10.

---

## 10. The method, not the backlog

**Is the unit of work wrong?** Partly. "One row = one component change, measured on the floor" is
fine when the row's target population is known. What went wrong in the no-op rows is that the
population was assumed: PU.53 assumed five heldout stills (two are heldout; `split.csv` lines 21-24
mark `pump-020/021/022` as `train`, and the worktree's own report table lists all five as if they
counted); PU.54's brief assumed 26 stills (9 had a read pair, 3 validate); PU.55 assumed a signal
nobody had measured on a strip. Each was computable from the tree before dispatch in under an hour,
and each would have re-ranked the row.

**Is the scalar floor the cause, as PU.56 argues?** No - section 3. The floor refused fifteen
candidates correctly. What the floor cannot do is *explain* a refusal, and that is what PU.56's
ledger adds. So: build PU.56's instrument, but do not expect it to end the pattern; the pattern ends
when rows are priced before they are built.

**Should PU.56 come first?** Before any further model round, yes. Before items 1-3 of section 8,
no - those are already priced by the measurements in hand.

**What I would change, routed to `docs/DEVELOPMENT-TIMELINE.md`** as one entry, because it is a
change to how this work is chosen and measured:

> **2026-09-22 · A pump-reader row states its ceiling before it is dispatched.** Every PU build row
> names the heldout stills it targets (by name, from the per-still ledger) and the maximum number of
> live cells it can move if it works perfectly on every one of them. A row whose ceiling is inside
> the noise band (+-2 cells seed noise, `REPORT.md` round 10; +-13 cells sampling noise at 175-183
> cells, PU.32's review) is dispatched as a **measurement**, never as a build; a model round is
> dispatched only after the stage it retrains is shown, by the oracle-box tier, to be the bottleneck.
> **Evidence**: PU.53 (ceiling 2 stills, moved 0), PU.54 (ceiling 9 of the 26 assumed, moved 4),
> PU.55 (ceiling 2 cells, refuted), PU.19 (+1 at 45x), rounds 7-11 and PU.48 (15 candidates, 0
> shipped) against PU.33/35/42/54 (each started from a counted table and moved the number).
> **Also**: the basis of every reported number (heldout count, asserted cells, slicer and corpus
> commit) is written in the table row, because four basis changes in three days made the ledger's
> rounds non-comparable (section 2 of this review).

Two smaller method notes. (a) The `PUMP_*` opt-in diagnostics (`PUMP_LIVE_DIAG`, `PUMP_DECOUPLE`,
`PUMP_FUSION`, `PUMP_ORIENT`) are the right instruments and are never in a checks table; the
oracle-box tier belongs beside them. (b) `PumpReaderTestSupport.detectorURL` reads
`ml/pump-reader/.out/det/DigitRows.mlmodel`, not the bundled resource (PU.48's finding, still open):
a candidate is scored by overwriting the dev copy. That is how a mix-up between PU.48's two exports
happened (PU.57's finding). A `PUMP_DETECTOR=` override like `PUMP_MODEL=` closes it in one line.

---

## 11. The risks of what is already ruled (PU.59)

The ruling (decision 11, second amendment) is the owner's and is not relitigated here. What it will
cost, from the numbers in `REPORT.md` PU.54, so it can be watched:

**1. The cautioned tier's precision on the heldout will be low - near 0.2 by arithmetic.** PU.54
measured the band-only pair path at **59 committed / 49 correct (0.831), with six confident-wrong
stills - `pump-019`, `032`, `104`, `120`, `125`, `187` - all role-assignment misses or misreads**,
and then measured that the validated pair path commits **47 / 47** with **6 stills refusing as
`priceUnvalidated`**. The difference between the two runs is 12 committed cells of which 2 are
correct and 10 wrong; PU.54 also states the six wrong stills *"have no board at all (or one
40-140 % away)"*, which is precisely the `priceUnvalidated` condition. I infer - and PU.59's own
print will confirm or refute - that the six cautioned stills are the six wrong stills, and the
cautioned tier lands at about **2 of 12 cells correct**. The amendment's sentence *"against the
alternative of 12 fills the user must retype from a photo the app read correctly"* is, on this
corpus, the reverse of what was measured: the unvalidated pairs are mostly NOT read correctly.
**What to watch**: the cautioned precision the split gate prints, with the six named. If it is under
0.5, the caution is the app's largest single source of wrong pre-fills, and the owner should see
that number before the sheet ships. PU.60 first (item 2 of section 8) is the mitigation the row
already names: `pump-032`'s wrong pair is an assignment miss.

**2. The F2 residue is the majority case here, not a residue.** F2's table (`docs/JOURNEYS.md` F2)
is built around the cross-check refusing to lock and the user tapping the amber field to see the
crop. A cautioned pair has no cross-check at all (two numbers, no third), so the amber state is
"unverified", not "these don't multiply up", and the user has no arithmetic reason to look. The
mitigations F2 names for the consistent-wrong case - the odometer delta and the consumption outlier
on save - are what will catch a wrong cautioned pair, and neither is pump-specific. PU.59's brief
should say which of the two fires on a factor-of-ten volume, because that is the wrong value the
pair tier produces (`pump-032`: 0.647/L implied).

**3. The rules arm fills the field the reader abstains on, at 0.946.** `CapturePipeline.swift:76-83`:
`assembly.extraction.unitPrice = pumpReading.extraction.unitPrice ?? assembly.extraction.unitPrice`.
Under PU.54 a committed pair carries `unitPrice: .abstained(.priceDisagrees)` (`PumpReadingLaw.swift`,
`pairOutcome`), so the price field on the form is filled by `PumpExtractor` - the Vision-plus-rules
pump path whose precision is 0.946 on macOS 26 and unknown on the phone (RV.295: three confidently
wrong totals on macOS 27). The reader's 1.000 is therefore not what the user sees on a pair: it is
the reader's two fields plus the rules arm's third, and the `crossCheck` on the assembly is the rules
arm's own outcome over its own triple (line 79 only promotes to `.lock` when the reader committed
three). This is `DEFECT-PATTERNS.md` §2 - a fallback reachable by the ordinary path. PU.59's brief
does not mention it. **What to do**: on a `.pumpPhoto` prefill, the rules arm's pump fields should
fill only what the reader did not *refuse* - a field the reader abstained on with a reason is not
blank, it is refused - or at minimum the cautioned notice must cover the rules-arm price too.
Inferred from the code; a test that a reader-abstained price stays empty is the falsifier.

**4. The verified tier's floor must not be allowed to blend.** The row says so; the checks table
should print both tiers on separate lines and the `#expect` on the verified tier should be `== 47`
exactly, as PU.54 left it, not `>=`.

---

## 12. PU.6 - the ship decision

**Ship on: no, on the gate's own rule.** Live coverage is **47/183 = 0.257** against 0.60, and the
gate's precision bar is met only because the law refuses 50 of 68 photos. The reader's read stage
clears both bars on oracle boxes (0.612 at 0.991), which is the reason to keep going, not a reason
to ship.

**Ship off: no, on the evidence.** Decision 7 (2026-09-19) already ships the reader in every build:
a display runs the reader, the committed fields pre-fill under the alpha notice, typing beside them.
On the heldout it has produced zero wrong pre-fills (47/47). Turning that off would remove a correct
head start on 16 of 68 photos to prevent a harm the corpus has not shown - and would not remove the
harm that IS there, which comes from the rules arm's fill-through (section 11.3), which runs whether
or not the reader does.

**So PU.6's honest answer today is its second branch, written out**: *"the measured gap, by failure
mode and by make, is written into EXTRACTION.md and the next row is filed from it."* Sections 2, 3
and 5 are that gap. Before the first branch can ever be taken, four things are missing, all cheap
and none a model round:

1. **The gate reads the reader** (section 8 item 6). Today `PumpPhotoGate` is the rules parser's
   53/56/865 asserted against the rules corpus; the reader could hit 0.99/0.60 and `pumpAlpha` would
   stay true. Until this is fixed the ship decision has no instrument.
2. **The gap is apportioned** (section 5, runs A and B). Whether 0.60 live is reachable with the
   current detector is a question the oracle-box tier answers in two suite passes.
3. **A device number exists** (section 7). The iPhone 12 floor and a 30 MB detector through Vision
   have never met; PU.39 was built for this.
4. **The yardstick is big enough to see a 0.60** (section 8 item 8). At +-13 cells, 0.60 of 183 is
   110 +- 13; the second draw halves the band.

And two things PU.6 should record whichever way it goes: the detector's **30.3 MB** in the bundle
(PU.33 left its size as "the owner's call before ship"; it has been in every build since) and the
**`captureKind`/`kind: "pump"`** ledger evidence that a real user's pump photos are reaching the
reader at all - the gateway ledger records `kind`, so the count of `pump` calls in production is
the one number that says whether the door is being walked through.

---

## 13. Contradictions found, against `REPORT.md` and `docs/TASKS.md`

Each quoted, with why it is wrong:

1. **PU.53's row and report: "Five heldout stills carry a rotation (`pump-019`, `020`, `021`,
   `022`, `023`)"** (`docs/TASKS.md` PU.53; `tb-pu53/ml/pump-reader/REPORT.md` PU.53: *"Five heldout
   stills carry `rotationCW: 90` ... all reviewed"*). `Spike/ReceiptSpike/fixtures/pump/split.csv`
   lines 21-24, identical at the worktree's base `82398950` and at `HEAD`: `pump-020`, `021`, `022`
   are **`train`**; only `pump-019` and `pump-023` are heldout. The report's per-still table lists
   all five as if they were in the 52. Its committed number (43) is right because `isHeldout` filters
   the three out; its stated population is wrong by a factor of 2.5, and the brief for this review
   inherited it ("all five rotated stills refuse at their correct orientation too").
2. **The brief's reading list: "Read the PU.52, PU.55 and PU.53 sections [of `REPORT.md`] closely."**
   `REPORT.md` at `HEAD` has no PU.52 section (PU.52 is a review file, referenced at lines 1795 and
   1893) and no PU.53 section - PU.53's section exists only in the uncommitted `tb-pu53` worktree
   (its line 1983).
3. **PU.52 §5 item 2: "Moves ~26 of the 53 abstaining stills."** PU.54 measured the population at 9
   stills with a read pair, 3 validated: +4 cells. The review divided `boardFoundNoPrice` by nothing.
4. **Decision 11's second amendment: "against the alternative of 12 fills the user must retype from
   a photo the app read correctly."** PU.54's own measurement (section 11.1) says the 12 cells are
   10 wrong and 2 right. The ruling may stand on other grounds; this sentence does not.
5. **`docs/TASKS.md` row status vs the ledger**: PU.34 `[ ]` (shipped and measured in `REPORT.md`
   PU.34), PU.36b `[ ]` (shipped, `REPORT.md` PU.36b), PU.5 `[ ]` (delivered by PU.22/24/29/33),
   PU.55 `[ ]` (refuted, nothing to build). `DEFECT-PATTERNS.md` §5.
6. **`PU.49` is two rows**: the cut hanging-comma row (`docs/TASKS.md:635`) and the open tilted-
   display row (`docs/TASKS.md:143`). The index carries both under one id.
7. **`REPORT.md` round 11: "68 heldout stills / 186 cells"** vs **PU.51: "coverage 0.235 of 183"**
   and PU.54's 183. Three cells moved with a corpus session; no row records which.
8. **`REPORT.md` PU.48 vs PU.47's re-score name different files as "PU.48's candidate"**
   (`d18531eb` vs `f48991f4`) - already recorded by PU.57; still unreconciled in the PU.48 section.
9. **The brief's state table: "PU.53 ... three of them with `boardFoundNoPrice`"** - true of the
   worktree's five-row table (019, 022, 023), but only 019 and 023 are heldout, so the PU.53 + PU.54
   combination the brief calls "unmeasured and might move" has a ceiling of **two stills**, and
   PU.54's validated-pair path needs a shown price near the implied one, which `pump-019` at its
   correct orientation still lacks (`boardFoundNoPrice` at 90 in the worktree table).
10. **`HANDOVER.md` "The reader's state"** still lists as next steps *"(2) decouple the verifier"*
    (PU.47, shipped) and *"(3) retrain `DigitRows`"* (PU.48, refused twice). Stale.

---

## If I could do exactly three things

1. **Run the oracle-box tier and the vertical-only swap on the 68 heldout stills (read-only, two
   suite passes) and write the 112 -> 47 apportionment into `docs/EXTRACTION.md` decision 10 before
   any further PU row is briefed** - it prices PU.58, PU.60 and every locator idea, and it is the
   experiment PU.52 asked for and nobody ran.
2. **Land PU.60, then PU.59 with the cautioned tier's precision printed and its six stills named,
   and re-point `PumpPhotoGate` and `pumpAlpha` at the reader's verified tier instead of the rules
   parser's 53/56/865** - so the ship decision finally has an instrument and the user-facing risk
   is measured, not assumed.
3. **Close PU.41, PU.48, PU.55, PU.5, PU.34 and PU.53's app half unbuilt or as-measured, park PU.49,
   and put the freed effort into one Capture Lab session on a phone and a second frozen heldout draw
   from batches 6-9** - because fifteen trained candidates in three days shipped nothing, and the
   two numbers the ship decision still lacks are a device time and a yardstick with less than a
   +-13-cell noise band.
