# PU.69 completeness review - row angle by a fast Hough transform, with a confidence

Run of `agents/briefs/REVIEW-COMPLETE-PU.69.md` (template `REVIEW-PU-COMPLETENESS.md`), 2026-09-24.
Read-only except this file. Tree state reviewed: the uncommitted PU.69 diff
(`PumpFastHough.swift` new, `PumpRowDeskew.swift`, `PumpRowDeskewTests.swift`,
`PumpRowDeskewCorpusTests.swift` new, `docs/EXTRACTION.md`, `docs/TASKS.md`) on top of HEAD
`bd840ce4`, with the concurrent uncommitted PU.78/PU.72/PU.81 edits present and ignored except
where they set the constants PU.69 is read against (`PumpPhotoGate` 47/47/183,
`committedFloor` 118).

**Evidence I generated myself** (the machine may have been loaded; said where it matters):

- `PUMP_DESKEW=1 swift test --filter PumpRowDeskewCorpusTests` (DEBUG, final tree, exit 0):
  `n 188, median 0.60 deg, p90 1.97 deg, mean 0.89 deg; >6 deg n 5 median 0.66` - independently
  reproduces the row's and EXTRACTION's FHT-side numbers. The DEBUG `116.2 ms/row` is meaningless;
  I did not reproduce the Release timing. This run also proves the new corpus test compiles and
  passes on the final tree - no captured log covered that (the mutation logs predate its final
  mtime 03:04:32).
- `swift test --filter PumpRowDeskewTests` (DEBUG, final tree): 6/6, exit 0.
- Python re-count of the population from the working tree's `windows.json`/`split.csv`: 65 heldout
  reviewed rot-0 stills, **188** transaction windows with quads; `pump-275` has `reviewed` cleared
  and carries 2 transaction windows - 190 minus 2 = 188 exactly.
- Read both mutation logs and the app-bundle log: `/tmp/agentlogs/pu69-mutation-mirror.log` (red,
  5 issues: with the mirror dropped, +20.0 reads -19.9, +6.0 reads -6.03, +3.0 reads -2.96 - the
  sign mechanism is pinned), `/tmp/agentlogs/pu69-mutation-sec3.log` (red: the sec^3 weight dropped,
  `values[3]/values[0]` fails at 1.83 against 2^1.5), `/tmp/agentlogs/pu69-app.log` (`Executed 301
  tests, with 0 failures`, TEST SUCCEEDED, 03:05 - after the PU.69 edits landed 02:53-03:04, so the
  app target compiles the new code).
- `scripts/tasks-index.py --check` exit 0 (index row `docs/TASKS.md:171` reads `[x]`);
  `scripts/scenario-index.py --check` exit 0 (row names J4).
- I did NOT re-run the old-sweep baseline (0.73/1.98/1.00/8.4 ms): it needs the file swapped back,
  which this review may not do. Those four numbers and the Release latency rest on the
  orchestrator's report, with no captured log.

The code itself I judge sound and faithful to the note; the gaps are measurement, mutation and
comment/doc gaps, and every one is cheap to close.

## 1. Fidelity to the published method - MET

Algorithm 1 (arXiv:1912.02504 §3, as the note fetched it) step by step against the build:

- Step 1 (derivative + FHT): the across-row first difference `d = gray[x, y+1] - gray[x, y]`
  (`PumpRowDeskew.swift:171-177`) is A4's named adaptation (the paper's operator is undefined in
  the fetched text, note §2.7-6; the difference operator "ships first" per A4). The transform
  (`PumpFastHough.swift:16-27`) is the Brady-Yong recursion: dyadic column bisection, merge =
  vector add of one shifted row-pair per accumulator row (`:33-47`) - the note §2.2's Theorem-1
  shape.
- Step 2 (Kh^3 * SSG): `criteria` (`PumpRowDeskew.swift:206-220`) computes
  `(1 + s^2)^1.5 * sum-of-squared-successive-differences` with `s = t/(n-1)` (`:216-217`) - exactly
  the paper's `Kh[i] = sqrt(1 + i^2/(H-1)^2)` cubed times SSG (Alg. 1 lines 5-6; Kunina eq. 4 as
  note §2.4 resolves the 3/2-vs-3 ambiguity, in favour of the skew paper's unambiguous form, which
  is what is implemented).
