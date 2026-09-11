# REVIEW-SCENARIO run: F3 - No internet at the pump - 2026-09-11

**Verdict: IMPLEMENTED**

Every stage, fallback and seam in F3 is backed by code, walked end-to-end as one user doing one thing. Two non-blocking findings filed below (a telemetry gap on the metric's "instrumented locally" parenthetical, and two stale phrases in the F3 text that the shipped code has outrun). Neither is a user-facing promise, so the journey is implemented.

## Ticked rows found untrue

None.

- **PJ.19** (the only build row naming F3) is genuinely shipped and honest: the ranking is a pure core function over injected coordinates (`ios/Sources/TankbookCore/Domain/StationSuggestion.swift`), the app seam reads CoreLocation on-device (`ios/App/Sources/ConfirmManual/ForecourtLocationReader.swift:18-121`), and nothing in it touches the network. The "maps" claim in F3's own text is stale (see proposed row 2), but the row did what it said.
- **SH.3** is the owner's own launch walk, not a build row; nothing to verify against the tree.

## Promise-to-code map

| F3 text | Verdict | Evidence |
|---|---|---|
| Capture, on-device OCR, parsing, cross-check, save all work identically offline; the user should be unable to tell | **MET** | OCR is `VNRecognizeTextRequest` on-device (`ios/Sources/TankbookCore/Extraction/VisionTextRecognizer.swift:24-47`); the pipeline is Vision OCR + local QR + `ExtractionAssembler` with no network (`ios/App/Sources/Capture/CapturePipeline.swift:56-71`); cross-check is core `ExtractionCrossCheck` (`ios/Sources/TankbookCore/Extraction/CrossCheck.swift:16`); the price-band provider is "Local-only, no network" (`ios/App/Sources/Capture/AppFuelPriceBand.swift:12`); save is local. No offline surface exists on the capture/Confirm path (the offline cards live in Settings, Import, AddVehicle, Feedback). |
| Currency conversion silently defers: entry saves original amount + "rate pending" chip | **MET** | Pending card renders "≈ –" + "converts when online" (`ios/App/Sources/ConfirmManual/CurrencyConversionCard.swift:91-95,144-149`); save preserves the original pair on `.ratePending` (`ios/App/Sources/ConfirmManual/ManualFillUpCurrencySupport.swift:419-429`). |
| Converts on next connectivity | **MET** (wording loose, see proposed row 2) | S8 backfill runs after every `AppRates.refresh()` and on foreground (`ManualFillUpCurrencySupport.swift:90-118`; `ios/App/Sources/Navigation/TabRoots.swift:529`); the on-demand "Check for rates" drain is the manual door (`ManualFillUpCurrencySupport.swift:146-162`). It fires on launch/foreground/manual, not on connectivity restoration alone - F9 already states this precisely. |
| Trends momentarily exclude rate-pending rows from home-currency sums | **MET** | `LogStream.MonthTotal.Accumulator` is the shared seam; footnote is `PendingRatesFootnote` (`ios/App/Sources/Shared/PendingRatesFootnote.swift:37`); zero-summing was fixed per-surface (RV.106/112/145/147/166) and guarded by `MoneyHomeSideSumGuardTests` (RV.167). |
| Station auto-suggest from maps defers; favorites still work (local) | **MET** (better than promised) | The ranking is fully local, not a maps API: `StationSuggestion` is a pure function; location is CoreLocation GPS (`ForecourtLocationReader.swift:92-110`), no network; J4 already reconciled this ("Offline is a non-event: the ranking is local (F3)", `docs/JOURNEYS.md:124-125`); favorites are a local field with a Garage writer (PJ.55). Nothing defers because there is no network half. |
| Backup upload (queued) | **MET** | Offline/5xx returns rows to `.dirty` via `recoverStuckPushes` (`ios/Sources/TankbookCore/Sync/SyncEngine.swift:155,176,217`); `SyncOutcome.offline`/`serverUnavailable` are passive, "rows stay dirty" (S7, `SyncEngine.swift:19-28`). |
| The one visible seam: foreign entry shows "≈ – · converts when online" instead of home amount; `inkSoft` not `warn` | **MET** | `pendingGlyph = "≈ –"` (`CurrencyConversionCard.swift:99`) and `inkSoft` subtitle (`:145-147`); no warn color on the pending state. |
| Metric: offline captures complete at the same rate (instrumented locally, reported in aggregate) | **MISSING (telemetry, non-blocking)** | `capture.pipeline` carries `pipelineId, durationMs, per-field confidence, crossCheck, userCorrected` and no offline/online flag (`ios/Sources/TankbookCore/Logging/LogEvents.swift:523-546`; `ios/Sources/TankbookCore/Logging/CaptureCommitLog.swift:30-43`). The app observes connectivity (`ios/App/Sources/Network/AppPathMonitor.swift:40`, `network.path` edge) but nothing joins "this capture happened while offline". See proposed row 1. |

## Sequence trace

One user, underground garage, no signal, foreign-currency receipt:

1. Shutter -> review step -> `CapturePipeline.process` runs Vision OCR + QR + assembly fully on-device (`CapturePipeline.swift:56-71`); no await on any network. **Fact carried: the photo.**
2. Confirm sheet opens with the local prefill; cross-check runs locally. **Fact carried: the proposed fields.**
3. Foreign currency, no rate for the entry date in the bundled seed/cache -> `.ratePending`; the card shows "≈ –" + "converts when online" in `inkSoft` (`CurrencyConversionCard.swift:144-149`). **Fact carried: the foreign currency + original total.**
4. Save: `convertForSave` returns the pair unchanged on `.ratePending` (`ManualFillUpCurrencySupport.swift:426-427`), so the original amount is exact and never faked. **Fact carried: original amount, rate-pending marker.**
5. Trends/Home reduce through the accumulator and exclude the pending row from home sums, footnoted (`PendingRatesFootnote`). **Fact carried: "not yet in home-currency totals".**
6. Station suggestion runs locally (CoreLocation + favorites + last-used); no maps call. **Fact carried: station.**
7. Sync runs, sees no host, marks the entry dirty (S7) - backup queued, nothing lost (`SyncEngine.swift:217`).
8. Later foreground -> `AppRates.refresh()` -> S8 backfill fills the pending row at the entry's own date (hard rule 3), silently; the footnote drains. **Fact resolved: home amount.**

The fact that survives every step intact is the original amount; the only thing deferred (the home conversion) is carried as a rate-pending marker with a named next step, never a zero and never a block. No step loses a fact, and no step requires a network round trip.

## Proposed rows (non-blocking)

**1. F3 metric instrumentation - offline vs online capture is not recorded.**
- Deliverable: thread the current path status (from `AppPathMonitor`'s last status, or a reachability read at commit) into the `capture.pipeline` event as one Safe field, so "offline captures complete at the same rate as online ones" can be measured from the diagnostics export in aggregate.
- Journey stage it closes: the metric line ("instrumented locally, reported in aggregate").
- Consequence today: the metric is unmeasurable as written - nothing distinguishes an offline capture from an online one in telemetry.
- Severity: **polish** (no user-facing effect; the behavior is correct, only the measurement is absent).
- Check: L1 - a capture committed under a seeded/offline path state emits the flag, and a capture under a satisfied path emits the opposite; assert the field name and value, not a domain value.
- Scenario id: F3.

**2. F3 wording reconciliation - two phrases the shipped code has outrun.**
- Deliverable: (a) change "station auto-suggest from maps" to reflect that the ranking is fully local (CoreLocation + favorites), so F3's deferral list stops naming a network maps feature that was never built (PJ.19 built a local ranking instead); (b) tighten "converts on next connectivity" to match F9's precise mechanism ("converts on the next rate refresh - launch or foreground - or on demand").
- Journey stage it closes: the "What silently defers" bullet and its deferral consequence.
- Consequence today: none for the user (the app does more offline than the text promises); the risk is a future reader re-adding a network maps suggestion because the doc still names one.
- Severity: **polish** (doc-only).
- Check: doc-only; no code/test gate.
- Scenario id: F3.

## Could not settle

- Whether the F3 metric should be filed as a build row at all: metrics across JOURNEYS.md are aspirational success metrics, and the status-line rule defines "what the user is promised" as stages and fallbacks, not metrics. Filed as a polish row rather than treating it as a blocking gap; the product owner's call whether "instrumented locally" is a commitment that needs the flag.
- The "converts on next connectivity" nuance (refresh-triggered, not connectivity-triggered) is F9's domain and is already stated precisely there; I did not treat it as a defect, only flagged the F3 phrasing.
