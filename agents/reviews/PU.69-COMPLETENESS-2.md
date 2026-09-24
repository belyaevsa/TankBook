# PU.69 completeness review, second pass - row angle by a fast Hough transform, with a confidence

Run of `agents/briefs/REVIEW-COMPLETE-PU.69-2.md` (template `REVIEW-PU-COMPLETENESS.md`), 2026-09-24.
Read-only except this file. Tree state reviewed: the uncommitted PU.69 diff (`PumpFastHough.swift`
new, `PumpRowDeskew.swift`, `PumpRowDeskewTests.swift`, `PumpRowDeskewCorpusTests.swift` new,
`docs/EXTRACTION.md:1111-1122`, `docs/TASKS.md:1072`) on top of HEAD `bd840ce4`, with the
concurrent uncommitted PU.78/PU.72/PU.81 edits and the PU.70/PU.71 cuts present. The PU.78 edits
are ignored as diff but acknowledged as the constants the suite now runs against (`PumpPhotoGate`
47/47/183 at `ios/Sources/TankbookCore/Config/PumpPhotoGate.swift:86,91,95`, `committedFloor` 118
at `ios/Tests/TankbookCoreTests/PumpReaderPipelineTests.swift:30`); the PU.70 cut is acknowledged
where PU.69's own text interacts with it (item 6).

**Evidence I generated myself** (all read-only: file reads, greps, two python re-counts over
`windows.json`/`split.csv`, `swiftlint lint` on the two changed source files, the two index scripts
with `--check`. I built nothing, ran no test suite and no `PumpReadTool` - every needed number was
in the captured logs. The owner's annotator may have been running; nothing I executed is
timing-sensitive):