- Step 3 (vertical band): dropped - A3, named and justified (italic guard); only the
  mostly-horizontal accumulator and its mirror exist (`:178-179`).
- Step 4 (Recalculate): correctly absent - one band survives, per A5's note.
- Step 5 (Combine/argmax/arctan): the stitched signed curve (`:185`), argmax with the `> 0` guard
  (`:187`), quadratic sub-row refinement (`:188-193`), `atan` of the refined slope (`:194`).
- Gate and confidence: not in the paper (note §2.7-1,4); both are A6's named choices - the
  `minimumGain` 0.05 ratio gate re-based verbatim onto the SSG curve (`:199`, value unchanged
  `:41`, not re-fitted), and `Confidence` (`:58-68`, set at `:195-198`) is exactly A6's three
  published-shape statistics: Leptonica-style peak-over-minimum, Kunina-eq.-6-shaped dominance
  computed as peak-vs-range-median and labelled as such (`:63-64`), raw peak mass.

Departures, each checked against the note's §4 list: A1 (scale - ruled below), A2 (interpolation -
ruled below), A3, A4, A5 (signed coverage - the mirrored second transform `:175,:179,:185` is the
flip relation of 1811.06378 §3.3's quadrant concatenation restricted to the horizontal band; A5
required the choice to be recorded in the build, and the row text records it: "both slope
directions via the mirrored crop"), A6, A7 (ruled below), A8 (ruled below), A9 (`levelAngle` /
`levelled` / `unlevelled` untouched by the diff), A10 (measurement, item 3).

Two implementation choices go beyond the A-list; both stay inside published mechanisms the note
itself cites, and both are disclosed in the row text ("zero-padded to a power-of-two width and
height + width rows"):

- **Power-of-two width padding** (`PumpFastHough.swift:17-18`) instead of the mapping table's
  "arbitrary-size variant (FHT2DS/2DT)". The base Brady-Yong algorithm is defined for n = 2^q
  (note §2.2); zero-padding to that domain is the published base's own input regime, not a method
  departure - FHT2DT exists to avoid the padding's cost, and the measured cost (2.7 ms/row Release,
  3.1x better than the sweep) shows nothing needed avoiding. The accuracy bound applies at the
  padded n (log2(512)/6 ~= 1.5 px worst case) - inside A1's owned consequence. Ruled acceptable;
  if the orchestrator reads §4's fence as covering plan-level choices too, a one-line owner
  confirmation closes it.
- **One-sided offset range** (offsets 0..height+n-1; lines that would enter through the crop's top
  edge at x=0, i.e. negative offsets, are not representable). Irrelevant for the target population:
  the crop is the row's own upright bound padded 30 % (`PumpRowDeskew.swift:78-79`), so the row's
  edges start at offset >= 0 in one direction or, via the mirror, the other. Empirically unpinned
  by a pathology: +-20 deg synthetics inside 0.6 deg, the >6 deg corpus bucket at median 0.66
  (verified by my re-run).

### Row-specific rulings the brief asked for

- **Sign convention (positive = clockwise, y down): MET and mutation-pinned.** Documented at
  `PumpRowDeskew.swift:51-52` and `:183-184`; the transform's "rises t rows (y grows with x)"
  (`PumpFastHough.swift:14-15`) is falling-right on screen = clockwise; `atan` of the signed
  position (`:194`) feeds `rotatedRect`, whose matrix turns clockwise for positive degrees
  (`:150-157`); `findsTheTurn` pins both signs (-20..+20 within 0.6 deg,
  `PumpRowDeskewTests.swift:55-59`); the mirror-drop mutation flipped every positive angle to
  negative and went red with 5 issues (captured log, verified above).
- **A8 black zone: satisfied, by a stronger mechanism than the letter of A8.** Padding the
  accumulator to `height + n` rows (`PumpFastHough.swift:19`) plus the non-cyclic merge tail (the
  out-of-range right-half contribution is dropped, never wrapped: `:43-44`) makes wrap contamination
  structurally impossible - which is the entire purpose of the paper's h x h / w x w padding
  (note §2.3). A8's second clause ("zero-coverage rows excluded from the argmax") has no referent
  in this geometry: the black-zone triangle arises from cyclic wraparound, and with one-sided
  offsets every slope inside the +-30 deg selection bound (`PumpRowDeskew.swift:181`) crosses the
  crop at some offset. The residual risk A8 named - the sec^3 weight growing with |t| and favouring
  coverage-starved slopes - is bounded by that selection bound and the `curve[peak] > 0` guard
  (`:187`). Yes: this satisfies A8.
