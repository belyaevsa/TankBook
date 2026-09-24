# PU.69 completeness review, third pass - row angle by a fast Hough transform, with a confidence

Run of `agents/briefs/REVIEW-COMPLETE-PU.69-3.md` (template `REVIEW-PU-COMPLETENESS.md`), 2026-09-24.
Read-only except this file. Tree state reviewed: the uncommitted PU.69 diff (`PumpFastHough.swift`
new, `PumpRowDeskew.swift`, `PumpRowDeskewTests.swift`, `PumpRowDeskewCorpusTests.swift` new,
`docs/EXTRACTION.md:1111-1124`, `docs/TASKS.md:1072`) on top of HEAD `bd840ce4`, with the
concurrent uncommitted PU.78/PU.72/PU.81 edits and the owner's in-flight corpus annotation present
and ignored except where they set the constants PU.69 is read against (`PumpPhotoGate` 47/47/183 at
`ios/Sources/TankbookCore/Config/PumpPhotoGate.swift:86,91,95`; `committedFloor` 118; the pump-275
`windows.json` state).

**Evidence I generated myself** (disclosed per the brief; the machine may be loaded - the only
timing-sensitive claim I did NOT re-measure is the Release latency, for that reason and per note
§5.4's ANE-contention rule):

- `cd ios && swift test --filter PumpRowDeskewTests` (DEBUG, final tree): **10/10, exit 0** - all
  ten tests named in the log, including the four new pins. This was the one claimed number with no
  captured green artefact (the last full suite predates the four new tests; every captured deskew
  log since is either red-by-design or corpus-only), so I ran it. It builds, hence writes `.build`;
  no source was modified. Timing-insensitive.
- `swiftlint lint` over the four changed files: **exit 0**; warnings only (`line_length` ≤ 133 in
  `PumpRowDeskew.swift:100,111,142,315` and `PumpRowDeskewCorpusTests.swift:48`; single-letter
  `identifier_name` in the tests) - same species as the file's own precedent, non-blocking.
- `python3 scripts/tasks-index.py --check` exit **0** (index row `docs/TASKS.md:171` reads `[x]`);
  `python3 scripts/scenario-index.py --check` exit **0** ("PASS: 528 rows"), the row names J4.
- Python re-count of the population from the working tree's `windows.json`/`split.csv` with the
  harness's own filters (`PumpReaderTestSupport.swift:83,88`): **65 heldout reviewed rot-0 stills,
  188 transaction windows, 255 reviewed train stills**; `pump-275` `reviewed` absent, **2**
  transaction windows - reproduces F1's `n 188` and F6's population exactly, and the row's
  190 → 188 drift clause exactly.
- Read every `/tmp/agentlogs/pu69-*` log at the lines quoted below; hand-verified the merge's
  drop-vs-wrap on the 2×1 case (drop → 0; cyclic wrap → 2, the mutation log's value), the sec^3
  mutation's 1.828 = |1 − 2^1.5|, the parabolic-vertex formula and its concavity guard, the
  coverage arithmetic of `rows = height + n` (any real-anchored pattern spans y + t ≤ height − 1 +
  n − 1 < rows, so nothing real is ever clipped), `rotatedRect`'s clockwise-positive matrix under
  y-down, and the mirror's sign safety (SSG is invariant under global negation of the difference
  image, so the stitched curve at `PumpRowDeskew.swift:187` is sign-consistent).
- I did NOT run `PumpReadTool`, the Release corpus suite or the full package suite: every needed
  number was in the captured logs, and a Release re-run risks both ANE contention (note §5.4) and
  `.build` lock contention with the concurrent PU.73/PU.78 work.

## Third pass: the four claimed closures, verified

1. **Latency reporting - CLOSED EXCEPT THE PRINTED FLOOR.** The row (`docs/TASKS.md:1072`) and
   `docs/EXTRACTION.md:1119-1120` now say "**8.4 -> 2.7-3.1 ms per row** across four Release runs,
   the higher ones with training running", citing `/tmp/agentlogs/pu69-corpus-*.log`. The captured
   FHT Release values under that glob are **2.9** (`pu69-corpus-release.log:377`), **3.1**
   (`pu69-corpus-with-interp.log:386`), **2.8** (`pu69-corpus-no-interp.log:33`, the no-refinement
   variant) against the sweep's **8.4** (`pu69-corpus-release-oldsweep.log:374`). The spread is now
   honestly disclosed with its load explanation (PU.73's training window is corroborated by
   `pu73-round-a.log`, 04:56) - but **"2.7" appears in NO captured artefact** (re-grepped every log:
   the only `ms/row` lines are 8.4, 2.9, 3.1, 2.8), and the cited glob does not contain the run
   that produced it. This is review 2's fix 1 residue: the point of keeping logs was that printed
   numbers be traceable, and the range's floor is not. Fix 2 below; no conclusion changes either
   way (the speedup is 2.7-3.0× on captured numbers alone).
2. **Row-text clauses - CLOSED.** All three of review 2's fix 2 are in the row, verified verbatim:
   (i) the drift clause - "188 heldout hand windows - the build-commit re-count under the note's
   §5.2 drift rule: pump-275's re-annotation cleared its `reviewed` flag, dropping its 2 windows
   from the note's 190" - matches my independent re-count digit for digit; (ii) "within 1 deg
   0.697 [0.628, 0.758] (Wilson 95 %; the note's sweep baseline 0.690 [0.617, 0.754])" - 131/188
   per `pu69-corpus-with-interp.log:385`, interval from the test's own `PumpPrecisionBounds.wilson`
   (`PumpRowDeskewCorpusTests.swift:45-47`, PU.68's mechanism), baseline correctly attributed to
   the NOTE's §5.3 sweep proxy (the like-for-like oldsweep run predates the CE line and printed
   none - the attribution is accurate, not conflated); (iii) the bridge re-home - "PU.70 was cut,
   so the confidence - and note §3's `deskewed` degrees+confidence bridge - land with the oriented
   detector, PU.76" - the bridge is indeed still quad-only (`PumpRowDeskew.swift:275-279`), and the
   clause now says where the variant lands.
3. **PU.70 references - CLOSED in the row and EXTRACTION; ONE MISSED IN A TEST COMMENT.**
   `docs/EXTRACTION.md:1122-1123` reads "kept for the oriented detector (PU.76; PU.70, their first
   consumer, was cut)" ✓; the row's operative sentence re-homes to PU.76 ✓ (its Built narrative
   keeps "peak mass for PU.70" as build-time intent, explicitly superseded three sentences later in
   the same cell - acceptable for a row, which is a historical record). But
   **`PumpRowDeskewCorpusTests.swift:60` still reads "on the TRAIN split so PU.70 can fit a
   threshold there"** - a code comment in a file NEW in this diff naming a `[cut]` row
   (`docs/TASKS.md:1073`) as the test's purpose. Code comments are current truth only (CLAUDE.md);
   the sibling comment at `PumpRowDeskew.swift:61` was written row-free ("exposed for a threshold
   fitted on the train split") - the test comment missed the re-pointing pass. Fix 1 below.
4. **Pins and mutations - CLOSED.** `PumpRowDeskewTests` is **10/10 on the final tree (my own run,
   exit 0)** with the four new pins present:
   - `transformDoesNotWrap` (`PumpRowDeskewTests.swift:119-125`): the 2×1 case I hand-computed -
     the drop gives 0, a cyclic wrap gives exactly the right pixel's 2; the mutation log
     (`pu69-mutation-wrap.log:30-34`) is red **at 2.0**, i.e. the mutation demonstrably re-wrapped
     and the test caught it. Review 2's 5c closed, and `PumpFastHough.swift:12-13`'s "never wrap"
     promise now has its failing test (CLAUDE.md comment rule satisfied).
   - `confidenceIsAlwaysReported` (`:127-134`): both of review 2's 4(d) assertions - a turned row
     carries non-nil confidence with `peakRatio >= 1 + minimumGain` (guaranteed by construction,
     `PumpRowDeskew.swift:198,201`, and now pinned), and the level/refusal result carries non-nil
     confidence too (`:87`). Review 2's 5d closed.
   - `subSlopeRefinement` (`:137-155`): a half-step synthetic (truth 2.358° midway between slopes
     10 and 11 at n = 256), shipped at the one-slope-step tolerance with the reason documented in
     the comment (`:139-145`: the dyadic patterns' own approximation bias, note §2.2's Theorem-2
     bound, keeps the estimate from the exact half-step; the refinement's gain is measured on the
     corpus instead). The refinement's mutation WAS run and IS captured red
     (`pu69-mutation-interp.log:42-46`: deleting the `position +=` line, found 2.2457 = the bare
     argmax slope-10 grid point vs truth 2.3579, red at the then-shipped quarter-step tolerance
     0.056), and the load-bearing pair is captured in Release on both sides
     (`pu69-corpus-no-interp.log:33`: median 0.63, p90 2.01; `pu69-corpus-with-interp.log:386`:
     median 0.60, p90 1.97; CE@1° identical at 131/188). Ruling in item 5.
   - `slantedStrokesAreNotATurn` (`:158-175`): slanted strokes with NO horizontal structure; the
     fusion mutation (the paper's vertical band added back, undoing A3) turns it red **"turned to
     10.296"** (`pu69-mutation-fusion.log:33-34`) - the slant read as exactly its 10° lean. F3's
     mutation arm is demonstrated against the NEW method; review 2's 5b closed. (Note: under the
     same mutation `italicIsNotATurn` stays green - its synthetic has full seven-segment horizontals
     that dominate the fused curve - which is why the purpose-built strokes-only case is the real
     teeth. The row's quote "turned to 10.3 deg" is an honest rounding of the log.)
   Carried items: **PU.65's correction appended** (`docs/TASKS.md:1064`, end of row: "max 18" is a
   normalised-space artefact, pixel-space max 10.35 - appended, not edited, per note §7-1's rule) ✓;
   **PU.67's row carries the FHT note** (`docs/TASKS.md:1066`: "the row angle is now PU.69's fast
   Hough transform ... the re-measure (with PU.81's guard) runs the new estimator, and carries this
   row's Release refusal-path latency number") ✓ - which also parks the re-homed latency and the
   PU.81 stack in the right place.

## 1. Fidelity to the published method - MET

Reviews 1 and 2 ruled this MET on behaviourally identical source (the only changes since are the
mutation round-trips, reverted exactly - see the fingerprint argument in item 4); I re-derived the
load-bearing parts against the final file rather than adopting the rulings blind, and concur:

- **Algorithm 1 (arXiv:1912.02504 §3, via note §2.1) step by step.** Step 1: the across-row first
  difference `d = gray[x, y+1] - gray[x, y]` (`PumpRowDeskew.swift:173-179`) is A4's named
  adaptation (the paper's operator is undefined in the fetched text, note §2.7-6; the difference
  operator "ships first" per A4's decision clause - no train-split preference for raw luminance was
  claimed, so no switch was owed). The transform (`PumpFastHough.swift:16-27,33-47`) is the
  Brady-Yong recursion: dyadic column bisection, merge = vector add of one shifted row-pair per
  accumulator row (`:40-45`), the note §2.2 Theorem-1 shape; `rows = height + n` (`:19`) and the
  non-cyclic merge tail (`:43-44`) are the padding of note §2.3/A8. Step 2: `criteria`
  (`PumpRowDeskew.swift:205-222`) computes `(1 + s²)^1.5 · Σ(Δoffsets)²` with `s = t/(n−1)`
  (`:218-219`) - exactly the paper's `Kh[i]³ · SSG` (Alg. 1 lines 5-6; the note §2.4 resolution of
  Kunina's 3/2-vs-3 ambiguity in favour of the skew paper's unambiguous form is what is
  implemented, and the mutation pins it: 1.828 = |1 − 2^1.5|, `pu69-mutation-sec3.log:38`).
  Step 3: the vertical band is dropped - A3, named, justified (italic guard), mutation-demonstrated
  (above). Step 4 (`Recalculate`): correctly absent - one band survives (A5's note). Step 5: the
  stitched signed curve (`:187`), argmax with the `> 0` guard (`:189`), quadratic sub-row
  refinement (`:190-195`), `atan` of the refined slope (`:196`) - Alg. 1 lines 15-16 plus A2.
- **Gate and confidence** (not in the paper, note §2.7-1,4 - both A6 named choices): `minimumGain`
  0.05 unchanged (`:43`, not re-fitted), re-based verbatim as
  `curve[peak] >= level * (1 + minimumGain)` (`:201`); `Confidence` (`:62-70`, set at `:197-200`,
  populated on refusals too at `:87`) is exactly A6's three published-shape statistics - Leptonica
  peak-over-minimum, Kunina-eq.-6 dominance computed as peak-vs-range-median and labelled as such
  in its doc comment (`:65-66`), raw peak mass.
- **Departures**: A1 (ruled below), A2 (ruled below), A3, A4, A5, A6, A7 (ruled below), A8 (ruled
  below), A9 (`levelAngle`/`levelled`/`unlevelled`/`minimumLevelAngle` untouched by the diff -
  `:325-377` is context), A10 (the measurements, items 3-4). No unlisted departure found. The two
  beyond-the-A-list implementation choices remain as reviews 1-2 ruled: the power-of-two width
  padding (`PumpFastHough.swift:17-18`) is the published base's own `n = 2^q` domain (note §2.2;
  FHT2DS/2DT exist to avoid its cost, and ~3 ms/row shows nothing needed avoiding), disclosed in
  the row text; the one-sided offset range is sound because every slope inside the ±30° selection
  bound (`PumpRowDeskew.swift:183`) crosses the crop at offset ≥ 0 in one direction or, via the
  mirror, the other - and it is now empirically pinned (±20° synthetics within 0.6°, the >6°
  corpus bucket at 0.66).

### Row-specific rulings the brief asked for

- **Sign convention (positive = clockwise, y down): MET, mutation-pinned.** Documented at
  `PumpRowDeskew.swift:53` and `:185-186`; the transform's "slope t rises t rows (y grows with x)"
  (`PumpFastHough.swift:14-15`) is falling-right on screen = clockwise; the stitched curve reads
  `down` for s ≥ 0 and the mirrored transform for s < 0 (`:187`; mirror built at `:177`, sign-safe
  by the SSG negation-invariance I verified); `atan` of the signed position (`:196`) feeds
  `rotatedRect`, whose matrix turns clockwise for positive degrees under y-down (`:152-159`,
  verified). Pins: `findsTheTurn`'s ± cases (`PumpRowDeskewTests.swift:55-59`, green in my run) and
  the mirror-drop mutation red with 5 issues, every positive angle flipping
  (`pu69-mutation-mirror.log:27-47`). `subSlopeRefinement` adds a direct one-grid-step pin of the
  accumulator layout, which is F2's substance (a transpose or convention error blows past one
  step); `transformAndWeight`'s slope-major index arithmetic (`:107-109`) catches F2's named
  transpose mutation by construction.
- **A8 black zone - YES, padding to `height + width` rows satisfies it, by a stronger mechanism
  than the letter, and the mechanism is now test-pinned.** The paper pads so cyclic shifts wrap
  into zeros (note §2.3); here the merge never wraps at all - the out-of-range right-half
  contribution is dropped (`PumpFastHough.swift:43-44`), equivalent to wrapping into an infinitely
  zero-padded region, so wrap contamination is structurally impossible. I verified the coverage
  arithmetic myself: for every offset anchored in real rows (y ≤ height−1) the pattern's span
  y + t ≤ height−1 + n−1 < rows, so no real-anchored pattern is clipped; rows ≥ height are pure
  padding contributing zeros. A8's second clause (zero-coverage rows excluded from the argmax) has
  no referent in this one-sided-offset geometry: every slope inside the ±30° bound crosses real
  pixels at offset 0, and the `curve[peak] > 0` guard (`:189`) excludes the all-zero case; the
  residual risk A8 named (sec³ growing with |t|) is bounded by the selection bound (≤ 1.54× at 30°)
  and measured harmless - the >6° bucket improved (1.00 → 0.66). The doc promise "never wrap onto
  real pixels" (`PumpFastHough.swift:12-13`) now has the failing test CLAUDE.md requires
  (`transformDoesNotWrap` + red wrap mutation at the exact wrapped value 2.0).
- **A2 sub-slope interpolation: matches the note.** The standard three-point parabolic vertex
  `position += 0.5*(a−c)/(a−2b+c)` with the concavity guard `denominator < 0`
  (`PumpRowDeskew.swift:190-195`), through the SSG maximum and its two neighbours, in slope-index
  space, before the `atan` (`:196`) - A2's "Lagrange/quadratic fit ... before arctan", of the
  Leptonica `numaFitMax` family A2 cites. Interior-peak-only is a safe degeneracy fallback to the
  paper's bare argmax. Test coverage: item 5.
- **A7 - keeping `rowSize`/`largeTurn` for OUTPUT sizing only is NOT a departure.** Reviews 1-2's
  reading, adopted after my own diff check: A7 retires the per-trial SEARCH reshaping (structural
  to per-angle warping, which is gone - the diff deletes the whole `score` closure and its
  per-trial `rowSize` call), while the §3 mapping table says "Output geometry - unchanged" and A7
  itself says the >6° intent "is already carried by `rotatedRect` + the unchanged output path".
  Those are consistent only under the reading the build took. The output block
  (`PumpRowDeskew.swift:88-93`) keeps `rowSize`/`largeTurn` solely for the returned box's size, is
  otherwise diff-context-identical to HEAD (only the `confidence:` argument added),
  `largeTurnRecoversTheRowSize` (`PumpRowDeskewTests.swift:61-69`) is kept green pinning exactly
  the intent A7 transfers, the row text discloses it ("kept for the OUTPUT box's size only"), and
  A7's guard transfer is beaten: the >6° bucket measures median **0.66** (n = 5) against the note's
  1.43 proxy and the like-for-like sweep's 1.00 (`pu69-corpus-release.log:377`,
  `-oldsweep.log:374`).