- Population re-count from the working tree's corpus: **65 heldout reviewed rot-0 stills, 188
  transaction windows** - reproduces the F1 log's `n 188` exactly. `pump-275` carries **2**
  transaction windows and its `reviewed` flag is **absent** - 190 − 2 = 188 confirmed, and the
  "corpus state, not this diff" attribution of the two red floors confirmed at the source.
  Train reviewed: **255 stills** (F6's population).
- Read all six `/tmp/agentlogs/pu69-*` logs in full or by targeted grep; every number the row and
  the second-pass brief claim is quoted below against its log line.
- `swiftlint lint` over `PumpFastHough.swift` + `PumpRowDeskew.swift`: **no errors**; the only
  output is `identifier_name` warnings on single-letter variables - the new code's warnings are the
  same species as the HEAD file's own (`r`, `c`, `s`, `h`, `q` in `rowSize`/`rotatedRect`/`inside`),
  consistent with the file's mathematical style. Non-blocking; noted.
- `python3 scripts/tasks-index.py --check` exit **0** (index row `docs/TASKS.md:171` reads `[x]`);
  `python3 scripts/scenario-index.py --check` exit **0** ("PASS: 528 rows, every open one attached
  to a scenario"); the row carries `(J4 pump display photo)`.
- Timeline from mtimes, to settle what ran against what: mutation logs 03:03, app bundle 03:05,
  `docs/EXTRACTION.md` last written **03:04:24** (before review 1 - it has NOT been updated since),
  review 1 03:42, FHT Release log 03:46, old-sweep log and the final restores of
  `PumpRowDeskew.swift`/`PumpRowDeskewCorpusTests.swift` 03:49:11, full package suite ended 04:00
  (617 s run), `docs/TASKS.md` 04:03. The full suite provably compiled the FINAL tree, not the
  mid-swap old-sweep file: `transformAndWeight` calls `PumpRowDeskew.criteria`/`PumpFastHough.transform`
  and the corpus suite's F6 test references `PumpRowDeskew.Confidence` - neither exists in the
  reverted file, so the swap would not have compiled, yet both suites passed (`✔ Suite "Pump row
  deskew"` `pu69-swifttest.log:4897`, `✔ Suite "Pump row deskew on the corpus"` `:4353`). The current
  `PumpRowDeskew.swift` differs from the tree review 1 read only by the two comment fixes (+2
  lines - review 1's `:41`/`:185`/`:199` citations are today's `:43`/`:187`/`:201`), which are
  behaviourally inert; the mutation logs therefore still address the live logic (the mutated code
  and the tests that went red are unchanged).

## Second pass: the four claimed closures, verified

1. **Full package suite on the composite tree - CLOSED.** `pu69-swifttest.log:5300`: "Test run with
   **2285 tests** in 294 suites failed after 617.720 seconds with **2 issues**" - and both issues
   are exactly the two floors the brief names, both pure pump-275 population effects:
   - Annotated arm (`:5242`): "committed **116, correct 116, precision 1.000**, coverage 0.641 of
     **181**; photos with every field right **40/67**" - that is PU.78's own 118/118, 41/68, 183
     minus pump-275's 2 cells, 1 photo, 2 windows (my re-count above confirms the flag and the
     window count). Failure text (`:5247-5251`): `committed 116 >= committedFloor 118` - the floor
     counts pump-275, the population no longer does. Zero wrong readings.
   - Live arm (`:5274`): "PU.63 live path (the app's classify): committed **47, correct 47**,
     precision **1.000**, coverage 0.260 of **181**" - committed/correct match `PumpPhotoGate`'s
     reader constants 47/47 exactly (`PumpPhotoGate.swift:86,91`); the only failed expectation
     (`:5289-5294`, `PumpReaderPipelineTests.swift:112`) is `numericTotal 181 == 183` - again the
     pump-275 population, not a reading. pump-275's cells commit on neither arm of the live path
     (47 of 181 without it, 47 of 183 with it per PU.78's gate), so both runs triangulate: **zero
     new wrong readings anywhere in the tree**.
   - The rest of the claimed evidence is in the same log: oracle ratchet "committed **774**,
     correct 773, precision **0.9987**, coverage 0.8706 of 889" (`:3423`, the known pump-031 wrong
     cell - ratchet not fallen), fragility "**0.0412**" ≤ 0.10 (`:3544`), and `✔ Suite "pump trace
     parity" passed after 216.383 seconds` (`:5259`) - review 1's named end-to-end `.onRefusal`
     consumer of the new angle code, green on the final tree.
   - Commit-time caveat, stated so nobody is surprised: these two floors are red ONLY while the
     owner's uncommitted `windows.json` (must-not-touch per the standing fence) excludes pump-275.
     On the committed corpus the constants are the ones PU.78 measured green (47/47/183, 118/118).
     Do not commit the working tree's `windows.json` with this row.
2. **F6 - CLOSED.** `pu69-corpus-release.log:379`: "PU.69 F6 (train): good **458**, bad **108**;
   AUROC peakRatio **0.653**, dominance **0.689**, peakMass **0.700**" - Release ("Building for
   production" at the log head), the reviewed TRAIN split (`isReviewedTrain`,
   `PumpReaderTestSupport.swift:88`, train ∩ reviewed = my counted 255 stills), digit-for-digit the
   row text's report. The note's F6 falsifier is "AUROC ~0.5 ... nothing separates"; 0.65-0.70 is
   above it, and the row reports it honestly ("a modest, real separation, not falsified"). The new
   test is `PumpRowDeskewCorpusTests.swift:58-91`, thresholds exactly F6's (≤ 1 deg good, > 2 deg
   bad). This also closes review 1's item 5(d) in measurement form: `found.confidence` is read and
   `#expect(!good.isEmpty && !bad.isEmpty)` (`:90`) fails if confidence ever stops being populated -
   though only under `PUMP_DESKEW=1`, which is why the unit pin below stays on the list.