- **A2 sub-slope interpolation: matches the note exactly.** The standard three-point parabolic
  vertex `position += 0.5*(a-c)/(a-2b+c)` with the concavity guard `denominator < 0`
  (`PumpRowDeskew.swift:189-193`), through the SSG maximum and its two neighbours, in slope-index
  space, before the `arctan` (`:194`) - A2's "Lagrange/quadratic fit ... before arctan", the
  Leptonica `numaFitMax` family A2 cites. Interior-peak-only is a safe degeneracy guard (a boundary
  peak falls back to the bare argmax, the paper's own behaviour). Fidelity MET; test coverage of it
  is PARTIAL - item 5.
- **A7: keeping `rowSize`/`largeTurn` for OUTPUT sizing only is NOT a departure - it resolves a
  contradiction inside A7 on the side that preserves measured behaviour.** A7 says "retire" but also
  that the >6 deg intent "is already carried by `rotatedRect` + the unchanged output path", and the
  §3 mapping table says "Output geometry - unchanged". Those are consistent only under the reading
  the build took: `rowSize` retires from the SEARCH (its per-trial crop reshaping was structural to
  per-angle warping, which is gone - the diff deletes the whole `score` closure), while the output
  path stays byte-identical to HEAD (`:86-91` is context in the diff, only `confidence` was added).
  The note said `largeTurnRecoversTheRowSize` "retires with rowSize" - the build instead kept it
  green, which is the conservative choice: it pins the very intent A7 says is carried. A7's guard
  transfer is met and beaten: the >6 deg bucket measures median 0.66 (n = 5, verified by my re-run)
  against the note's 1.43 proxy figure and the like-for-like sweep's 1.00. Disclosed in the row text
  ("kept for the OUTPUT box's size only").
- **The 48 -> 96 px input change: the A1-fallback claim is SUSTAINED.** The remedy is exactly the
  fallback's named parameter move ("raise the FHT input height toward the native crop"): the native
  crop median height is 133 px (note §3), 96 sits below it, and 96 has an independent justification -
  it is the read path's own strip height (`PumpReader.swift:13`, verified), so the search never
  samples below the scale the read uses. The stated trigger ("48 px gave a 0.6-0.7 deg bias on
  synthetic turns") differs in letter from the fallback's condition (F1's distribution clustering at
  the grid step) but is an instance of the same scale-limited error regime the fallback exists for:
  halving the strip height halves the width, halves n and doubles the grid step (note §5.5's
  inverse-width arithmetic). The move is disclosed in both the row text and EXTRACTION, and F1's
  outcome confirms it improved agreement rather than degrading it (0.60 vs the like-for-like 0.73).
  The note pre-authorises it: "a parameter move inside the published method, not a new departure."
- **The deferral of "app path live >= PU.67's count": the row text DOES make it plain.** "The app
  path is unchanged (row deskew is off until PU.67); the deskew arm's live count is PU.67's
  re-measure" states the fact, the reason and the future owner, and PU.67's row is open carrying
  exactly that re-measure. I verified the code fact behind "unchanged": the app's reader is built at
  the default `.off` (`ios/App/Sources/Capture/CapturePipeline.swift:28` ->
  `PumpDisplayCapture.makeReader`, `PumpDisplayCapture.swift:106-110` -> `PumpReader.swift:33,35`),
  and every caller of the changed code is mode-gated - classify's turned-rows retry
  (`PumpDisplayCapture.swift:346-349`), `readPhotoDetailed`'s `.onRefusal`/`.level` branches
  (`PumpRowDeskew.swift:298-315`), `candidates(for:deskewRows:)` (`PumpReader.swift:54-56`). With
  `.off`, no changed line executes on the phone. What is missing is the measurement that the
  convention asks for on top of that argument - item 3.

## 2. Wired into the app path, not only the harness - MET

The new method sits inside `PumpRowDeskew.deskew` (`PumpRowDeskew.swift:74-113` -> `angle(of:)`
`:166-201` -> `PumpFastHough.transform`), which is the function classify's own refusal retry calls:
`PumpDisplayCapture.swift:346-349` -> `candidates(for:deskewRows: true)` `PumpReader.swift:54-56`
-> `PumpReader.deskewed` `PumpRowDeskew.swift:273-277`. It is also what `readPhotoDetailed`'s
`.onRefusal` and `.level` arms run (`:304-315`). No `#if DEBUG` anywhere in the new or changed code
(grep over both source files and the tests: no match), so it compiles into the app target in both
configurations; the app-bundle run (301/301, Debug) and the `-c release` corpus run cover both
compiles. This is not a harness-only or DEBUG-only seam: it is dormant on the phone solely because
PU.67's documented hold keeps the mode at `.off`, which is PU.67's decision to reverse, not a wiring
gap of this row - and the row text says so plainly (ruled above).

## 3. Measured on the app path, on the named population - PARTIAL

- **F1's agreement gate ran, on the population the note's drift rule produces, and I reproduced its
  FHT side myself**: n 188, median 0.60, p90 1.97, mean 0.89, >6 deg n=5 median 0.66 (my DEBUG
  re-run; the row's Release numbers agree to the digit). The population drift 190 -> 188 is exactly
  the note §5.2 rule applied at the build commit (pump-275's re-annotation cleared `reviewed`,
  dropping its 2 windows - verified by my count), and the >6 deg bucket is still the note's 5 boxes.
- **The sweep side (0.73 / 1.98 / 1.00 / 8.4 ms) has no captured log** - it was a temporary
  file-swap run this review cannot reproduce read-only. All four numbers rest on the orchestrator's
  report. Direction of every reported statistic is improvement or flat, so F1's "materially worse"
  falsifier is clearly not tripped.
- **The live-path floor never ran on the composite tree.** `pu78-gate.log` is timestamped 01:24;
  `PumpFastHough.swift` appeared at 02:53:57 and `PumpRowDeskew.swift` was last written 03:03:57 -
  no full package suite covers PU.69's edits. The PU.69 evidence is filtered runs plus the app
  bundle. `livePath` cannot move under `.off` (the item-2 code fact), but the convention is
  measurement, not argument, and one suite genuinely exercises the new code end-to-end and has
  never run: `PumpTraceParityTests` builds its reader at `.onRefusal`
  (`PumpTraceParityTests.swift:43`). Nothing in the evidence cross-checks `PumpPhotoGate`'s reader
  constants (47/47/183, `PumpPhotoGate.swift:86,91,95`) against a live run of this tree.
- **Distribution reporting is thin against F1's own baseline**: the note compares against
  "median 0.68 deg, CE@1 deg 0.690 [0.617, 0.754]" (§5.3/§5.6-F1); the build reports
  median/p90/mean/one bucket and no CE@1 deg, and carries no interval beside any figure (PU.68 has
  landed; the row's medians are not proportions, but the within-1 deg rate is, and it is the one
  baseline statistic F1 names that went unreported). The row text also never explains 188 vs the
  Checks cell's promised 190 - the drift rule was applied but not stated.

Needed: one full `swift test` on the composite tree with livePath's committed/correct reported
against the `PumpPhotoGate` constants (fix 1); CE@1 deg with its Wilson interval and a drift clause
in the row text (fix 6).

## 4. No regression elsewhere - PARTIAL

- **Receipt leak**: cannot move - routing (`decide`) never touches deskew code; classify's retry is
  post-routing and mode-gated, and the app is at `.off`. Code-fact argument only; no measurement in
  evidence (the leak suite is `PUMP_LEAK=1`-gated, so even a full `swift test` skips it unless run
  with the env - acceptable to rest on the code fact here, but say so).
- **Annotated floor and the law's oracle ratchet**: no run on the composite tree in the evidence
  (`committedFloor` 118, `PumpReaderPipelineTests.swift:30`, and the ratchet are package tests; the
  only full-gate log predates the edits). Same remedy as item 3 - one suite run reports both.
- **Latency on the hot path**: a Release per-row number exists (8.4 -> 2.7 ms, orchestrator-
  reported, no captured log). The refusal-path total is item 7, sentence 5.

## 5. Tests that would fail - PARTIAL

What is pinned, with red mutation evidence (both logs read):

- Accumulator layout and the sec^3 weight: `transformAndWeight`
  (`PumpRowDeskewTests.swift:101-116`; `sums[3*rows+0] == 4` pins slope-major layout directly, so
  F2's named transpose mutation would be caught by it even though that specific mutation was not
  run); the sec^3-drop mutation is red (captured log).
- The signed/mirror mechanism: `findsTheTurn`'s +- cases plus the mirror-drop mutation red with
  5 issues, sign flips visible in the log (captured).
- The italic guard's first clause (F3): `italicIsNotATurn` green after the change (6/6, reproduced
  by me on the final tree).

What is NOT pinned - each currently stays green with the promise removed:

- **(a) The A2 quadratic refinement.** No recorded mutation removes it, and a plain argmax would
  likely keep the suite green: the grid step at the synthetic strips' widths is ~0.22-0.45 deg
  (n = 128-256), well inside `findsTheTurn`'s 0.6 deg tolerance. A promise in the row text, in the
  file's doc comment (`PumpRowDeskew.swift:163-164`) and in EXTRACTION with no failing test behind
  it.
- **(b) F3's named mutation (enabling the mostly-vertical fusion) was not run**, so the italic
  guard has no demonstrated teeth - it is green, but nothing shows it CAN go red. The mutation
  needs ~10 lines of throwaway fusion code (transform the horizontal difference or the transposed
  crop, add it to the curve); the note names it explicitly as the falsifier.
- **(c) The "never wrap" promise** in `PumpFastHough.swift:12-13` ("so the patterns' shifts never
  wrap onto real pixels"): a cyclic-wrap mutation of the merge tail (`:43-44`) would likely keep
  every test green (the contamination lands at high offsets the synthetics and the layout pin do
  not read). CLAUDE.md's comment rule: a behavioural promise needs the test that fails when it
  breaks.
- **(d) Confidence has no test at all.** No file under `ios/Tests` reads `Result.confidence` or
  `PumpRowDeskew.Confidence` (grep). The row promises "the confidence is exposed for PU.70" and
  nothing asserts it is populated, non-nil on a turned row, or shaped as A6 specifies.
- **(e) The `minimumGain` re-base onto the SSG curve** (`:199`) has no mutation; on the symmetric
  synthetics, deleting the gate would likely leave `levelStaysUpright` green.

## 6. Docs reconciled - PARTIAL

- `docs/EXTRACTION.md`: the PU.69 paragraph (`:1111-1125`) is accurate - every number in it
  matches my independent re-run or the gate evidence; it names the mirror mechanism, the dropped
  vertical band, the sec^3 weight, the interpolation, the 96 px input with its reason, the three
  confidence statistics, and states plainly "Nothing on the app path changes until row deskew is
  enabled (PU.67)". No numbered decision owns the deskew method (Decisions 1-11 checked; none
  touched), so prose is the right home. MET.
- `docs/TASKS.md`: the row is ticked, the Built text carries the numbers, the index row
  (`:171`) agrees, both index scripts exit 0. Missing clauses are listed under items 3 and 7.
- `docs/ERRORS.md` / `docs/JOURNEYS.md`: correctly untouched - nothing user-visible changes while
  the app runs `.off`. MET.
- **CLAUDE.md comment rules - two violations in touched files:**
  1. `PumpRowDeskew.swift:26-27` still reads "The corpus has rows turned past 15 degrees (a display
     shot from the side)". The research note's finding §7-1 established this is false against the
     drawn evidence (pixel-space max 10.35 deg, none past 12) and assigned the fix to THIS build
     twice: "Owner: the PU.69 build (comment fix rides the file rewrite)" and §6's "the
     `PumpRowDeskew.swift:22-23` comment corrected per §7-1 in the same change that rewrites the
     file". The file was rewritten; the known-false comment survived. The honest replacement exists
     in the note: the range may still stand on runtime reader-side turns (PU.65's tilted list, not
     statically reproducible), not on drawn corpus angles.
  2. `PumpRowDeskewCorpusTests.swift:8-10`: "the 72-trial sweep it replaced measured median 0.68
     deg, p90 1.99 on the same population" - wrong on the population (0.68/1.99 are note §5.3's
     PROXY figures over 174 detector-matched boxes; the like-for-like sweep through this very
     instrument measured 0.73/1.98, as the row text itself reports), and it copies mutable accuracy
     scores plus a before/after story into a comment, which CLAUDE.md forbids - link
     `agents/research/PU.69.md` §5.3 or drop the numbers.
  Row-id references in comments ((PU.69 note A6) `:58-59`, the research-note path `:19`, the test
  header) follow the tree's standing precedent - HEAD's sources carry dozens of `(PU.38)`/`(PU.53)`-
  style pointers - and are not flagged.
