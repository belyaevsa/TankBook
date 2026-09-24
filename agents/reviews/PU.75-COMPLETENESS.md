# PU.75 completeness review

Run 2026-09-24 against the working tree on `main` (HEAD `37197a09`; uncommitted changes under
review in the eight files named by the brief). Research note: `agents/research/PU.75.md`. Diff under
review: `PumpDisplayCapture.swift`, `PumpSegmentsModel.swift`, `PumpReader.swift`,
`PumpDisplayCaptureTests.swift`, `PumpSegmentsModelTests.swift`, `docs/LOGGING.md`,
`tools/pump-annotate/pipeline.js`, the PU.75 row (and RV.306 filed beside it, ignored). The row is
`[~]` - "M1 + M2 SHIPPED" with a "Left open, and why" list. My job is whether that partial state is
honest against the row's Checks cell and the note's fence (A4/A5).

**What I ran**: read-only git/grep/read inspection of the diff, the five consumers of
`Detection.textLines`, the app-target consumers, and the gate evidence in `/tmp/agentlogs/`
(`pu75-identity-main.log`, `PU.75.last.md`, `PU.75-codex.log`, `pu75-gate-2.log`,
`pu75-e5rt-ab.log`). No builds, no test runs, no writes except this file. I did **not** run
`xcodebuild … -only-testing:TankbookTests test` - see "the app-target bundle" below; no number was
missing, so machine load affects nothing I report.

## The seven checklist items

### Item 1 - fidelity to the published method: **MET**

M1 and M2 are built exactly as the note's §3 describes, and the two halves the row leaves open are
left open *by the note's own fence*, not dropped silently.

- **M1** (note §3, A1): `textLineCount` moved into the slow branch after `fastVerdict` abstains
  (`PumpDisplayCapture.swift:207-219`); the fast path carries the sentinel
  `textLinesNotMeasured = -1` (:76, :207-208); the slow path computes the real count (:218) exactly
  as before. `fastVerdict`'s `textLines` parameter stays in the signature and is still never read
  (:142, doc comment :135-137), which is the note's M1 premise. The `-1`-not-`0` choice matches A1's
  stated reason (a pump face can show 0 real lines, :73-75).
- **M2** (note §3, A2/A3): `PumpSegmentsModel.probabilities(cells:)` (`PumpSegmentsModel.swift:58-76`)
  builds each crop's `MLDictionaryFeatureProvider` exactly as `probabilities(cell:)` (:44-46 vs
  :63-65), wraps in `MLArrayBatchProvider`, one `predictions(fromBatch:)`, reads the 8 probabilities
  per row in input order (:70-74). Both call sites the note names are switched: the read's TTA via
  `PumpReader.averaged` (`PumpReader.swift:579-588`) and the verifier's per-candidate margin pass
  (:518-525). The verifier's margin pass previously wrapped each single crop in `averaged` (a divide
  by `max(1, 1) = 1`, exact); the new code calls `probabilities(cells:)` directly and computes the
  same `PumpCellReading.margin` per cell, then the same `mean = margins.reduce(0, +) / count` - no
  numeric or order change. Batching a fixed-shape model without re-export is A2's first branch.
- **M3 / vImage**: not shipped, and the note's §0.2/A4 measured that every vImage primitive
  resamples differently from our loops (4478/4608, 57354/57600 channel values differ) and that none
  is projective (no `vImagePiecewiseAffineWarp` in the iOS 27 SDK), so it is "not a pure speed
  change"; A4 makes it default-refuse and A5 forbids any CI/Metal projective substitute without the
  owner. Leaving it open is what the note *requires*, not an omission.
- **M4 / detector spike**: not shipped as a row; the note §5.4 measured that no post-training path
  works on the legacy pipeline (ct 9.0 rejects or crashes), a `REFUSED`-class spike result. Named
  open, consistent with the note.

No unlisted departure from the published method. The one deliberate re-framing (vImage conditional
rather than assumed) is A4's own language, so it is listed and justified.

### Item 2 - wired into the app path, not only the harness: **MET**

`decideAt` (`PumpDisplayCapture.swift:199`) is reached from `classify` (:328-334), which is
`CapturePipeline`'s entry point via `readPumpDisplay` -> `PumpDisplayCapture.read/classify`
(`CapturePipeline.swift:58-69`). `PumpSegmentsModel.probabilities(cells:)` and `PumpReader.averaged`
are internal package code called from the read and verify paths, all behind the public `classify` -
no `#if DEBUG` seam, no `PumpReadTool`-only or test-only route. The change compiles into Release:
the gate's app-target Debug build exited 0 against the changed `TankbookCore`
(`pu75-gate-2.log:2985`), and nothing here touches a `#if DEBUG`/`#if EXPERIMENTS` seam, so no
`RELEASE=1` gate is owed. The preview guidance is untouched and deliberately unaffected: it calls
`fastVerdict(rows:textLines: 0)` directly (`PreviewGuidance.swift:30`), never `decideAt`, as the
note M1 states.

