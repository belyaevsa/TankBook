# PU.68 completeness review - second pass (review 1 was INCOMPLETE)

Run 2026-09-23 against the working tree on HEAD `7673612b` (base `c86755d6`; the concurrent
annotator session committed `afb611a0` and `7673612b` between the two passes - pump trace work,
excluded from this review by the brief). Research note: `agents/research/PU.68.md`. Review 1:
`agents/reviews/PU.68-COMPLETENESS.md`. Diff under review: the five test files named in the brief
and the PU.68/PU.78/PU.69/PU.79/PU.80/RV.304 rows in `docs/TASKS.md` plus `docs/EXTRACTION.md:901`.

**What I ran**: read-only git/grep/log inspection; an independent Python recomputation of every
bound the shipped code prints (same algorithm as the code: lgamma PMF, 100-step bisection); a
duplicate-prefix scan of `split.csv`; `swiftlint lint` from the repo root (exit 0, warnings only);
`scripts/tasks-index.py --check` (exit 0) and `scripts/scenario-index.py --check` (exit 0, "526
rows, every open one attached"). No builds, no test runs, no writes except this file. I did not
need `swift run PumpReadTool` - no number was missing, so machine load affects nothing I report.

**Independent arithmetic check** (all exact to 4 decimals against the logs and the note):
the note §4 table (45/45 [0.9213, 1] / 0.9433 / 0.9356; 51/52; 54/54; 111/112), the pipeline
log's annotated line (110/111 [0.9507, 0.9984] / 0.9606 / 0.9580), the train line (117/124
[0.8881, 0.9724] / 0.8990 / 0.8966), every photo line (0.8627, 0.7971, and 0.9456 in the mutated
run), every UCB (0.2108 / 0.1884 at 5 of 47; 0.1034 / 0.0931 at 7 of 124; 0.0618 / 0.0478 at the
mutation's 0 of 47; the whole §5.1 reachability table; F3's 0.0119 > 0.01), and CP 45/45 =
0.05^(1/45) = 0.9356. The **Wald-mutation log's ten values match the Wald-centred formula to 16
decimals** - the red output is genuine and the mutation was what the row says. The restored
formula reproduces every value `PumpPrecisionBoundsTests` asserts, inside its 6e-5 tolerance, so
the restored suite's green is arithmetic, not just an orchestrator claim. **Population spot-check**:
`split.csv` holds 329 stills with **no duplicate 8-character prefixes** (the tally assertion's key
is collision-free today), 4 `heldout2` entries (pump-322/323/327/328), and no code anywhere reads
the string `heldout2` - `isTrain` requires "train" and `isHeldout` requires "heldout"
(PumpReaderTestSupport.swift:83-85), so the second frozen draw stays frozen and unconsumed.
Fixtures, `ios/App` and `ml/` are untouched between `c86755d6` and HEAD, so the corpus the gate
measured is the corpus that ships.

## The six items of the second pass, verified one by one

1. **Fusion and decoupling print the interval - CLOSED.** `precisionLine` now prints in the
   fusion's local `report()` (PumpReaderPipelineTests.swift:422 - all four arms go through it) and
   in the decoupling's `line()` (:501 - both models). A grep of the file finds exactly four
   precision prints (:268 gateMirror, :419 fusion, :499 decoupling, :621 report) and each is
   paired with a `precisionLine` (:271, :422, :501, :625). The Checks-cell "every" and the Built
   text are now true as written; every report also carries a per-photo count line (gateMirror :269,
   fusion :420, decoupling :499, report :628-629 - the photo-unit Wilson bound itself prints only
   in `report()` :626-627, which is where the photo-unit certificate lives, correctly).
2. **`PUMP_DETECTOR` exercised - CLOSED.** `/tmp/agentlogs/pu68-detector-override.log`, three arms
   on `PumpDisplayCaptureTests` (the "PU.38 heldout classification" print, PumpDisplayCaptureTests.swift:94):
   unset 5/6 and 9 tests pass (:1-3 - same 5/6 the full run shows, pu68-swifttest.log:5750);
   `pu66c` candidate 4/6, suite red with 4 issues (:4-6) - the switch verifiably steers the
   measurement and the floors catch the regression; nonexistent path stops the run with
   "Precondition failed: PUMP_DETECTOR names no file: /nonexistent/DigitRows.mlmodel" (:7-9), the
   new precondition at PumpReaderTestSupport.swift:32. The dev copy was not touched: its mtime is
   Sep 22 18:52, the candidate is its own file (`.../det/pu66c/DigitRows-pu66c.mlmodel`, Sep 23
   04:08). Review 1's silent-`nil` failure shape is gone.