- **Found and not fixed, owned elsewhere** (this review may not write them): the orchestrator-owned
  correction note on the PU.65/PU.67 row texts' normalised-space angle statistics ("max 18",
  note §7-1) has not been appended; and PU.67's OPEN row still describes the now-retired method
  ("The method is a projection-profile skew estimate (row-brightness profile sharpness)") - PU.67's
  re-measure will run the FHT, so its row text needs that update when it reopens. The old
  PU.65/PU.67 EXTRACTION paragraph's present-tense method sentence is acceptable as a dated
  historical record sitting next to the new paragraph; an optional "(method superseded above)"
  pointer would remove any doubt.

## 7. Everything the row promised - Checks cell sentence by sentence

1. **"Angle from the published FHT method (a C/Accelerate kernel if the note says the Swift loop
   cannot meet it)" - MET.** The note's verdict is "no C or C++ target is needed; the Swift loop
   CAN meet it" (§3); the build is pure Swift, no new target, no Package.swift change, and the
   Release per-row cost (2.7 ms, orchestrator-reported; my DEBUG re-run confirms the mechanism)
   sits where the note predicted. Fidelity per item 1.
2. **"The sweep is retired or kept only as the note justifies" - MET.** Retired outright:
   `coarseStep`, `fineStep`, `profileSharpness` are gone from the tree with zero remaining
   references (grep over ios/docs/design/Spike); the row text says "retired".