- **The 48 → 96 px input change: the A1-fallback claim is SUSTAINED** (reviews 1-2's ruling,
  adopted; nothing changed since). The remedy is the fallback's own named parameter move ("raise
  the FHT input height toward the native crop", note A1): 96 sits below the native crop median
  height (133, note §3) and independently equals the read path's own strip height
  (`PumpReader.swift:13`, `stripHeight: CGFloat = 96` - verified), so the search never samples
  below the scale the read uses. The stated trigger ("48 px gave a 0.6-0.7 deg bias on the
  synthetic turns") differs in letter from F1's clustering condition but is an instance of the same
  scale-limited error regime (halving the height halves n and doubles the grid step, note §5.5);
  it is disclosed in the row AND EXTRACTION (`:1121-1122`); F1's outcome confirms improvement
  (0.60 vs the like-for-like 0.73); and the note pre-authorises it ("a parameter move inside the
  published method, not a new departure").
- **The deferral of "app path live >= PU.67's count": the row text makes it plain.** "The app path
  is unchanged (row deskew is off until PU.67); the deskew arm's live count is PU.67's re-measure"
  (`docs/TASKS.md:1072`) - fact, reason, future owner; and PU.67's own row now carries the dated
  note accepting the re-measure with the new estimator (`docs/TASKS.md:1066`). Code facts
  re-verified myself: the app's reader is built at the default `.off`
  (`ios/App/Sources/Capture/CapturePipeline.swift:28` → `makeReader`,
  `PumpDisplayCapture.swift:106-110` → `PumpReader.swift:33,35`, `deskew: DeskewMode = .off`), and
  every caller of the changed code is mode-gated (classify's retry behind
  `reader.reader.deskew == .onRefusal`, `PumpDisplayCapture.swift:346-349`; `readPhotoDetailed`'s
  arms, `PumpRowDeskew.swift:296-320`; `candidates(for:deskewRows:)`, `PumpReader.swift:50,54-56`).
  And the deferral has the measurement review 1 conditioned it on: livePath ran on the composite
  tree at 47/47 (item 3).

## 2. Wired into the app path, not only the harness - MET

Unchanged since reviews 1-2, re-verified against the final tree: the new method sits inside
`PumpRowDeskew.deskew` → `angle(of:)` → `PumpFastHough.transform`, which classify's own refusal
retry calls (`PumpDisplayCapture.swift:346-349` → `PumpReader.candidates(for:deskewRows: true)`
`:54-56` → `PumpReader.deskewed`, `PumpRowDeskew.swift:275-279`), as do `readPhotoDetailed`'s
`.onRefusal`/`.level` arms (`:296-320`) and `levelAngle` (`:332-337`). No `#if DEBUG` anywhere in
`ios/Sources/TankbookCore/Extraction/PumpReader/` (grep: no match), so the code compiles into both
configurations; the Release compile is exercised by all four `-c release` corpus runs ("Building
for production" at each log head) and the Debug app-target compile by the unit bundle
(`pu69-app.log:3876-3886`: "Executed **301 tests**, with **0 failures**", `** TEST SUCCEEDED **`;
the bundle predates the final comment-only source edits and the test-file additions, neither of
which the app target compiles into behaviour - the package's post-03:05 changes are comments and
mutation round-trips, and both the 04:00 full suite and the 04:55 Release run recompiled the
package since). Not a harness-only or DEBUG-only seam: dormant on the phone solely because PU.67's
documented hold keeps the mode `.off` - PU.67's decision to reverse, and the row says so.

## 3. Measured on the app path, on the named population - MET

- **Live-path floor ran on the composite tree**: committed **47**, correct **47**, precision 1.000
  (`pu69-swifttest.log:5274-5276`) - matching `PumpPhotoGate.readerCommitted`/`readerCommittedCorrect`
  47/47 (`PumpPhotoGate.swift:86,91`, verified in the file); "photos: 17 committing, **0 with a
  wrong cell**". The arm's only failed expectation (`:5289-5294`, `PumpReaderPipelineTests.swift:112`)
  is `numericTotal 181 == 183` - the pump-275 population, not a reading. **Zero new wrong
  readings**, both arms (annotated: 116 committed, 116 correct, precision 1.000, `:5242`; its red
  is `committed 116 >= committedFloor 118`, `:5247-5251`, again the 2 pump-275 cells my re-count
  confirms).
- **F1 ran on the population the note's drift rule produces at the build commit**: 188 (my
  independent re-count: 65 stills / 188 windows / pump-275 reviewed-cleared with 2 windows - exact),
  against the **captured** like-for-like sweep baseline through the same instrument
  (`pu69-corpus-release-oldsweep.log:374`: 0.73 / 1.98 / 1.00 / 8.4). Every reported statistic
  improved or held (median 0.73 → 0.60, p90 1.98 → 1.97, mean 0.95 → 0.89, >6° 1.00 → 0.66,
  CE@1° 0.697 [0.628, 0.758] vs the note's §5.3 baseline 0.690 [0.617, 0.754]) - F1's "materially
  worse" falsifier is not remotely tripped, and A7's guard-transfer bucket improved.
- **The interval convention (PU.68) is satisfied** for the one proportion F1 names (CE@1° with its
  Wilson interval in both the row and the test's own print, `PumpRowDeskewCorpusTests.swift:44-47`);
  the medians are not proportions and carry none, correctly.
- The composite-tree run also carries the rest of the floor family: oracle ratchet **774 committed,
  0.9987** (`pu69-swifttest.log:3423`, the known pump-031 cell), fragility **0.0412** ≤ 0.10
  (`:3544`), and `pump trace parity` green (`:5259`) - the `.onRefusal` end-to-end consumer of the
  new angle code that review 1 named.
- Provenance note, stated so the record is explicit: the full suite ended 04:00, before the four
  new unit tests (04:50-04:58) and the mutation round-trips that last touched
  `PumpFastHough.swift`/`PumpRowDeskew.swift` (mtimes 04:50:39/04:59:09). The suite's results
  remain valid for the final tree because the source CONTENT is behaviourally identical - the
  mutations were exact reverts, fingerprinted by the 04:55 Release corpus run reproducing the
  03:46 run's every statistic (0.60/1.97/0.89/0.66), by my reading of the final files (interp
  present `:194`, drop-not-wrap tail `PumpFastHough.swift:43-44`, no fusion code), and by my own
  10/10 green run of the final suite. The deskew unit suite on the final tree is covered by my run;
  nothing added since 04:00 can move livePath, the floors, the oracle or parity (test-file-only
  additions plus inert reverts).

## 4. No regression elsewhere - MET

- **Receipt leak**: cannot move, and the row now carries the code-fact argument review 1 accepted
  in lieu of a `PUMP_LEAK=1` run ("The leak cannot move: the display decision (`decideAt`) never
  calls deskew, which runs only in the retry after a frame is already routed as a pump"). Verified
  myself: `decideAt`'s body contains no deskew reference (grep over
  `PumpDisplayCapture.swift:180-260`: no match); the only deskew call sites are the mode-gated
  retry at `:346-349`, post-routing.
- **Annotated floor and the law's oracle ratchet**: both ran on the composite tree - 116/116
  precision 1.000 against the pump-275-shortened population (the 118 floor's red is corpus state,
  verified at the source: my re-count reproduces 181 = 183 − 2 and 67 = 68 − 1 exactly), and the
  oracle at 774/0.9987 with the known single wrong cell - neither fell.
- **Fragility** 0.0412 ≤ 0.10 (`pu69-swifttest.log:3544`).
- **Latency on the path the row touches**: the deskew step has Release numbers with captured
  artefacts on both sides (8.4 vs 2.8/2.9/3.1; the printed floor's traceability is item 6, fix 2 -
  a reporting defect, not a measurement gap). The row touches nothing the phone runs (`.off`,
  item 2), and the refusal-path TOTAL is explicitly PU.67's gate now, per note F4's own framing
  ("The deskew STEP falling ... is the real target") and PU.67's Checks ("a Release latency number
  for a refusal photo").
- The full-suite run has **exactly 2 issues in 2285 tests** (`pu69-swifttest.log:5300`), both
  accounted for above; the corpus deskew suite was correctly SKIPPED in that run (`:2244-2245`,
  `PUMP_DESKEW=1` unset) and measured separately in Release, as designed.
- **Commit hygiene (orchestrator, blocking for the commit, not for this row's verdict)**: the
  working tree currently has `Spike/ReceiptSpike/fixtures/corpus.sqlite` **STAGED** (index shows
  26,718,208 → 27,086,848 bytes) plus modified-but-unstaged `windows.json`,
  `pump-live/{corrections.jsonl,video-labels.json,videos.json}` - all owner-annotator state, none
  of it PU.69's. The commit must contain only the six PU.69 files; the staged sqlite must be
  unstaged first, and the working-tree `windows.json` must NOT ride along (on the committed corpus
  the two red floors are green by PU.78's own evidence - review 2's caveat, still standing, now
  with the staged file added).

## 5. Tests that would fail - MET

Every promise, its pin, and its red mutation - all logs read by me, all reds at the expected
values:

| Promise | Pin (file:line) | Red mutation evidence |
|---|---|---|
| Signed layout / mirror (A5, F2) | `findsTheTurn` ± (`PumpRowDeskewTests.swift:55-59`); `subSlopeRefinement` one-step (`:137-155`); slope-major index (`:107-109`) | `pu69-mutation-mirror.log`: 5 issues, +20 found −19.9, +6 found −6.03, +3 found −2.96 |
| sec³ weight (Alg. 1 lines 5-6) | `transformAndWeight` (`:110-115`) | `pu69-mutation-sec3.log`: ratio fails at 1.828 = \|1 − 2^1.5\| exactly |
| "never wrap" padding (A8) | `transformDoesNotWrap` (`:119-125`) | `pu69-mutation-wrap.log`: red at 2.0 = the wrapped pixel |
| Italic guard / horizontal-only (A3, F3) | `italicIsNotATurn` (`:95-99`) + `slantedStrokesAreNotATurn` (`:158-175`) | `pu69-mutation-fusion.log`: slanted strokes red, "turned to 10.296" = the 10° lean |
| Quadratic refinement (A2) | `subSlopeRefinement` (F2 one-step) + corpus pair | `pu69-mutation-interp.log`: red at the then-shipped 0.056 tolerance (found 2.2457 = bare argmax); `pu69-corpus-no-interp.log` (median 0.63, p90 2.01) vs `-with-interp.log` (0.60, 1.97) |
| Confidence exposed (A6) | `confidenceIsAlwaysReported` (`:127-134`); F6 measurement test (`PumpRowDeskewCorpusTests.swift:62-95`) | peakRatio ≥ 1+gain is construction-pinned; F6 fails on empty good/bad (`:94`) |
| Large-turn output sizing (A7 transfer) | `largeTurnRecoversTheRowSize` (`:61-69`), kept green | (pins the kept behaviour; its mutation target `rowSize` survives in the output path) |

**The refinement ruling, stated as a judgment so the record shows it was made, not missed.** The
SHIPPED `subSlopeRefinement` (one-step tolerance) stays green if the refinement is deleted
(0.112 < 0.225 - I computed it from the mutation log's own values). Taken alone that is the
template's PARTIAL shape. It is not PARTIAL here, for four reasons: (1) the template's evidence
rule - "the orchestrator's mutation of it turned the test red (the mutation and its red output are
in the gate evidence)" - is literally satisfied: `pu69-mutation-interp.log` is that mutation and
that red output, against the test as first shipped; (2) the tolerance relaxation is physically
justified and disclosed at the pin itself (`:139-145`): the note's Theorem-2 dyadic deviation
bound (~1.3-2.3 px at n = 256) means a clean synthetic edge cannot localise to a quarter step, so
NO tolerance exists that passes with the refinement and fails without it on that synthetic - the
mutation log's own numbers show the no-refinement error (0.112) is exactly the half-step, i.e. of
the same order as the pattern bias itself; (3) the gain is instead measured where it is real, with
captured Release artefacts on both sides (median 0.63 → 0.60, p90 2.01 → 1.97, CE identical), and
the row text says exactly that ("load-bearing on the corpus, not on a synthetic ... because the
dyadic patterns' own bias exceeds a half step on a clean edge"); (4) CLAUDE.md's comment rule is
satisfied by its own escape clause - the comment no longer promises what no test enforces; it
names the corpus measurement as the check. What is NOT claimed anywhere is that the default suite
would catch a refinement deletion; a future editor deleting `:194` would see green synthetics and
a corpus median move 0.60 → 0.63 inside a reporting-only test. That residual risk is the declared
trade, and I accept it. (The `minimumGain` re-base still has no mutation of its own - review 2
noted it, did not require it, and I concur: the gate is indirectly pinned by
`confidenceIsAlwaysReported`'s construction assertion and `levelStaysUpright`.)

## 6. Docs reconciled - PARTIAL

- **`docs/EXTRACTION.md:1111-1124`**: accurate on mechanism (mirror, dropped vertical band, SSG +
  sec³, quadratic refinement, 96 px with its reason, three statistics, the PU.76 re-home with the
  PU.70 cut stated, "Nothing on the app path changes until row deskew is enabled (PU.67)") and its
  agreement numbers match the artefacts digit-for-digit (188; 0.73 → 0.60; 1.98 → 1.97; 1.00 →
  0.66; 0.697 [0.628, 0.758]) - **except the latency floor "2.7-3.1" (`:1120`), whose 2.7 end
  matches no artefact** (closure 1 above). No numbered decision owns the deskew method (the diff
  touches no Decision heading - verified by hunk scan), so the prose paragraph is the right home.
  The old PU.65/67 paragraph below reads as a dated historical record beside the new one, which
  explicitly says "It replaces a 72-trial warp sweep" - acceptable as reviews 1-2 ruled.
- **`docs/TASKS.md:1072`**: ticked; index row agrees (`:171`, both index scripts exit 0); scenario
  named (J4); the Built text carries the mechanism, every departure with its A-number, the drift
  clause, the full distribution with the interval, the tests 10/10, all five mutations with their
  logs, the F6 closure, the PU.76 re-home (confidence AND bridge), the latency re-home to PU.67,
  and the leak argument. Outstanding: the same 2.7 floor (fix 2).
- **`docs/ERRORS.md` / `docs/JOURNEYS.md`**: correctly untouched (git status: neither modified) -
  nothing user-visible changes while the app runs `.off`.
- **CLAUDE.md comment rules in touched files**: both review-1 violations remain fixed
  (`PumpRowDeskew.swift:26-29` - the honest runtime-turn justification, false "past 15 degrees"
  claim gone; `PumpRowDeskewCorpusTests.swift:9-11` - the like-for-like 0.73/1.98 with the
  EXTRACTION authority link). Comments are present-tense current truth; row-id pointers follow the
  tree's standing precedent; citations name sources, not history. **One violation open:
  `PumpRowDeskewCorpusTests.swift:60`'s stale "so PU.70 can fit a threshold there"** (fix 1).
  Nits, non-blocking (the species review 2 already accepted with links present): accuracy scores
  duplicated in comments - the corpus-test header's 0.73/1.98 (review-1-prescribed content, linked)
  and `subSlopeRefinement`'s "median 0.63 -> 0.60 deg" (its authorities are linked for the bias
  claim; the pair is also in the row, so a link-only form exists if the orchestrator prefers it).

## 7. Everything the row promised - Checks cell sentence by sentence

1. **"Angle from the published FHT method (a C/Accelerate kernel if the note says the Swift loop
   cannot meet it)" - MET.** The note's verdict is "no C or C++ target is needed; the Swift loop
   CAN meet it" (§3); the build is pure Swift, no new target, no `Package.swift` change; the
   Release step cost (~3 ms/row captured) sits where the note predicted and three orders below the
   paper's per-angle-scheme comparison. Fidelity per item 1.
2. **"The sweep is retired or kept only as the note justifies" - MET.** Retired outright:
   `coarseStep`, `fineStep`, `profileSharpness` have zero remaining code references (grep over
   `ios/` - no match); the row says "retired"; `rowSize`/`largeTurn` survive only in the output
   path, which A7's own text and the §3 mapping table keep ("Output geometry - unchanged"),
   disclosed as such.
3. **"Angle agreement with the sweep on the 190 heldout hand quads ... reported as a distribution"
   - MET.** Run on 188 - the note §5.2 drift-rule re-count at the build commit, exact per my
   independent count, and the row now SAYS so in words (closure 2-i). Reported as a distribution:
   median, p90, mean, the >6° bucket, and CE@1° with its Wilson interval, against the captured
   like-for-like sweep baseline through the same instrument plus the note's §5.3 proxy baseline for
   CE - every statistic improved or held; F1 not falsified; A7's guard bucket beat its bound.
4. **"App path live >= PU.67's count at zero new wrong readings" - MET.** The explicit legitimate
   deferral (ruled plain in item 1) now carries the measurement review 1 conditioned it on:
   livePath on the composite tree at 47/47, precision 1.000, zero wrong cells on either arm
   (`pu69-swifttest.log:5274-5276`), matching `PumpPhotoGate`'s constants; PU.67's row owns the
   deskew-arm re-measure and says so.
5. **"A Release latency number for the refusal path, before and after" - MET as re-homed; the
   step number's printed floor needs the one-word reconciliation.** The re-home is explicit in the
   row ("re-homed to PU.67's gate (it only exists where the retry runs)"), PU.67's Checks carry
   the refusal-photo number and its row's new note stacks it with the re-measure; the step-level
   before/after - note F4's "real target" - has captured Release artefacts on both sides (8.4 vs
   2.8/2.9/3.1). The only defect is the printed "2.7" floor with no artefact (fix 2), which does
   not change the promise's substance.
6. **"The confidence is exposed for PU.70" - MET.** Exposed (`Result.confidence`,
   `PumpRowDeskew.swift:50-70`, populated on every searched crop including refusals `:87`), with
   exactly A6's three published-shape statistics; MEASURED (F6 on the reviewed TRAIN split,
   Release: good 458 / bad 108, AUROC peakRatio **0.653**, dominance **0.689**, peakMass **0.700**
   - `pu69-corpus-release.log:379`, digit-for-digit the row's report; the note's ~0.5 falsifier is
   not tripped and the row says "a modest, real separation, not falsified" - honest); pinned in the
   default suite (`confidenceIsAlwaysReported`, green in my run); the consumer question resolved in
   writing (PU.70 cut → confidence and the note §3's `deskewed` degrees+confidence bridge land with
   PU.76, stated in the row AND EXTRACTION `:1122-1123`); the bridge itself is legitimately
   unchanged quad-only (`:275-279`) now that the row says where the variant lands. The one miss is
   the stale test comment naming PU.70 - item 6, fix 1.

## Verdict: INCOMPLETE

Two one-line residuals, both in the exact places the third pass claimed closed; everything else -
fidelity, wiring, measurement, no-regression, pins and mutations, and every Checks-cell promise -
is MET, with the refinement-pin judgment recorded above. Neither fix needs a new measurement; both
are edits to files already in the diff.

1. **Re-point the stale PU.70 comment.** `ios/Tests/TankbookCoreTests/PumpRowDeskewCorpusTests.swift:60`
   ("on the TRAIN split so PU.70 can fit a threshold there") names a `[cut]` row as the test's
   purpose. Align it with `PumpRowDeskew.swift:61` (row-free: "for the threshold fit on the train
   split") or point it at PU.76 as the row and EXTRACTION now do. CLAUDE.md current-truth rule;
   this file is new in this diff, so the comment rules apply to it squarely.
2. **Make the printed latency floor traceable.** `docs/TASKS.md:1072` and `docs/EXTRACTION.md:1120`
   print "2.7-3.1 ms per row across four Release runs" citing `/tmp/agentlogs/pu69-corpus-*.log`,
   whose FHT values are 2.8 / 2.9 / 3.1 - "2.7" is in no artefact and the glob does not cover the
   run that produced it. Either (a) print the captured span - e.g. "8.4 -> 2.9-3.1 ms per row
   (captured Release runs; the no-refinement variant read 2.8), the higher ones with training
   running" - or (b) capture the log of a quiet-machine run that reads 2.7 and keep it under the
   glob. Review 2's fix 1 exists because printed numbers must match their artefacts; the range
   form narrowed the gap but did not close it.
3. **Then re-dispatch this review (fresh copy, same row).** Items 1-5 and 7 need no re-work; the
   verdict turns entirely on the two edits above. No gap here needs a new row.

Found and not fixed, with owners named:
- **Commit hygiene (orchestrator, must handle BEFORE the commit)**: `Spike/ReceiptSpike/fixtures/corpus.sqlite`
  is **staged** in the index (26.7 → 27.1 MB) and `windows.json` + the three `pump-live/` files are
  modified - all owner-annotator state. Unstage the sqlite; commit only the six PU.69 files
  (`PumpFastHough.swift`, `PumpRowDeskew.swift`, `PumpRowDeskewTests.swift`,
  `PumpRowDeskewCorpusTests.swift`, `docs/EXTRACTION.md`, `docs/TASKS.md`); do not commit the
  working-tree `windows.json` (its pump-275 state is what reddens the two floors; on the committed
  corpus they are green per PU.78's evidence).
- Review 1's fix 7 (a formal owner OK for the power-of-two padding in place of the mapping table's
  FHT2DS/2DT plan) remains the orchestrator's call; I concur with reviews 1-2 that it needs
  neither - the published base algorithm's own `n = 2^q` input domain (note §2.2), disclosed in
  the row text.
- PU.67's open row still describes the retired method in its body text; its dated 2026-09-24 note
  corrects the record for now, and the row text should be updated when it reopens (review 2's
  carried item, still standing; its re-measure also discharges PU.81's and the re-homed
  refusal-path latency in one run).
- Non-blocking observations: the full package suite (04:00) predates the final four unit tests -
  accepted on the fingerprint argument in item 3, with my 10/10 run covering the final deskew
  suite; the new code adds single-letter `identifier_name` and four `line_length` warnings (lint
  exit 0, same species as the file's own precedent); accuracy scores duplicated in two test
  comments where CLAUDE.md prefers links (both have authority pointers; the orchestrator may
  link-only them while making fix 1).