3. **The tally assertion plus its mutation - CLOSED.** `trainSplitRiskBound` now asserts
   `m.photosWrong` equals the distinct photo prefixes in the wrong list
   (PumpReaderPipelineTests.swift:152-156). Mutation (`photosWrong += 0`):
   `/tmp/agentlogs/pu68-mutation-photosWrong.log` re-ran the whole 1703 s certificate, printed
   "47 committing, **0** with a wrong cell" (:14) against the same 7-line wrong list (:32-38), and
   went red at :155:9 - "photosWrong 0, photos named in the wrong list 5" (:41-45); the mutated
   run's UCBs (0.0618/0.0478 at k=0, n=47) recompute exactly, so the log is internally consistent.
   Review 1's "delete the increment and every test stays green" is no longer true.
4. **Comments and EXTRACTION.md - CLOSED.** The certify doc comment now says "the reviewed train
   split (244 stills at the 2026-09-23 corpus), ~30 minutes in Debug"
   (PumpReaderPipelineTests.swift:123-124) - matching the observed 29.8/28.4-minute runs and the
   runs' own "34/244 ... of 670" prints; the leak header names the four currencies and why ("the
   phone's locale - not the photo - picks the currency", PumpLeakConsequenceTests.swift:8-10),
   matching the `currencies` constant (:17); `docs/EXTRACTION.md:901` now reads "Wilson two-sided
   95 %; the one-sided 95 % lower bound is 0.943" - the correct labels for 0.9213 and 0.9433. The
   Qwen review file was left alone, as review 1 directed.
5. **Row updated, Wilson mutation captured - CLOSED.** The row now says the owner **created**
   `heldout2` in `c86755d6` (verified: the commit message and split.csv:323-329) and records the
   re-counted train population "244 reviewed stills, 670 cells (the note counted 250/668 at
   `310e7660`)" - both certify logs print exactly that. `/tmp/agentlogs/pu68-mutation-wilson.log`:
   10 issues, every value Wald-centred to 16 decimals (above); the count decomposes 2+3+2+3 over
   the four table cases with the two x=n uppers and all CP assertions untouched - exactly what a
   centre-only mutation must produce.
6. **The pre-existing reds filed - CLOSED.** PU.79 (docs/TASKS.md:1066, index :167): the annotated
   floor 111 vs 112, attributed to PJ.500/`bdca96a9`, the wrong cell pump-055 unchanged (matches
   pu68-pipeline.log:19-24), checks include naming the flipped cell, floor-or-law reconciliation
   with the reason in the comment, correcting PU.65's stale "annotated 112/111" (:1061), and the
   suite green again. PU.80 (:1067, index :168): both sweep arms, the 2x57 issue lines I counted in
   the log (PaddleOCRTests.swift:37, CorpusABTests.swift:93), the owner's PaddleOCR retirement
   approval quoted verbatim, and the intake-skill rule. RV.304 (:960, index :104): the expense
   contradiction red since 2026-09-21 (log :2715), fixture and category named. All three carry
   scenario tags; both index scripts exit 0 with them.

## Checklist items

### Item 1 - fidelity to the published method: **MET**