3. **"Angle agreement with the sweep on the 190 heldout hand quads ... reported as a distribution"
   - PARTIAL.** Run on 188 - the build-commit re-count the note's drift rule mandates, verified
   exact by me - but the row text never explains the 190 -> 188 drift; the sweep baseline has no
   captured log; and the "distribution" is three statistics plus one bucket, omitting CE@1 deg,
   F1's own second baseline statistic, and every interval. Direction of travel is unambiguous
   (each reported statistic improved or held), so F1 is not falsified - the reporting just does not
   yet show the full picture F1 defined.
4. **"App path live >= PU.67's count at zero new wrong readings" - MET as an explicit, legitimate
   deferral.** The brief's question answered plainly: YES, the row text makes the deferral plain
   (quoted and ruled in item 1). PU.67 remains open and owns the re-measure; the code fact behind
   "unchanged" is verified (item 2). The condition on this verdict: the composite-tree suite run
   (fix 1) must confirm 47/47 in measurement, not only in argument.
5. **"A Release latency number for the refusal path, before and after" - PARTIAL.** What was
   measured and reported is the deskew STEP in Release, before and after, on the named population
   (8.4 -> 2.7 ms/row) - which the note calls "the real target" (F4: the refusal TOTAL is dominated
   by the second verify+read this row does not touch, and on the app the refusal path does not
   exist until PU.67 enables `.onRefusal`, whose own Checks already carry "a Release latency number
   for a refusal photo"). The substitution is defensible but was made silently: the row text offers
   the step number without saying the refusal-path promise moved to PU.67's gate. Neither latency
   number has a captured log. Needed: one sentence in the row re-homing the refusal-total number to
   PU.67 and naming the step number as this row's F4 evidence - or the refusal-path measurement
   itself, on a quiet machine per note §5.4's hygiene rule, with the log kept.
6. **"The confidence is exposed for PU.70" - PARTIAL, and this carries the review's largest gap.**
   Exposed it is: `Result.confidence` (`PumpRowDeskew.swift:53-55`), `Confidence` (`:58-68`) with
   exactly A6's three statistics, populated by every searched crop including refusals (`:85`). But:
   - **F6 never ran.** The note lists it among "the results that would falsify the row": if no
     statistic of the three separates high-error from low-error angles on the TRAIN split
     (e.g. AUROC ~0.5 for |err| > 2 deg vs <= 1 deg against drawn truth), "the 'with a confidence'
     deliverable fails even if the angles pass, and PU.70 has no input". Nothing in the gate
     evidence, the row text or EXTRACTION reports any separation measurement. The row is TITLED
     "with a confidence"; five of the note's six falsifiers were addressed (F1 run, F2 test-present,
     F3 half-run, F4 substituted, F5 deferred-by-code-fact) and the sixth was simply not run, and
     no row explicitly owns it. Either run it and report it in the row text, or move it into
     PU.70's Checks in writing (both rows) - never silently. If it fails, the row is falsified and
     the owner decides before any commit.
   - The note §3 Types paragraph planned the `PumpReader.deskewed` bridge "gains a variant that
     carries degrees+confidence out for PU.70"; the bridge is unchanged (`:273-277`, quad-only), and
     PU.70's consumer (`PumpDisplayCapture.passesSize`) reads rows through that bridge. Fine to
     leave for PU.70's wiring - but say so, in this row's text or PU.70's.
   - No test touches confidence (item 5d).

