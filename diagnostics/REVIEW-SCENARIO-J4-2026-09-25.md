# REVIEW-SCENARIO J4 · No receipt – pump display photo · 2026-09-25

Walked by the orchestrator (standing instruction 2026-09-12), read-only, on request after PU.86,
PU.87 and PU.88 landed (`884500ca`, `4f836a6a`, `aa9e54d8`). Rows naming J4: 89, 12 open.
Brief: `agents/briefs/REVIEW-SCENARIO-J4-2026-09-25.md`.

## Verdict

**NOT IMPLEMENTED.** The chain from shutter to saved entry exists, is reachable in every build and
now runs the new locator (RowSeg) end to end, preview included. What is missing is the same as on
2026-09-20 plus one new thing: the journey's own bar (*"as reliable as J3 or not exist"*) is met by
framing, not by reading - the live path commits 62 of 183 heldout cells, 21 of 68 photos fully
right; **both findings the previous walk proposed were never filed** (five days, no row); and the
journey's two numbers (*"~95% gate"*, *"≥95% on the confirm screen"*) no longer match the gate the
code enforces (0.99 precision, 0.60 coverage).

## Ticked rows found to be untrue

None. PU.86, PU.87, PU.88 hold at their cited lines (below). Two ticked-adjacent notes:

- **PU.87 shipped without running the pump UI suites.** `scripts/gate.sh` runs the unit bundles
  only; `CaptureUITests.testPumpCaptureBelowTheGatePrefillsWithTheAlphaNotice`,
  `testAPumpPairWhoseShownPriceDiffersCarriesTheCautionNotice` and
  `CaptureGuidanceUITests.testPumpFrameShowsDisplayInView` / `testReceiptFrameKeepsThePlainCaption`
  exercise exactly the locator PU.87 replaced and have not run against RowSeg. Not untrue - unverified.
- **`PumpPhotoGate`'s composite constants were not re-measured after PU.86/87/88.**
  `allowsPumpPhoto` is decided by `measuredCommitted` / `measuredNumericTotal` (56 / 910,
  `ios/Sources/TankbookCore/Config/PumpPhotoGate.swift:48,64,138-139`), which only the L5 accuracy
  suites assert, and those skip on macOS 27 (`.visionMeasuredRuntimeOnly`). The reader's own
  constants moved (62 / 61 / 183, `:86-96`); the number the gate decides on did not. PU.61 `[~]` and
  PU.6 own it.

## Promise-to-code map