No formula changed since review 1's line-by-line verification; the second-pass diff is prints, one
guard, one env override and one internal-consistency assertion. I re-derived every printed number
from the shipped code's own algorithm (above) - all exact. The adaptation ledger still holds on the
current file: A1 the certificate is a fixed-threshold LTT test, never CRC/RCPS lambda-selection
(doc comment PumpReaderPipelineTests.swift:117-121; "does not certify <=" phrasing :148); A2
labelled IN-SAMPLE in the comment (:122), the report label (:137) and the row; A4 the photo is the
loss unit - binary UCB primary (:140), cell UCB printed and labelled "cells within a photo are not
independent - secondary" (:141, :145-146), fractional-loss HB labelled secondary (:142-144); A5
delta 0.05 and 0.10 both printed (:139); A6 two-sided beside one-sided in every precision line
(PumpPrecisionBounds.swift:89-94), the gate itself untouched; A7 Wilson/CP estimate
(`precisionLine` :87-95), exact binomial certifies (`binomialUCB` :65-68, used only in the certify
print), roles uncrossed anywhere including the new fusion/decoupling lines; A8 scorer tolerance
inherited unchanged (:600); A10 reachability in the row ("268 clean commits needed, 183 cells
exist"). F3 asserted live (PumpPrecisionBoundsTests.swift:52); F4 held observationally (0.2108 vs
0.1034 on a run with two 2-cell photos). The precondition on a bad `PUMP_DETECTOR` path involves no
paper (note §3.5 says so) and implements review 1's own finding - not a departure. **No unlisted
departure found.**

### Item 2 - wired into the app path (as re-scoped by the brief): **MET**

The diff is test-bundle code and docs only; `PumpPhotoGate.swift`, `ios/App` and every
`#if DEBUG` seam are untouched (git status), so no RELEASE gate is owed (note §7). The instruments
measure the app's own seams: the certificate builds its reader through
`PumpDisplayCapture.makeReader` (PumpReaderPipelineTests.swift:128-129) - the factory
`CapturePipeline.swift:28` calls - and scores through `PumpDisplayCapture.classify` via
`measureLive(appPath: true)` (:134-136, classify at :567; the app's call site
CapturePipeline.swift:131). The leak test does the same (PumpLeakConsequenceTests.swift:30-31,
:44-45, :50-52). The concurrent HEAD commits added a defaulted `trace: PumpTrace? = nil` to those
entry points: signature-compatible with every instrument call site, and the "pump trace parity"
suite passed inside the full run (pu68-swifttest.log:5742), so the measured numbers stand against
the code that will be committed. No test-only reader anywhere.

### Item 3 - measured on the app path, on the named population: **MET**