## Verdict: INCOMPLETE

The implementation is faithful, fast, disclosed and - on the angle side - better than what it
replaced; I reproduced its headline numbers myself. What is missing is evidence and two comments,
all cheap:

1. **Run the full package suite on the composite tree** (`cd ios && swift test`, exit code and
   counts reported): `livePath` committed/correct against `PumpPhotoGate` 47/47/183,
   `gateMirror`/`committedFloor` 118, the oracle ratchet and fragility, and `PumpTraceParityTests`
   (the one suite that runs the new angle code end-to-end, at `.onRefusal`). Optionally
   `PUMP_LEAK=1` for the leak, or state the code-fact argument (routing never touches deskew) in
   the row text instead. Keep the log.
2. **Run F6**: the three `Confidence` statistics against drawn-truth angle error on the TRAIN split
   (AUROC or equivalent, |err| > 2 deg vs <= 1 deg); report the result in the row text. If nothing
   separates, the row is falsified per the note - owner's call before commit. If the orchestrator
   judges the measurement PU.70's, re-home it explicitly in both rows' text.
3. **Close the refusal-path latency promise**: either the Release before/after refusal-path number
   (quiet machine per note §5.4, log kept), or one sentence in the row re-homing it to PU.67's gate
   and naming the 8.4 -> 2.7 ms step number as this row's F4 "real target" evidence. Keep a log for
   the Release corpus/baseline runs too - the four sweep-side numbers currently have no artefact.