| promise (journey text) | status | where |
|---|---|---|
| **Preview:** the row detector runs on live preview frames | MET | `ios/App/Sources/Capture/PreviewGuidance.swift:155-159` (pixel buffer), `:146-152` (simulator test frame), throttled `:119`; reader = `CapturePipeline.pumpReader` (RowSeg), `CameraCapture.swift:153`; debounced 3 frames `PreviewGuidance.swift:40` |
| *Display in view* with rows outlined in the fuel token; *Move closer* with a 2× tap where the device zooms; *Tilt to show the whole display* | MET | states `PreviewGuidance.swift:12-33` (rules are `PumpDisplayCapture.fastVerdict` / `passesSize`, no second copy); copy `CaptureGuidanceCaption.swift:62,75,78,80`, zoom affordance in `action` not taillight `:49-69`; EN + RU in `Localizable.xcstrings` |
| the hint never gates: the shutter fires in every state, typing stays the peer door | MET | `CaptureGuidanceUITests.swift:53,55` (shutter enabled, Type it hittable while the hint shows) - **not re-run since PU.87** |
| a receipt frame raises no hint | MET | size rule alone keeps a receipt in `searching`/`tooSmall` `PreviewGuidance.swift:24-27`; `CaptureGuidanceUITests.swift:59-71` - **not re-run since PU.87** |
| guidance runs in the fill-up scan mode | MET | `CaptureGuidanceCaption.swift:13` (`mode == .fillUpAuto`), the default mode `CaptureView.swift:47` |
| → first-use tip "no receipt? Shoot the pump" | **MISSING, unowned** | searched `Shoot the pump`, `no receipt` in `ios/App/Sources`, `Localizable.xcstrings`, `docs/TASKS.md`, `docs/TASKS-DONE.md`: nothing. Proposed 2026-09-20 as PJ.new-a, **never filed**. The caption withholds the pump claim below the gate (`CaptureView.swift:531-538`), so today nothing tells a user the pump is a target |
| the reader reads the three numbers, the arithmetic assigns them | MET | locate: `PumpRowDetector` segmenter backend, RowSeg loaded `CapturePipeline.swift:30-32`; roles: `PumpRowAssignment.assign` with the tilt undone (PU.88); law: `PumpReadingLaw.resolve`, repair budget `repairWindow` (PU.86) |
| ⚠ "the spike's ~95% gate applies before this ships" | **PARTIAL - the text is stale** | the gate the code enforces is precision ≥ 0.99 and coverage ≥ 0.60 (`PumpPhotoGate.swift:113,123,138-139`), not ~95 %; and it is decided on the composite constants, not the reader's (above) |
| station auto-suggested from location + favourites | MET | `ios/Sources/TankbookCore/Domain/StationSuggestion.swift`; ask `ConfirmManual/ForecourtLocationReader.swift:85`; favourite `StationSettings/StationSettingsView.swift:32` |
| a frame is a display by structure, never by strings | MET | `PumpDisplayCapture.classify` `ios/Sources/TankbookCore/Extraction/PumpReader/PumpDisplayCapture.swift:330-340`; logged shape-only `CaptureClassify` `Logging/LogEvents.swift:569-586` |
| the same classification on capture, attach, re-attach, replace | MET | `CapturePipeline.process` call sites: `CaptureFillUpScan.swift:27`, `ManualFillUpReceiptSave.swift:72`, `EditEntryView.swift:676`, `AttachmentViewerActions.swift:108`; `CaptureExpenseScan.swift:131` passes `.receipt` by design |
| display → reader → Confirm as `.pumpPhoto`, committed fields pre-filled | MET | `CapturePipeline.swift:59-65,98-102` |
| decision 11: a pair commits within 5 %; a shown price that differs raises an amber notice naming both (PJ.500) | MET | `PumpReadingCautionNotice.swift` (warn token, words carry the meaning), shown `ManualFillUpView.swift:168`, set `CapturePipeline.swift:100`; `CaptureUITests.testAPumpPairWhoseShownPriceDiffersCarriesTheCautionNotice` - **not re-run since PU.87** |
| a refused field is filled from the receipt parser where it read one (PU.62) | MET | `CapturePipeline.composed` `:112-117`; a cautioned pair's price is left empty `:116` |
| a sideways display is read upright: when the first read commits nothing, the orientation the detector prefers | MET | seed first, search on refusal `PumpDisplayCapture.swift:338-354`; the 180-degree tie broken by read margin (PU.87, `PumpReader+Orientation.swift`) |
| below the gate the sheet says so (alpha notice text) | MET | `ManualFillUpView.swift:167`, `pumpAlpha` from `PumpPhotoGate.allowsPumpPhoto` `CapturePipeline.swift:101-102`; EN + RU in `Localizable.xcstrings:10631` |
| typing stays the peer door | MET | same Confirm form; `captureTypeItButton` |
| a pump photo never runs the receipt parser in silence | MET | `CapturePipeline.swift:59-65`: a classified display takes the reader branch and carries the alpha notice |
| the kind on the attachment (`pump-reader v1`) | MET | `ScannedSavePlan.swift:85`; writers `ManualFillUpReceiptSave.swift:125,272`, `EditEntryView+FillReceiptSave.swift:49`, `EditEntryView+NonFillSave.swift:125`, `AttachmentViewerActions.swift:118` |
| the entry carries `.pumpPhoto` | MET at the write; **PARTIAL after it** | no screen reads it back: `.pumpPhoto` in `ios/App/Sources` appears only in writers and comments (`CapturePipeline.swift:37`, `ConfirmPrefill.swift:40`). Proposed 2026-09-20 as PJ.new-b, **never filed** |
| the gateway asked with `kind: "pump"`, the ledger records it | MET | `ManualFillUpView.swift:454` |
| the locator is automatic; no tap-to-frame | MET | decision 8; RowSeg first, the Vision and classical fallback behind it (`PumpReader.candidates(for:)`) |
| station brand / name, Change brand, the picker's order | MET | `ManualFillUpStationRow.swift:155`, `StationBrandPickerSheet.swift:40`, `StationSettingsView.swift:81` |
| the creation door, favourite, Remove location, the save stamp | MET | `StationsListView.swift:71,97`, `StationSettingsView.swift:32,141` (walked implemented in J3's and PJ.19's reviews; spot-checked only) |
| "as reliable as J3 or not exist" | **MISSING** | heldout live path 62 committed / 61 correct of 183 cells, 21 of 68 photos fully right (`PumpPhotoGate.swift:86-96`, `PumpReaderPipelineTests.livePath`); the build ships it as alpha (decision 7). PU.6 owns the verdict; PU.89 is the next reading lever |
| success metric: pump-photo share ≥ 15 % of captures | **MISSING - no measurement path** | `capture.classify` is logged on the device only (`LogEvents.swift:569`), and the product has no telemetry by design; the ledger's `kind` sees only captures that reach the cloud gateway. Nothing can report the share |
| success metric: extraction accuracy ≥ 95 % on the confirm screen | **PARTIAL** | the corpus measures the reader (61 / 62 committed at 0.984, 0.339 coverage); nothing measures what the Confirm screen shows after the rules-arm fill (`CapturePipeline.composed`) outside the L5 suites, which skip on macOS 27 |