3. **Latency re-homing, sweep baseline log, leak argument - CLOSED except one number.** The row
   text now carries the explicit re-home ("The refusal-path latency promise is re-homed to PU.67's
   gate (it only exists where the retry runs); this row's evidence is the per-row step") and PU.67's
   open Checks already carry "a Release latency number for a refusal photo". The like-for-like
   baseline now has an artefact: `pu69-corpus-release-oldsweep.log:374` - "n **188**, median
   **0.73** deg, p90 **1.98** deg, mean 0.95 deg; >6 deg n **5** median **1.00**; **8.4 ms/row**",
   the same F1 test, Release. The leak argument is in the row text and I verified the code fact:
   `decideAt` (`PumpDisplayCapture.swift:192`) contains no deskew reference; the only deskew call
   sites in the file are the mode-gated retry AFTER routing (`:346-349`).
   **The exception:** the FHT-side per-row number. The captured Release log says **2.9 ms/row**
   (`pu69-corpus-release.log:377`); the row text and `docs/EXTRACTION.md:1119` both say **2.7**,
   and "2.7" appears in NO captured artefact (grep over all six logs: the only `ms/row` lines are
   8.4 and 2.9). 2.7 predates the kept log (EXTRACTION's mtime 03:04 vs the log's 03:46) and was
   presumably an uncaptured earlier run. The direction and magnitude of the claim survive either
   way (8.4 → 2.9 is 2.9x), but the point of keeping the log was to make the printed number
   traceable - printed and artefact must agree. Fix 1 below.
4. **Both comments - CLOSED.** `PumpRowDeskew.swift:26-29` now reads "The owner's hand quads top
   out near 10 degrees, but a detector row on a display shot from the side can be turned further
   (PU.65's tilted stills), so the search keeps room past the drawn range" - exactly the note §7-1's
   honest replacement, false "turned past 15 degrees" claim gone. `PumpRowDeskewCorpusTests.swift:9-11`
   now carries the like-for-like figures ("run through this same test in Release, read median 0.73
   deg, p90 1.98 deg") with the authority pointer (`docs/EXTRACTION.md -> the PU.69 paragraph`) -
   review 1's prescribed fix verbatim. (Nit, not blocking: the comment still duplicates two accuracy
   scores CLAUDE.md would rather see linked-only, but review 1 itself prescribed this content and
   the link is present.)

**What the second-pass brief does not list:** review 1's verdict required fixes 1-6 before
re-dispatch ("Re-dispatch this review ... once 1-6 are in; 7 is the orchestrator's call"). Fixes
**5** (unpinned promises) and **6** (row-text clauses) were not claimed closed, and I confirm they
are not closed - no new test beyond `transformAndWeight` (which predates review 1; it is the diff's
only test addition, `PumpRowDeskewTests.swift:101-116`), no new mutation log (the `pu69-mutation-*`
pair is unchanged since 03:03), and the row text carries none of the three clauses. They remain
PARTIAL below. Review 1's fix 7 stays the orchestrator's call; I concur with review 1's judgment
that the power-of-two padding needs no owner OK (it is the published base algorithm's own input
domain, note §2.2's `n = 2^q`, and it is disclosed in the row text).

## 1. Fidelity to the published method - MET

Review 1 ruled this MET on the same code (only comments changed since); I re-derived the load-
bearing parts independently and concur:

- **Algorithm 1 (arXiv:1912.02504 §3) step by step**: derivative = the across-row first difference
  `d = gray[x, y+1] - gray[x, y]` (`PumpRowDeskew.swift:171-179`) - A4's named adaptation, the
  difference operator that "ships first". Transform = the Brady-Yong recursion (`PumpFastHough.swift:33-47`):
  dyadic column bisection, merge = vector add of one shifted row-pair per slope - I hand-verified
  the merge's index arithmetic on n = 2 and n = 4 (t = 0..3): every accumulator row is a staircase
  rising exactly `t` rows over `n` columns, 8-connected, offsets spanning the padded range; the
  note §2.2's Theorem-1 shape. Criterion = `criteria` (`PumpRowDeskew.swift:205-222`):
  `(1 + s^2)^1.5 * Σ(Δoffsets)^2` with `s = t/(n-1)` (`:218-219`) - exactly the paper's
  `Kh[i]^3 = (sqrt(1 + i^2/(H-1)^2))^3` times SSG (Alg. 1 lines 5-6; Kunina eq. 4 with §2.4's
  resolution of the 3/2-vs-3 ambiguity in favour of the skew paper's unambiguous form). Vertical
  band dropped (A3); `Recalculate` correctly absent (A5, one band survives); argmax (`:189`) with
  the `> 0` guard, quadratic refinement (`:190-195`), `atan` of the refined slope (`:196`) -
  Alg. 1 lines 15-16 plus A2.
- **Gate and confidence** (not in the paper, §2.7-1,4 - both A6 named choices): `minimumGain` 0.05
  unchanged (`:43`), re-based verbatim as `curve[peak] >= level * (1 + minimumGain)` (`:201`);
  `Confidence` (`:60-70`, set at `:197-200`) is exactly A6's three published-shape statistics -
  Leptonica peak-over-minimum, Kunina-eq.-6 dominance computed as peak-vs-range-median and labelled
  as such in its doc comment, raw peak mass.
- **Departures**: A1 (ruled below), A2 (matches - three-point parabolic vertex
  `position += 0.5*(a-c)/(a-2b+c)` with the concavity guard, in slope-index space, before `atan`;
  interior-peak-only is a safe degeneracy fallback to the paper's bare argmax), A3 (`:19-21` doc,
  mirror instead of a vertical band), A4, A5 (see sign ruling), A6, A7 (ruled below), A8 (ruled
  below), A9 (`levelAngle`/`levelled`/`unlevelled` untouched by the diff - `:325-377` is context),
  A10 (the measurements, items 3-4). No unlisted departure found. The two beyond-the-A-list
  implementation choices review 1 identified stand as ruled: power-of-two width padding
  (`PumpFastHough.swift:17-18` - the published base's own `n = 2^q` domain, FHT2DS/2DT exist to
  avoid its cost and 2.9 ms/row shows nothing needed avoiding; disclosed in the row text) and the
  one-sided offset range (every slope in the selection bound crosses the crop at offset 0;
  empirically sound at ±20 deg and the >6 deg bucket).

### Row-specific rulings the brief asked for

- **Sign convention (positive = clockwise, y down): MET, mutation-pinned.** Documented at
  `PumpRowDeskew.swift:53` and `:185-186`; the transform's "slope t rises t rows (y grows with x)"
  (`PumpFastHough.swift:14-15`) is falling-right on screen = clockwise; the stitched curve reads
  `down` for s ≥ 0 and the vertically mirrored transform for s < 0 (`:187`) - I verified the mirror
  is sign-safe because SSG is invariant under the difference image's global negation; `atan` of the
  signed position (`:196`) feeds `rotatedRect`, whose matrix turns clockwise for positive degrees
  (`:152-159`). Pins: `findsTheTurn`'s ± cases (`PumpRowDeskewTests.swift:55-59`) and the
  mirror-drop mutation red with 5 issues - the log shows every positive angle flipping (+20.0 found
  −19.917, +6.0 found −6.033, +3.0 found −2.965; `pu69-mutation-mirror.log`). The log's suite has 5
  tests (it predates `transformAndWeight`); the mutated mechanism is pinned by `findsTheTurn`,
  which is unchanged, so the evidence addresses the current tree.
- **A8 black zone - YES, padding to `height + n` rows satisfies it, by a stronger mechanism than
  the letter.** The paper pads so cyclic shifts wrap into zeros (§2.3); here the merge never wraps
  at all - the out-of-range right-half contribution is dropped (`PumpFastHough.swift:43-44`), which
  is equivalent to wrapping into an infinitely zero-padded region, so wrap contamination is
  structurally impossible. Sufficiency: for every offset anchored in real rows (y ≤ height−1) the
  pattern's span y+t ≤ height−1+n−1 < rows, so no real-anchored pattern is ever clipped; rows
  y ≥ height are entirely padding and contribute zeros. A8's second clause (zero-coverage rows
  excluded from the argmax) has no referent in this geometry: every slope inside the ±30 deg
  selection bound (`PumpRowDeskew.swift:183`) crosses real pixels at offset 0, and the
  `curve[peak] > 0` guard (`:189`) excludes the all-zero case; the residual risk A8 named (sec^3
  growing with |t| favouring coverage-starved slopes) is bounded by the selection bound (weight
  ≤ 1.54x at 30 deg) and measured harmless - the >6 deg bucket improved (1.00 → 0.66). The
  uncovered item is the TEST for the "never wrap" doc promise - item 5, fix 4c.
- **A2 interpolation: matches the note** (above); its test coverage is the open item 5(a).
- **A7 - keeping `rowSize`/`largeTurn` for OUTPUT sizing only is NOT a departure.** Review 1's
  reading stands and I adopt it: A7 retires the per-trial SEARCH reshaping (structural to per-angle
  warping, which is gone - the diff deletes the whole `score` closure), while the §3 mapping table
  says "Output geometry - unchanged" and A7 itself says the >6 deg intent "is already carried by
  `rotatedRect` + the unchanged output path". The build resolves that internal contradiction on the
  conservative side: the output block (`PumpRowDeskew.swift:88-93`) is byte-identical to HEAD (diff
  context, only the `confidence:` argument added), `largeTurnRecoversTheRowSize`
  (`PumpRowDeskewTests.swift:61-69`) is kept green pinning exactly the intent A7 transfers, the
  row text discloses it ("kept for the OUTPUT box's size only"), and A7's guard transfer is beaten:
  the >6 deg bucket measures median **0.66** (n = 5; review 1's independent DEBUG re-run and the
  captured Release log agree) against the note's 1.43 proxy and the like-for-like sweep's 1.00.
- **The 48 → 96 px input change: the A1-fallback claim is SUSTAINED** (review 1's ruling, adopted;
  nothing changed since). The remedy is the fallback's own named parameter move ("raise the FHT
  input height toward the native crop", note A1); 96 sits below the native crop median height
  (133, note §3) and independently equals the read path's own strip height (`PumpReader.swift:13`,
  verified `stripHeight: CGFloat = 96`), so the search never samples below the scale the read uses.
  The stated trigger ("48 px gave a 0.6-0.7 deg bias on the synthetic turns") is an instance of the
  scale-limited error regime the fallback exists for (halving the height halves n and doubles the
  grid step, note §5.5), it is disclosed in the row text AND in EXTRACTION (`:1120-1121`), and F1's
  outcome confirms improvement, not degradation (0.60 vs the like-for-like 0.73). Pre-authorised:
  "a parameter move inside the published method, not a new departure."
- **The deferral of "app path live >= PU.67's count": the row text makes it plain.** "The app path
  is unchanged (row deskew is off until PU.67); the deskew arm's live count is PU.67's re-measure" -
  fact, reason and future owner. Code facts re-verified: the app's reader is built at the default
  `.off` (`ios/App/Sources/Capture/CapturePipeline.swift:28` → `makeReader`,
  `PumpDisplayCapture.swift:106-110` → `PumpReader.swift:31-38`, `deskew: DeskewMode = .off`), and
  every caller of the changed code is mode-gated (`:346-349`; `readPhotoDetailed`'s arms,
  `PumpRowDeskew.swift:296-320`; `candidates(for:deskewRows:)`, `PumpReader.swift:54-63`). And the
  deferral now has the measurement review 1 conditioned it on: livePath ran on the composite tree
  at 47/47 (closure 1).

## 2. Wired into the app path, not only the harness - MET

Unchanged since review 1's MET ruling, re-verified: the new method sits inside
`PumpRowDeskew.deskew` → `angle(of:)` → `PumpFastHough.transform`, which classify's own refusal
retry calls (`PumpDisplayCapture.swift:346-349` → `PumpReader.candidates(for:deskewRows: true)`
`:54-63` → `PumpReader.deskewed` `PumpRowDeskew.swift:275-279`), as do `readPhotoDetailed`'s
`.onRefusal`/`.level` arms (`:296-320`) and `levelAngle` (`:332-337`). No `#if DEBUG` anywhere in
`ios/Sources/TankbookCore/Extraction/PumpReader/` (grep: no match), so the code compiles into both
configurations; the Release compile is exercised by the `-c release` corpus runs ("Building for
production") and the Debug compile by the app-target bundle (`pu69-app.log:3876`: "Executed **301
tests**, with **0 failures**", `** TEST SUCCEEDED **`). Dormant on the phone solely because PU.67's
documented hold keeps the mode `.off` - PU.67's decision to reverse, and the row text says so.

## 3. Measured on the app path, on the named population - PARTIAL

The measurements themselves are all present, captured and independently consistent:

- Live-path floor ran on the final composite tree: committed **47**, correct **47**, precision
  1.000 (`pu69-swifttest.log:5274`) - matching `PumpPhotoGate.readerCommitted`/`readerCommittedCorrect`
  47/47 (`PumpPhotoGate.swift:86,91`); **zero new wrong readings** on either arm.
- F1 ran on the population the note's drift rule produces at the build commit: **188** (my
  re-count reproduces it exactly, including WHY: pump-275's `reviewed` cleared, 2 windows), with
  the like-for-like sweep baseline through the same test (0.73/1.98/1.00/8.4). Every reported
  statistic improved or held - F1's "materially worse" falsifier is not remotely tripped, and the
  >6 deg bucket (A7's guard transfer) improved 1.00 → 0.66.

What keeps this PARTIAL is reporting, all of it review 1's fix 6, still open:

- **The row text never explains 190 → 188.** The Checks cell promises "the 190 heldout hand quads";
  the Built text reports "188 heldout hand windows" with no drift clause. One sentence: the note
  §5.2 re-count at the build commit, pump-275's re-annotation cleared `reviewed` and dropped its
  2 windows.
- **No CE@1 deg, and no interval anywhere.** F1's own baseline is "median 0.68 deg, CE@1 deg 0.690
  [0.617, 0.754]" (note §5.3/§5.6); the build reports median/p90/one bucket and omits the second
  baseline statistic entirely - the F1 test does not even compute it (`PumpRowDeskewCorpusTests.swift:43-50`).
  PU.68 has landed, and its convention is an interval beside every proportion; CE@1 deg is the one
  proportion F1 names. (The medians are not proportions - no interval applies to them.)
- **The per-row latency figure contradicts its own artefact** (closure 3's exception): row and
  EXTRACTION say 2.7 ms, the captured Release log says 2.9 ms, and no artefact says 2.7.

## 4. No regression elsewhere - MET

- **Receipt leak**: cannot move, and the row text now carries the code-fact argument review 1
  accepted in lieu of a `PUMP_LEAK=1` run ("The leak cannot move: the display decision (`decideAt`)
  never calls deskew, which runs only in the retry after a frame is already routed as a pump") -
  verified: `decideAt` (`PumpDisplayCapture.swift:192`) has no deskew reference; the only call
  sites are `:346-349`, post-routing and mode-gated.
- **Annotated floor**: 116 committed, **116 correct, precision 1.000** - the 118-floor red is the
  pump-275 population (2 cells, verified at the source), not a lost reading; on the committed
  corpus PU.78 measured 118/118 with these same law and reader.
- **Oracle ratchet**: 774 committed at 0.9987 (`pu69-swifttest.log:3423`) - not fallen; the one
  wrong cell is the ratchet's known pump-031. **Fragility 0.0412** ≤ 0.10 (`:3544`).
- **Latency**: the row touches no path the phone runs (`.off`); the deskew step has Release numbers
  with artefacts on both sides (8.4 → 2.9 per the logs; reconcile the printed 2.7 - fix 1). The
  refusal-path total is explicitly PU.67's gate now, per the note's own F4 framing (the second
  verify+read dominates; the step is "the real target").
- The full-suite run has **exactly 2 issues** in 2285 tests, both accounted for above; the parity
  suite that runs the new code end-to-end at `.onRefusal` is green (`:5259`).

## 5. Tests that would fail - PARTIAL

Pinned, with red mutation evidence in the gate logs (both read in full):

- **Sign/mirror mechanism**: `findsTheTurn` ± cases + mirror-drop mutation red, 5 issues, sign
  flips visible in the log (`pu69-mutation-mirror.log`).
- **sec^3 weight**: `transformAndWeight` (`PumpRowDeskewTests.swift:110-115`) + weight-drop
  mutation red - the ratio fails at 1.828 = |1 − 2^1.5| exactly (`pu69-mutation-sec3.log`).
- **Accumulator layout (slope-major)**: `sums[3 * hough.rows + 0] == 4` on the hand-computed 4x4
  diagonal (`:107-109`) - a transpose of the axes changes that index arithmetic and goes red;
  F2's named transpose mutation is caught by construction even though it was not separately run.
  F2's substantive pin is `findsTheTurn`'s signed set (a wrong convention inverts every positive
  angle - demonstrated by the mirror log).
- **Italic guard (F3, first clause)**: `italicIsNotATurn` green after the change (`:95-99`; suite
  green in the full-suite log `:4897`).
- **Confidence populated, in measurement form**: the F6 test reads `found.confidence` and fails on
  empty good/bad lists (`PumpRowDeskewCorpusTests.swift:78,90`), run and captured - but gated
  behind `PUMP_DESKEW=1`, so the default suite cannot fail on it.

Still unpinned - review 1's fix 5, not closed, each a promise that stays green when its behaviour
is removed (CLAUDE.md: "If a comment makes a behavioral promise, add or identify the test that
would fail when the promise is broken"):

- **(a) The quadratic sub-slope refinement** - promised in the row text, EXTRACTION `:1115-1116`
  and the doc comment (`PumpRowDeskew.swift:165-166`). Removing `position += 0.5 * (a - c) / denominator`
  (`:194`) leaves the whole default suite green: the worst-case quantisation error without it is
  half a grid step - ≤ 0.11 deg at n = 256 (the synthetics' padded width, ~213 px at 3 deg) and
  ≤ 0.23 deg at n = 128 (the 20-deg case's ~109 px strip) - against `findsTheTurn`'s 0.6 deg
  tolerance, and the corpus tests assert no thresholds. No mutation of it was run.
- **(b) F3's named fusion mutation was still not run.** The note's F3 has two arms - the test red
  after the change (green: satisfied), OR its mutation (enabling the mostly-vertical fusion,
  undoing A3) failing to turn it red (unevaluated). The guard's teeth against the NEW method are
  undemonstrated; PU.65's original column-profile mutation pinned the OLD one.
- **(c) The "never wrap" promise** (`PumpFastHough.swift:12-13`, echoed in the row text's
  "height + width rows"): a cyclic-wrap mutation of the merge tail (`:43-44`) has no test to fail -
  `transformAndWeight`'s 4x4 diagonal is wrap-blind (I checked the cells: both the wrapped and the
  dropped contribution are zero there), and the contamination lands at high offsets the synthetics
  do not discriminate.
- **(d) Confidence has no default-suite pin** (the gated F6 is measurement, not a gate): nothing
  asserts a turned synthetic row carries non-nil confidence, or the guaranteed shape - for a turned
  result `peakRatio ≥ 1 + minimumGain` holds by construction (`min(curve) ≤ level`, so
  peak/min ≥ peak/level ≥ 1 + gain, `:198,201`) and would fail loudly if the gate or the statistic
  were miswired.
- (Noted, not required - review 1 inventoried it but did not put it in the fix list: the
  `minimumGain` re-base (`:201`) has no mutation either.)

## 6. Docs reconciled - PARTIAL

- **`docs/EXTRACTION.md:1111-1122`**: the paragraph is accurate on mechanism (mirror, dropped
  vertical band, sec^3, interpolation, 96 px with its reason, three statistics, "Nothing on the app
  path changes until row deskew is enabled (PU.67)") and its agreement numbers match the artefacts
  digit-for-digit - except **`8.4 -> 2.7 ms per row` (`:1119`)**, which the captured log contradicts
  (2.9), and **"for PU.70" (`:1121`)**, now stale: PU.70 is `[cut]` one row below in TASKS.md
  (`docs/TASKS.md:1073`), its cut text re-homing the confidence to PU.76. EXTRACTION has not been
  touched since 03:04 - before both the captured log and (apparently) the cut. No numbered decision
  owns the deskew method (review 1 checked decisions 1-11; nothing changed since), so the prose
  paragraph is the right home. The old PU.65/67 paragraph below it reads as a dated historical
  record beside the new one, which explicitly says "It replaces a 72-trial warp sweep" - acceptable
  as review 1 ruled; the optional "(method superseded above)" pointer remains optional.
- **`docs/TASKS.md:1072`**: ticked, index row agrees (`:171`, both index scripts exit 0), scenario
  named (J4), Built text carries the mechanism, the departures, the numbers, the tests, the
  mutations, the deferral, the F6 closure, the re-homed latency and the leak argument. Outstanding:
  the 2.7/2.9 mismatch, the missing 190→188 drift clause, the missing CE@1 deg + interval, the
  stale **"PU.70 fits its threshold on it"** (same sentence should point where the cut row points -
  PU.76, or "its future consumer"), and no line saying where the note §3's `PumpReader.deskewed`
  degrees+confidence bridge variant lands (still quad-only at `PumpRowDeskew.swift:275-279`; its
  planned consumer PU.70 is cut - review 1's fix 6(iii), now easier: one clause naming PU.76 or
  deferring until a consumer ships).
- **`docs/ERRORS.md` / `docs/JOURNEYS.md`**: correctly untouched - nothing user-visible changes
  while the app runs `.off` (git status confirms neither file is modified).
- **CLAUDE.md comment rules**: both review-1 violations fixed (closure 4); the new/changed comments
  are present-tense current truth, no task-id narrative beyond the tree's standing row-pointer
  precedent, citations name sources not history. The one open comment-rule item is behavioural: the
  unpinned "never wrap" promise (item 5c) - fix by test or soften the claim.

## 7. Everything the row promised - Checks cell sentence by sentence

1. **"Angle from the published FHT method (a C/Accelerate kernel if the note says the Swift loop
   cannot meet it)" - MET.** The note's verdict is no C needed (§3); pure Swift, no new target; the
   Release step cost (2.9 ms/row captured) sits two orders below the note's ceiling. Fidelity per
   item 1.
2. **"The sweep is retired or kept only as the note justifies" - MET.** `coarseStep`, `fineStep`,
   `profileSharpness` gone with zero code references (grep: they survive only in docs/agents prose,
   as history); the row text says "retired".
3. **"Angle agreement with the sweep on the 190 heldout hand quads ... reported as a distribution"
   - PARTIAL.** Run on 188 - the drift-rule re-count, exact per my independent count - against the
   captured like-for-like baseline; every statistic improved; F1 not falsified. Missing: the drift
   clause, CE@1 deg with its interval (F1's second baseline statistic), and the printed latency
   figure contradicting its artefact. All three are reporting fixes, none re-opens the measurement.
4. **"App path live >= PU.67's count at zero new wrong readings" - MET.** Review 1 ruled this a
   legitimate explicit deferral CONDITIONED on the composite-tree run confirming 47/47 in
   measurement: the condition is now discharged (`pu69-swifttest.log:5274`, 47/47, precision 1.000,
   zero wrong on either arm). The row text states the deferral plainly (ruled in item 1).
5. **"A Release latency number for the refusal path, before and after" - MET as re-homed, with the
   number to reconcile.** The re-home sentence is in the row, PU.67's Checks carry the refusal-photo
   number, the step-level before/after has captured Release artefacts on both sides - but the
   printed "after" (2.7) is not what the artefact says (2.9). One-edit fix.
6. **"The confidence is exposed for PU.70" - PARTIAL.** Exposed (`Result.confidence`,
   `PumpRowDeskew.swift:50-70`, populated on every searched crop including refusals `:87`), exactly
   A6's three statistics, and now MEASURED (F6: AUROC 0.653/0.689/0.700, captured, honestly
   reported, falsifier not tripped). Outstanding: the named consumer is `[cut]` in the same tree
   while row text and EXTRACTION still point at it; the bridge-variant line is missing; no
   default-suite pin (item 5d).

## Verdict: INCOMPLETE

The four claimed closures are real and verified against their artefacts - the full suite, F6, the
re-homing with the baseline log, and both comments - and the implementation's fidelity, wiring and
no-regression evidence are stronger than at review 1. What remains is review 1's fixes 5 and 6
(neither claimed closed, neither closed) plus one new contradiction the newly-captured log exposes.
Every fix is small; none needs a new row; none re-opens a measurement.

1. **Reconcile the per-row latency with its artefact.** `docs/TASKS.md:1072` and
   `docs/EXTRACTION.md:1119` say 2.7 ms/row; `pu69-corpus-release.log:377` says 2.9 and no artefact
   says 2.7. Either print 2.9 (8.4 → 2.9, ~2.9x) in both places, or keep a log of the run that
   produced 2.7 - and if the spread is machine load (the annotator was live), say so per the note
   §5.4 hygiene rule.
2. **Row-text clauses (review 1 fix 6, verbatim still applies).** (i) One sentence: 188 = the
   build-commit re-count under the note §5.2 drift rule - pump-275's re-annotation cleared
   `reviewed`, dropping its 2 windows from the promised 190 (my count: 65 stills / 188 windows /
   pump-275 = 2). (ii) CE@1 deg against the sweep's, with the Wilson interval (PU.68's convention) -
   the F1 test already holds every per-box error; print the count, re-run Release (~1 min), report
   beside F1's 0.690 [0.617, 0.754] baseline. (iii) One clause on where the note §3's `deskewed`
   degrees+confidence bridge variant lands - PU.76 or "when a consumer ships".
3. **Fix the stale PU.70 references.** Row text "PU.70 fits its threshold on it" and EXTRACTION
   "three confidence statistics of the criterion curve for PU.70" contradict PU.70's `[cut]` row
   (`docs/TASKS.md:1073`), which re-homes the confidence to PU.76. Point both where the cut points.
4. **Make the unpinned promises fail-able (review 1 fix 5).** (a) Pin the quadratic refinement: a
   mid-grid synthetic case (e.g. a turn at half a grid step, tolerance under half a step - at
   n = 256 the step is 0.225 deg) or a recorded mutation deleting
   `position += 0.5 * (a - c) / denominator` (`PumpRowDeskew.swift:194`) with a red `findsTheTurn`.
   (b) Run F3's named fusion mutation (add the mostly-vertical band into the curve, ~10 throwaway
   lines): `italicIsNotATurn` must go red; revert, keep the log. (c) Pin "never wrap" with a direct
   `PumpFastHough` case that distinguishes drop from wrap - e.g. width 2, height 1, pixels (a, b):
   `sums[1 * rows + rows - 1]` must be 0, and a cyclic-wrap mutation makes it b. (d) Two assertions
   in the synthetics: a turned row carries non-nil confidence with
   `peakRatio >= 1 + PumpRowDeskew.minimumGain` (guaranteed by construction), and the level/refusal
   case carries non-nil confidence too.
5. **Re-dispatch this review (fresh copy, same row) once 1-4 are in.** Items 1, 2 and 4 of the
   checklist are MET and need no re-work; the verdict turns entirely on the fixes above.

Carried forward, owned elsewhere (found, not fixed - this review may not write them):
- The orchestrator's correction note on the PU.65/PU.67 row texts' normalised-space angle
  statistics (note §7-1: "max 18" is a normalised-space artefact; pixel-space max is 10.35) - still
  unappended; PU.65's row still reads "max 18" (`docs/TASKS.md:1064`).
- PU.67's OPEN row (`docs/TASKS.md:1066`) still names the retired method ("The method is a
  projection-profile skew estimate (row-brightness profile sharpness)") - its re-measure will run
  the FHT; update the row text when it reopens. Its re-measure also now stacks with PU.81's ("PU.67 re-measured on it") -
  one run can discharge both.
- Review 1's fix 7 (formal owner OK for the power-of-two padding in place of FHT2DS/2DT) remains
  the orchestrator's call; I concur with review 1 that it needs neither - published base domain,
  disclosed in the row text.
- Commit hygiene: the two red floors in the composite run are the owner's in-flight pump-275
  re-annotation (working-tree `windows.json`, must-not-touch). Do not commit that file with this
  row; on the committed corpus the floors are green by PU.78's own evidence.
- Observation, non-blocking: the new code adds single-letter `identifier_name` warnings (same
  species as the HEAD file's own); lint reports zero errors on both changed source files.