4. **Fix the two comments**: `PumpRowDeskew.swift:26-27` (the false "turned past 15 degrees"
   claim the note assigned to this build - replace with the runtime reader-side-turn
   justification or drop it) and `PumpRowDeskewCorpusTests.swift:8-10` (the misattributed
   0.68/1.99 "same population" figures - link the note or use the like-for-like 0.73/1.98 from
   EXTRACTION).
5. **Make the unpinned promises fail-able** (item 5): (a) a mutation removing the quadratic
   refinement must turn a test red - today it likely does not, so tighten `findsTheTurn` or add a
   sub-grid case (a synthetic turn at a mid-grid angle, e.g. 3.3 deg, found within a quarter grid
   step); (b) run F3's named fusion mutation against `italicIsNotATurn` (red, then reverted);
   (c) pin the "never wrap" promise with a direct `PumpFastHough` unit test (an out-of-range
   contribution must be dropped, not wrapped) or its mutation; (d) assert confidence is populated
   (a turned synthetic row carries non-nil confidence, and a turned result's `peakRatio` is at
   least `1 + minimumGain`).
6. **Row-text clauses**: (i) 188 = the build-commit re-count under the note's drift rule (pump-275's
   re-annotation dropped its 2 windows); (ii) CE@1 deg beside the medians, with its Wilson interval
   (PU.68's convention); (iii) one line on where the `deskewed` bridge variant lands (this row or
   PU.70).
7. **(Optional, closes the fence question formally)**: a one-line owner OK - or a note addendum -
   for the power-of-two padding replacing the mapping table's FHT2DS/2DT plan. My judgment is that
   it needs neither (it is the published base algorithm's own input domain, disclosed in the row
   text); this item exists only so the judgment is not mine alone on the record.

Found and not fixed, with their owners named: the orchestrator's correction note on the PU.65/
PU.67 row texts' normalised-space angle statistics (note §7-1); PU.67's open row text still names
the retired projection-profile method; the old EXTRACTION PU.65/67 paragraph's present-tense method
sentence (optional pointer to the new paragraph).

Re-dispatch this review (a fresh copy, same row) once 1-6 are in; 7 is the orchestrator's call.