## Sequence trace - one user, one fill, no receipt

1. Opens capture, points at the pump. **No tip says the pump is a target** (unowned, above).
2. The preview runs RowSeg every 100 ms; *Display in view* when two rows stack. Device cost never
   measured (RowSeg is 26.5-29.8 ms per frame on the Mac simulator, `PumpLocatorTimingTests`;
   RV.295 / the Capture Lab own the phone number).
3. Shoots. `CapturePipeline.process` → `PumpDisplayCapture.classify`: RowSeg rows, the tilt-aware
   assignment, the law with the repair budget. **Carried.**
4. A field the law refused is filled by the rules arm (`composed`), which reads the same glare the
   law refused. PU.86 moved more fields onto this path (a repair over budget now abstains), and the
   composite that decides what the user sees is measured only on macOS 26. **Carried, unmeasured
   here** - the alpha notice ("check every field") is what covers it.
5. Confirm opens as `.pumpPhoto`, alpha notice, caution notice where a pair's prices differ.
   Types the rest, picks the suggested station, saves. Attachment `pump-reader v1`, entry
   `.pumpPhoto`, gateway `kind: pump`. **Carried.**
6. Later, in the Log or the entry: nothing shows it came from a pump display. **Stored, never
   shown** - unchanged since 2026-09-20.

## Proposed rows

| row | deliverable | stage | consequence today | severity | check | scenario |
|---|---|---|---|---|---|---|
| PJ.new-a **[v1.1]** (re-proposed; filed nowhere since 2026-09-20) | The first-use tip "no receipt? Shoot the pump" - once, on the capture screen, while the pump path is offered (gate on or alpha), EN + RU | 1 | a user who skipped the receipt is never told the pump is a target | gap | L4 `CaptureUITests`: shown on first capture, gone on the second; screenshots EN/RU | J4 |
| PJ.new-b (re-proposed) | A "read from the pump display" mark where a `.pumpPhoto` entry lives (Log row / entry header), and the attachment's `pipeline` in the viewer's detail | 6 | the kind is written and read by nothing; F2's "double-check this one" has no handle | polish (gap once the gate turns on) | L1 on the row model; L4 on the Log row | J4, F2 |
| new | Re-run the pump UI suites against RowSeg: `CaptureUITests` (the two pump tests) and `CaptureGuidanceUITests`, signed, each bundle on its own | 2, 5 | PU.87 changed the locator these tests drive; they last passed on DigitRows | gap (verification) | the four named tests green, counts read | J4 |
| new | Reconcile J4's numbers with the enforced gate: the journey says "~95% gate" and "≥95% on the confirm screen"; the code enforces 0.99 precision / 0.60 coverage. The owner picks which is the promise; the journey or `PumpPhotoGate` follows | 3 | the specification and the gate disagree on what "ships" means | gap (doc) | `docs/JOURNEYS.md` J4 and `PumpPhotoGate.swift:113,123` say the same numbers | J4 |
| new (owner's call) | The pump-photo-share metric (≥ 15 %) has no measurement path: decide how it is measured (a count in the diagnostics export the owner reads, the ledger's `kind` for cloud captures only, or a store-side proxy) or drop it from J4 | metric | J4's success metric cannot be evaluated | gap | the metric names its source in J4 | J4 |
| (existing) PU.6 / PU.61 | Re-measure `PumpPhotoGate`'s composite after PU.86/87/88 on the measured runtime (macOS 26 / CI) - the gate decides on numbers that predate the new locator | 3 | `allowsPumpPhoto` may be stale either way | gap | `AccuracyRatchetTests` on macOS 26 | J4 |

Nothing else to file: RV.295 owns device timing, RV.289/RV.290 the cloud pump prompt, PU.89 the
next reading lever, PU.59 the held pair tier.

## Not settled

- **PU.49 ("a tilted display gets no rows") may be closeable**: RowSeg returns oriented quads
  (PU.87) and assignment undoes the tilt (PU.88). Settled by re-running PU.49's named stills
  through the live path.
- **Device cost of the preview**: RowSeg every 100 ms on an iPhone 12 - settled by the Capture
  Lab's timing (SH.7 beta) or RV.295.
- **Whether PU.86's newly refused fields are filled right by the rules arm**: settled by the L5
  composite on macOS 26 (CI), per-field.