### Item 3 - measured on the app path, on the named population: **MET**

`/tmp/agentlogs/pu75-identity-main.log` (the `main`-after-PU.74 re-run the brief names) shows the
package `swift test` over the pump suites: annotated **123/123** ("committed 123, correct 123,
precision 1.000"), live path **47/47** ("committed 47, correct 47, precision 1.000"), `heldout
classification 5/6 pumps (5 fast), 0/8 receipts leaked`. The fast frames print `textLines=-1`
(pump-032/042/038/092/062), the slow and receipt frames print real counts (31, 36, …). These match
`PumpPhotoGate`'s constants (47/47/183) that PU.74 set on `22559705`. The identity is the row's
"a speed change moves no reading" claim, and it holds: same 123/123 and 47/47 before = after (the
builder's before/after on the worktree base, `PU.75.last.md`, agrees: live 47/47, gateMirror
118/118, leak 6/116 routed / 0 committing). The row's own claimed movement - pump `appDecide`
78.5 -> 51 ms, `appClassifyAndRead` 499 -> 474 ms, receipts unchanged - is reported over the named
population (10 pump stills / 5 receipts), and the committed-cell precisions carry their Wilson
intervals in the logs. **Zero new wrong readings** (123/123 and 47/47, both precision 1.000).

One honesty caveat, already disclosed in the row's "Left open": the "Release" timings were measured
with `-Xswiftc -enable-testing` because `pump-read` uses `@testable import TankbookCore` and cannot
do a clean `swift build -c release` (`PU.75.last.md`). Before/after is still a fair comparison
(same config on both sides), but the absolute "Release" label is not a clean Release build - the
row's "Found beside it" sentence owns this, so it is disclosed, not hidden.

### Item 4 - no regression elsewhere: **MET**

Leak battery unchanged: 6/116 routed / 0 committing before = after (`pu75-identity-main.log`,
`PU.75.last.md`). Annotated floor and live floor both held at their PU.74 values (123/123, 47/47).
Latency has a number on the hot path it touched (`appDecide` 51 ms, `appClassifyAndRead` 474 ms
medians). The full-suite reds in the gate are both pre-existing and owned: `SyncWriteTriggerTests`
(RV.203, machine-load, named in the standing fences) and one Vision `e5rtError` in
`CaptureOrientationTests` (the A/B in `pu75-e5rt-ab.log`: without PU.75 2 of 3 full runs failed,
with PU.75 1 of 3 - so PU.75 neither causes nor fixes it; filed as RV.306).

### Item 5 - tests that would fail: **MET** (with a note on M1)

- **M2** has a test that pins the batch bitwise: `batchedEqualsSequential`
  (`PumpSegmentsModelTests.swift:100-118`) asserts batched equals sequential bit-for-bit
  (`bitPattern`), and the batched average equals the sequential-order sum. The crop-drop mutation's
  red output is captured verbatim in `PU.75.last.md` - the averaged comparison at
  `PumpSegmentsModelTests.swift:116:9` fails with `[0.789…] vs [0.983…]`, and restoring the loop
  passed 1/1. This is the note's F1/F2 falsifier (a dropped crop or reordered sum is caught).
- **M1** has `lazyTextLinePass` (`PumpDisplayCaptureTests.swift:173-192`): a fast frame reports
  `textLines == -1`, a slow frame `>= 0` and `!= -1`. No mutation red output for M1 is in the gate
  evidence (the row claims only the batch mutation). But the test is not vacuous: reverting M1
  (moving `textLineCount` back above `fastVerdict`) would make the fast frame report a real count
  and redden `:183`. I record the missing M1 mutation as a note, not a block - the behaviour the
  test pins (the sentinel) is directly asserted on a real fixture.

### Item 6 - docs reconciled: **PARTIAL**

- `docs/LOGGING.md` updated: `capture.classify`'s `textLines` field now reads "Vision text lines on
  the slow path; `-1` on the fast path, which decides before the text-line pass runs" (diff at
  LOGGING.md:292). The `-1` count is loggable (hard rule 12 - counts are loggable). **MET.**
- `docs/TASKS.md`: the PU.75 row is `[~]` with the M1/M2 SHIPPED text and the three-item "Left
  open, and why". RV.306 filed with its own row. **MET.**
- `docs/ERRORS.md` and `docs/JOURNEYS.md` J4/F2: nothing user-visible changed (a speed change, no
  error surface, no journey), so no update is owed. **MET.**
- Comments: the new code comments are present-tense, no task ids, current-truth ("The text-line pass
  is measured only when the fast path abstains", :205-206; the sentinel's reason, :72-75; the batch
  "Output order follows input order", :56-57; the verifier's "each receives the same single crop it
  did before", :519-520). Test comments use `M1:`/`M2:` - the note's method labels, consistent with
  the harness family's existing `PU.nn` print labels, not task-id-in-code drift. **MET.**
- **`docs/EXTRACTION.md` decision 10 - MISSING.** The note's A1 says the diagnostics-contract change
  "the docs (`docs/EXTRACTION.md` decision 10 PU.63 text, `docs/LOGGING.md` field list if it names
  the field) must record in the same change." The builder updated `docs/LOGGING.md` but not
  `docs/EXTRACTION.md`. The PU.38 decision text still states the fast-path decision is "a detector
  pass plus a text-line count (~50-80 ms in Release on the 12 MP stills)"
  (`docs/EXTRACTION.md:981-982`), and frames the fast path as "under the Vision text-line ceiling
  (`textLines ≤ 30`)" (:973-974). After PU.75 the fast path runs *neither* the count nor the
  ceiling check - `textLineCount` is simply not called on a fast-decided frame, and the decision is
  a detector pass alone. Decision 10 needs a PU.75 amendment (or the PU.38 text corrected in place,
  matching how PU.63 amended it at :985) recording that the fast path no longer measures text lines
  and that `textLines = -1` on fast frames.

### Item 7 - everything the row promised, sentence by sentence: **MET**

| Checks-cell sentence | Verdict | Evidence |
|---|---|---|
| "Lazy text-line pass" | **MET, shipped** | M1 in `decideAt`; `appDecide` 78.5 -> 51 ms; identity 123/123, 47/47. |
| "batched predictions" | **MET, shipped** | M2 in `PumpSegmentsModel`/`PumpReader`; bitwise test + mutation red. |
| "vImage warps" | **open, honestly** | Not shipped; note §0.2/A4 measured it resamples differently and none is projective, so A4/A5 default-refuse it. Named in "Left open". |
| "Release timings on the Mac AND on a device before/after" | **Mac MET; device open** | Mac medians in the row; device named "Left open" (Capture Lab on the owner's phone). |
| "the detector-size half is a spike report only" | **open, honestly** | Note §5.4 measured it (no working path); named "Left open". |

The `[~]` marker with "M1 + M2 SHIPPED" and a three-item "Left open, and why" is honest: two of the
Checks cell's six named deliverables are shipped and measured, and the other four (vImage, the
device half of the timing pair, and the spike) are left open with the note's own reasons - none is
quietly dropped, and the two that the note's fence actively *forbids* without the owner (A4/A5 for
vImage, §5.4 for the spike) are exactly the ones left open. This matches how PU.65 is marked `[~]`
with "Built" + "Open before the app turns it on".

## Row-specific checks

### Batching preserves the average's summation order - **MET**

`PumpReader.averaged` (:579-588) sums `for p in probabilities { for i in 0..<8 { sum[i] += p[i] } }`
- crop-outer, segment-inner, identical to the retired per-crop loop, and `probabilities(cells:)`
returns outputs in input order (:70-74). The verifier's margin mean uses `margins.reduce(0, +)` over
`probabilities.map { …margin }` - same order as before (:524-525). `batchedEqualsSequential`
asserts the average equals the sequential-order reference bit-for-bit (`PumpSegmentsModelTests.swift:112-117`).

### Every consumer of `Detection.textLines` tolerates `-1` - **PARTIAL**

The note's list, checked:

| Consumer | Tolerates `-1`? | Evidence |
|---|---|---|
| Logging (`LogEvents.swift:575-581` -> `CaptureClassify`) | yes | stores an `Int`; `-1` is a count, loggable (hard rule 12); documented in `docs/LOGGING.md`. |
| `CapturePipeline.swift:67` | yes | passes `detection.textLines` straight into the log. |
| `CaptureLabRunner.swift:153` | yes | stores it into `Score.textLines` -> run.json; a lab column, no gate. |
| `TraceServe.swift:187` (detectionJSON) and `:103` (attemptJSON) | yes | JSON `Int`/`NSNull`, no consumer asserts on it. |
| `PumpReadTool/main.swift:342` (appDecision) | yes at the emitter | writes `-1` into `reply.appDecision`. |
| `tools/pump-annotate/pipeline.js:674` (trace view) | yes | fixed in the diff: `d.textLines === -1` -> "not measured – the fast path decided first". |
| `PumpDisplayCaptureTests.swift:72,:88` | yes | prints only. |

**The one consumer that does not:** `tools/pump-annotate/index.html:2150`, the compare view's
`decisionHtml`. It renders `reply.appDecision` (fed by `main.swift:342`, i.e. `Detection.textLines`)
and runs `test(d.textLines <= (L.maximumTextLines ?? 30), …)`. On a fast-decided frame
`d.textLines === -1`, so `-1 <= 30` passes and the compare view prints `text lines -1 ≤ 30 ✓` - it
reports a text-line check as *passed* when the pass never ran. `pipeline.js` (the trace view) was
fixed to say "not measured"; `index.html` (the compare view) was not. This is the same contract
change through a second door, and the note's consumer list ("verified by search") missed it because
the note stopped at the emitter (`main.swift:342`) rather than following `appDecision.textLines` to
the JS that reads it. The diff under review does not touch `index.html`.

### The `[~]` verdict is honest against the Checks cell and A4/A5 - **yes**

Covered under item 7: the two shipped changes are measured with identity; the four open items are
the ones the note's fence (A4/A5, §5.4) or the physical dependency (the owner's phone) requires to
stay open, and each is named with its reason. The row does not claim a full delivery.

## The gate evidence, reconciled with what I observed

`pu75-gate-2.log`: `swift build` exit 0 (:3), `swiftlint lint` exit 0 (:2291), `xcodegen generate`
exit 0 (:2296), app-target Debug build exit 0 (:2985), `swift test` exit 1 (:8464). The red is five
issues: three `SyncWriteTriggerTests` + one `SyncWriteTriggerTests` expectation (RV.203,
machine-load, standing fence) and one `CaptureOrientationTests` `e5rtError` (`:8245-8246`, RV.306).
Both are named pre-existing reds, not PU.75's. The gate stopped at `swift test`, so its app-target
unit-bundle step never ran.

**The app-target bundle** - I judged a re-run **not needed**, and did not run it. Reasons: (a) the
gate's app-target Debug build (exit 0, `pu75-gate-2.log:2985`) already compiled the app target
against the changed `TankbookCore`, so package-green/app-green on the compile is proven; (b) the two
app-target consumers are trivial `Int` pass-throughs with no `-1`-sensitive logic
(`CapturePipeline.swift:67`, `CaptureLabRunner.swift:153`); (c) the app-target tests that touch the
pump path do not exercise the change - `PreviewGuidanceTests` drives
`CaptureGuidanceState.classify(rows:)` and `rescuedRows` (no `textLines`), `CaptureLabTests` uses
its own `Score.textLines` literal (5 and 0, serialization only), and
`CapturePipelineCompositionTests` composes reader fields + rules arm with no `Detection.textLines`.
The builder separately reported the app unit bundle 301/301 in `PU.75.last.md`; the changed
behaviour is fully covered by the package suite (`pu75-identity-main.log`).

## Findings (both are what INCOMPLETE requires; neither needs a new row)

1. **`docs/EXTRACTION.md` decision 10 not updated (note A1).** `:973-974` and `:981-982` still
   describe the fast path as running/guarding on the Vision text-line count. Fix in place: amend
   decision 10 (as PU.63 did at `:985`) to record that the fast path no longer measures text lines
   and reports `textLines = -1`, and that the decision is a detector pass alone.
2. **`tools/pump-annotate/index.html:2150` does not tolerate `-1`.** The compare view's
   `decisionHtml` renders "text lines -1 ≤ 30 ✓" on fast frames. Fix in place, mirroring
   `pipeline.js:674`: when `d.textLines === -1`, show "not measured – the fast path decided first"
   (or suppress that check row on the fast path), not a passed ceiling test.

## Verdict

**INCOMPLETE.** Items 1, 2, 3, 4, 5, 7 are MET; the `[~]` partial state is honest. Item 6 is
PARTIAL (docs/EXTRACTION.md decision 10 stale, note A1 unfulfilled) and the Row-specific consumer
check is PARTIAL (index.html:2150). Both are small, in-place fixes the orchestrator can make without
a new row; after they land, re-dispatch this review (a fresh copy, same row). Nothing else blocks -
the identity is genuine (123/123, 47/47, leak 6/0), the batch mutation red is captured, and the two
full-suite reds are RV.203 and RV.306, both pre-existing and owned.