`livePath` passed twice: in the filtered gate run (pu68-pipeline.log:41, 571.5 s) and inside the
full suite (pu68-swifttest.log:5771, 660.1 s) - both 45/45 of 183 with the interval beside the
point estimate (:26), and the run asserts equality with `PumpPhotoGate.readerCommitted` /
`readerCommittedCorrect` / `readerNumericTotal` = 45/45/183 (PumpPhotoGate.swift:86, :91, :95;
asserts at PumpReaderPipelineTests.swift:97-114). The certificate ran on the population the row
names (reviewed train; its own prints say 244 stills / 670 cells). Every number in the row's
Measured text appears verbatim in the logs and recomputes exactly. **Zero new wrong readings**:
heldout live 45/45; the annotated arm's single wrong cell is pump-055 56.09 for 56.05
(pu68-pipeline.log:19) - the same cell and values as PU.54's run at 112/111 (review 1 verified
against /tmp/agentlogs/PU.54.log); the seven train-split wrong cells are in-sample measurement,
not shipped behaviour, and all seven are named in the row and owned by PU.78 (log lines :62-68
match the row's list value for value).

### Item 4 - no regression elsewhere: **MET**

The diff changes no routing, law or reader code, so nothing behavioural can move. Leak: the PU.29
classification suite is green in the full run (pu68-swifttest.log:5754, "0/8 receipts leaked"
:5750), and the new worst-case ratchet (ceiling 6, commits 0, fixture named on failure,
PumpLeakConsequenceTests.swift:23-24, :66-68) turns review 1's "did not rise" into an enforced
number - the 6-of-116 is the stricter uncapped-budget configuration and the row says so. Law's
oracle ratchet held: PU.21 suite green (:5477), oracle print "committed 771, correct 770 ... of
889; wrong: [pump-031]" (:2275) - the declared csvDisagrees artefact. PU.4 harness green (:5738).
The annotated floor (111 < 112) is red and pre-existing - review 1 attributed it to PJ.500's
`bdca96a9`, PU.79 now owns it, and PU.68's only change to `gateMirror` is the interval print
(:271), which cannot move a count. Latency: no hot path touched; no Release number owed or
claimed.

### Item 5 - tests that would fail: **MET** (was PARTIAL)

Every promise now has captured red output, and I verified each log's arithmetic:
- Wald-centred Wilson mutation: red, 10 issues, values exact to 16 decimals
  (pu68-mutation-wilson.log); the suite ran green on the pre-mutation code inside the full run
  (pu68-swifttest.log:5528), and the restored code reproduces every asserted table value
  (recomputed), so the restore is that same code.
- `photosWrong` zeroed: red at :155:9 naming both counts (pu68-mutation-photosWrong.log +
  -summary.log); the mutated run's own UCB prints are the k=0 values, internally consistent.
- Leak routed ceiling: red for real at 6 > 5 with all six fixtures named (pu68-leak.log:8, :2-7).
- `PUMP_DETECTOR`: the candidate arm red with 4 issues and the precondition stop
  (pu68-detector-override.log) - removing the env read would now contradict a captured run.
Two honest caveats, at the standard review 1 itself set ("arithmetic on the observed counts"):
the shipped leak ceiling combination (6/0 behind `PUMP_LEAK=1`) has still never been observed
green - the pre-gating run observed 6 routed / 0 commits, so green is 6 <= 6 and 0 <= 0; and the
shipped certify combination (assertion + restored aggregation) has not run green end-to-end - the
19:53 green run predates the assertion and the 21:21 run had the mutated aggregation, but the
restored aggregation was observed producing 5 (:44 of the 19:53 run) over a wrong list with 5
distinct prefixes, and the assertion itself was observed compiled, evaluated and firing, so the
equality is arithmetic on two observed runs. Neither is a reason to hold the commit; both are
recorded so nobody mistakes them for observed green.

### Item 6 - docs reconciled: **MET** (was PARTIAL)

`docs/EXTRACTION.md:901` fixed and it is the doc's only Wilson mention (grep). The TASKS row's
Built/Measured/review-1-closed text is faithful - every figure checked against the logs, the
heldout2 tense corrected, the 244/670 re-count recorded, and each of the four "closed" claims
independently verified above. PU.79/PU.80/RV.304 filed with index rows (:104, :167, :168) and
scenario tags; `tasks-index.py --check` exit 0; `scenario-index.py --check` exit 0 (526 rows).
The row is unticked, correctly. `docs/ERRORS.md` and `docs/JOURNEYS.md` correctly untouched -
nothing user-visible changed. Comments in the touched files: both stale claims review 1 named are
fixed; what remains (research-note citations as authority links, `PU.nn` print labels, the
floor/ceiling provenance comments, observed durations on opt-in tests) is this harness family's
established convention as review 1 adjudicated, and the new comments state enforced or observed
facts only - the precondition comment (:28-29 of PumpReaderTestSupport.swift) describes behaviour
the code enforces three lines later (:32). Lint: `swiftlint lint` from the root exits 0, warnings only; the
five PU.68 files carry the family's `identifier_name` class for formula symbols.

### Item 7 - everything the row promised, sentence by sentence: **MET** (was PARTIAL)

| Checks-cell sentence | Verdict | Evidence |
|---|---|---|
| "Every precision the pipeline tests print carries its Wilson interval" | **MET** | All four precision prints paired with `precisionLine` (PumpReaderPipelineTests.swift:268/:271, :419/:422, :499/:501, :621/:625); grep finds no bare precision print left in the file. The Built text's "every pipeline report prints the interval and a per-photo line" is now true as written (per-photo counts at :269, :420, :499, :628). |
| "a conformal risk-control bound on the wrong-commit rate is computed on the TRAIN split and reported beside the heldout point estimate, method as the note derives it" | **MET** | :125-157 on `isReviewedTrain`; one gate log holds the heldout report (:25-27) then the train report and bounds (:42-70), labelled in-sample, never in place of; method fidelity per item 1, numbers recomputed. |
| "`PUMP_DETECTOR=<path>` scores a candidate without touching the dev copy" | **MET, exercised** | Code PumpReaderTestSupport.swift:30-37; three-arm log (second-pass item 2); dev copy mtime untouched; candidate at its own path. |
| "a test scores what each non-pump fixture routed as a pump COMMITS (fields, values' presence only - hard rule 12) and names them" | **MET** | PumpLeakConsequenceTests.swift:44-64: the app's `classify`, field NAMES only (:54-57), never values; ROUTED/COMMITS lines name every fixture (:61-64); observed run named all six routed, 0 commits, in the four currencies the row names. Caveat: shipped ceiling form not re-run since gating (item 5). |
| "A second frozen heldout draw is the owner's call, asked, not assumed" | **MET** | Nothing consumes heldout2 (no reference in any source or test file; both split filters exclude the value, PumpReaderTestSupport.swift:83-85); the owner created it himself in `c86755d6` and the row records exactly that. |

## The full-suite failures in pu68-swifttest.log - caused by the PU.68 diff?

**No - none of the 117 issues** (57 PaddleOCRTests.swift:37 + 57 CorpusABTests.swift:93 + 1
RV277ExpenseTotalTests.swift:115 + 1 CaptureOrientationTests.swift:41 + 1
PumpReaderPipelineTests.swift floor; I re-counted the issue lines: exactly 117). All predate the
base and all are now owned: the two sweep arms by **PU.80**, the expense contradiction by
**RV.304**, the annotated floor by **PU.79**. The CaptureOrientation `e5rtError` is the
concurrent-load flake class (the certify suite ran beside the full run; cf. `RV.203`'s note) -
unowned, and review 1 did not require a row for it; a solo re-run at the next gate remains the
cheap confirmation (finding 5 below). The 45-test localization run appended to the same log
passed (:5891), and the app-target unit bundle passed 301/301, TEST SUCCEEDED
(pu68-appunit.log:2597-2599).

## Findings I did not fix (none blocks the commit)

1. **The tally assertion keys photos by `prefix(8)`** (PumpReaderPipelineTests.swift:154). The
   current 329-still split has no duplicate 8-char prefixes (verified), so it is exact today; a
   future intake that adds a second still under the same pump number (the note §5.1(2) same-fill
   pattern, e.g. a `-reflection-b` twin of a numbered still) would make the assertion red when
   BOTH twins commit a wrong cell - a loud false red, never a silent pass. If PU.78 touches this
   test, keying on the full fixture name removes the corner.
2. **Two shipped combinations have never been observed green** (item 5's caveats): the leak
   ceiling form behind `PUMP_LEAK=1`, and certify-with-assertion. Review 1's ~45-minute
   `PUMP_LEAK=1` re-run remains "recommended, not required" and still open; the natural moment is
   PU.78's gate, which runs `PUMP_CERTIFY=1` anyway and will exercise the assertion for real.
3. **Gate evidence lives in `/tmp/agentlogs/`** and is volatile; the row cites one such path
   (`pu68-detector-override.log`). The durable record of every number is the row text, this review
   and review 1 - all three carry the figures, so nothing is lost on reboot, but a future reviewer
   will find the paths dangling.
4. **The `[exited with code 0]` wrapper annotation** at the tails of pu68-leak.log and
   pu68-mutation-photosWrong-summary.log contradicts the failure records inside them (review 1
   flagged the same artefact). The issue lines and "failed ... with N issues" are the evidence;
   the annotation is the tee/wrapper's exit code, not swift-test's.
5. **CaptureOrientationTests e5rtError**: re-run alone once at the next gate to confirm the flake;
   if it reproduces solo, it needs a row of its own (none exists today).

## Verdict

**COMPLETE.** All six second-pass items are closed with evidence that survives independent
recomputation; checklist items 1-7 are MET. The instrument is faithful to the published method
(every printed bound re-derived exactly, the mutation logs bit-exact against the mutated formula),
measures the app's own `makeReader`/`classify` path on the populations the row names, ratchets the
leak's worst case, and its promises each have a test that was observed red under mutation. The
full suite's 117 failures are pre-existing and every one now has an owning row. The five findings
above are recorded for PU.78/PU.79 and the next gate; none is a reason to hold this commit. The
orchestrator may commit PU.68.
