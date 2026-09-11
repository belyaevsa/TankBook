# REVIEW-SCENARIO run: F4 - Cloud LLM fallback unavailable - 2026-09-11c

**Verdict: IMPLEMENTED**

Every stage, fallback and seam in F4 is backed by code, walked end-to-end as one user doing one thing. The one build row still naming F4 is `PJ.18` (the "unreachable hint"), which is `[v2]` and N/A per the dispatch. The quota-spent note is Pro-tier-deferred (P6.16, `docs/TASKS.md:600`). One non-blocking finding filed below: the success metric's "fallback down" abandonment is unmeasurable (same shape as `RV.225` for F3 and `RV.233` for F1). No user-facing promise is unowned.

## Ticked rows found untrue

None.

- **P6.3** (the gateway client / the timeout branch of F4, ticked) is genuinely shipped: the budget is `GatewayBudget.duration = .seconds(3)` (`ios/Sources/TankbookCore/Extraction/Gateway/GatewayBudget.swift:20`), the wait never cancels the work (`GatewayWaiter.wait`, `:52-71`), and the on-device result is on screen before the gateway ever starts (`ManualFillUpView.swift:439-447`). The PJ.47 footnote "only the timeout branch of F4 renders" was true when written; it is still true today only of PJ.18's unreachable hint, which is `[v2]` by design.
- **RV.26, RV.38, RV.45, RV.57, RV.65, RV.201** are all `[x]` and each holds against the tree (evidence in the map below).

## Promise-to-code map

| F4 text | Verdict | Evidence |
|---|---|---|
| The app never waits on the gateway to show the card; on-device results render immediately; the fallback is an enhancement pass | **MET** | The session runs after the on-device prefill is applied (`ManualFillUpView.swift:316-320` applies prefill, `:439-447` starts the gateway in the background); `GatewayScanSession.swift:8-9` states the on-device result is already on screen when the sheet opens. |
| The wait has a 3-second budget | **MET** | `GatewayBudget.duration = .seconds(3)` (`GatewayBudget.swift:20`); `GatewayWaiter.wait` races answer vs deadline and returns `.stillRunning` past it (`:52-71`). |
| At 3 s the UI stops presenting the call as something to wait for and says so, naming the next step | **MET** | `GatewayProceedNote.shouldShow(phase:)` = `phase.isInFlight` (`GatewayReadingPhase.swift:62-66`); rendered as a dismissable, non-blocking note (`ManualFillUpView.swift:146-149`, `ManualFillUpGatewayBanner.swift:19-46`), copy localized EN+RU (`Localizable.xcstrings:1909-1924`). |
| The request may finish in the background - the budget bounds the user's wait, not the work | **MET** | `.stillRunning` keeps the task and never cancels (`GatewayWaiter.wait` doc `:36-51`); `GatewayScanSession.monitor` sets `.budgetExpired` and returns without touching `work` (`:145-152`). |
| Its late answer is never applied to the open editor | **MET** | RV.57 ruling encoded: `.stillRunning` never calls `deliver` (`GatewayScanSession.swift:145-152`); `deliver` also guards `saved` (`:159-162`); `GatewaySuggestionPolicy.fillableFields` returns `[]` when saved (`GatewaySuggestionPolicy.swift:50-58`). |
| A within-budget answer still applies directly, filling blank untouched fields only | **MET** | `applyGatewayAnswer` computes `GatewaySuggestionSnapshot(touched:onDeviceResolved:saved:)` and fills only `fillableFields` (`ManualFillUpView.swift:482-528`); the policy excludes `touched` and `onDeviceResolved` (`GatewaySuggestionPolicy.swift:50-58`). |
| RV.38: once saved, a late answer lands in the inbox (bell on the tab-root header); the app asks; "leave it as it is" is the default | **MET** | `markSaved` hands the still-in-flight `work` to a strongly-held task that calls `onSavedAnswer` (`GatewayScanSession.swift:113-123`); `onSavedAnswer` → `inbox.recordLateGatewayAnswer` (`ManualFillUpView.swift:459-464`); the bell lives on the tab-root header (`TabRootHeader.swift:52,74-75`); `recommendedAction(tickedCount: 0) == .leaveAsIs` (`GatewayInboxPolicy.swift:438-440`, `InboxView.swift:246-247`). |
| RV.45 per-field ask: "yours vs the receipt", tick per field; a field that agrees is not a choice | **MET** | `FieldOffer` with `.fillsBlank` vs `.differs` (`GatewayInboxPolicy.swift:103-124`); `offer` helpers return nil on agreement (`:391-402`); the card lists offers and ticks (`InboxView.swift:157,175-188`). |
| A reading that would change nothing says so and offers no update; an agreeing late answer creates no item at all | **MET** | `shouldOffer` = `!offers.isEmpty` (`GatewayInboxPolicy.swift:132-134`); `item` returns nil when nothing would change (`:141-146`); the empty-offers card says so and offers no update (`InboxView.swift:97`), seeded by `InboxTestSeed.swift:147` ("the nothing-to-change case"). |
| The upload is compressed on device before any of this | **MET** | `GatewayRendition.jpegData` downscales to long edge 1800 px @ quality 0.9, gated by the corpus (`GatewayRendition.swift:51-74`, header `:20-25`); called before the request is built (`ManualFillUpView.swift:448`); `CorpusCompressionTests` re-scores the fixtures. |
| If fallback is unreachable: low-confidence fields stay dimmed with "check these - enhanced reading unavailable right now." | **N/A ([v2])** | `PJ.18` is open, `[v2]`, `docs/TASKS.md:747`; the brief says mark it N/A. Today the transport-error branch collapses to `.answered` (`GatewayReadingPhase.phase(after:)` returns `.answered` for non-auth errors, `:47-52`), so the on-device result stands with no hint. |
| RV.26: a stale session no longer loses the cloud reading; guest gets no gateway; `authExpired` never re-arms; 401 refreshes once and retries; refresh rejected → `authExpired` surfaces in Settings with "sign in again" | **MET** | `GatewayArming.shouldArm` checks `isAuthExpired` before `load()` (`GatewayExtractClient.swift:32-40`); `GatewayScanStarter.makeTransport` arms only when `shouldArm` (`GatewayScanSession.swift:171-194`); 401 → refresh-and-replay (`TankbookHTTPClient.swift:241-247`); rejected refresh → `SessionRefresherError.authExpired` → `.authExpired` (`GatewayExtractClient.swift:80-87`); the mark surfaces in Settings as a card with its next step (`SettingsView.swift:144-149`, `L10n.authExpiredMessage`). |
| RV.65: a dead session no longer uploads the photo twice and no longer fails silently; warn card on the Confirm sheet | **MET** | Replay happens only when the bearer actually changed (`TankbookHTTPClient.swift:181-191,207-247`); the capture surface shows the notice when the phase is `.authExpired` (`ManualFillUpView.swift:150-156`, `GatewayAuthExpiredNoticeView.swift:20-55`); Save stays reachable (comment `:16`). |
| If quota is spent: same UX plus a quiet non-blocking note in Settings, never an upsell interstitial mid-capture | **N/A (Pro tier deferred)** | The gateway is unmetered in v1 (P6.16 deferred, `docs/TASKS.md:600`; PR.22's quota reconciliation). The "never upsell" half holds structurally: 402 maps to `.tierRefused` and the phase becomes `.answered` (silent), no paywall on the capture path (`GatewayReadingPhase.phase(after:)` `:47-52`; `ManualFillUpView` has no paywall surface). The Settings `quotaFull` card is blob/sync quota, not the LLM gateway (`SettingsView.swift:549-568`). |
| Metric: capture abandonment when fallback is down is no different from baseline | **MISSING (telemetry, non-blocking)** | `capture.pipeline` carries `pipelineId, durationMs, per-field confidence, crossCheck, userCorrected` and no gateway-outcome flag (`LogEvents.swift:523-546`, `CaptureCommitLog.swift:30-43`, emitted at commit `ManualFillUpView.swift:606-610`); an abandoned capture emits nothing (same as `RV.233`). See proposed row 1. |

## Sequence trace

One user, signed in, hard crumpled receipt, the cloud reading outrunning the budget:

1. Shutter → review step → `CapturePipeline.process` runs on-device OCR and assembles a partial prefill; the card on screen is that local result. **Fact carried: the photo + the partial prefill.**
2. Confirm sheet opens; `load()` applies the prefill and only then fires `startGatewayReading` in the background (`ManualFillUpView.swift:316-320,439-447`). The gateway is armed because `GatewayArming.shouldArm` passes. **Fact carried: the on-device fields, on screen before any network.**
3. 3 s pass; `GatewayWaiter.wait` returns `.stillRunning`; the sheet shows the proceed note ("a more reliable reading may still arrive... proceed now") and stops waiting - the request keeps running (`GatewayScanSession.swift:145-152`). **Fact carried: "do not wait, proceed".**
4. The user fills the odometer and saves. `save()` writes the entry and then `gatewaySession.markSaved(entryID:)` (`ManualFillUpView.swift:622`), which hands the still-running `work` to a task that will route the answer to the inbox (`GatewayScanSession.swift:113-123`). **Fact carried: the saved entry id.**
5. The answer arrives after save. `onSavedAnswer` → `inbox.recordLateGatewayAnswer` builds an item only if it would change something (`AppInbox.swift:75-80`); the bell shows the item. **Fact carried: the per-field "yours vs the receipt" offers.**
6. The user opens the inbox, ticks the fields to take, and taps "update from the receipt" (the loud button once a tick exists, `GatewayInboxPolicy.recommendedAction`). `AppInbox.resolve` applies exactly the ticked fields and no others (`AppInbox.swift:172-210`). **Fact carried: only the ticked values land; everything else is byte-identical.**

The fact that survives every step intact is the user's own typed/saved value: no value moves under the user's cursor at any point, a within-budget answer fills only blank untouched fields, and a late answer is offered, never applied. No step loses a fact, and no step blocks on the network.

## Proposed rows (non-blocking)

**1. F4 metric instrumentation - "fallback down" is not recorded, and an abandoned capture emits nothing.**
- Deliverable: one Safe field on `capture.pipeline` from the gateway session's terminal phase (`budgetExpired` / transport-error `.answered` / `.authExpired`), so "abandonment when the fallback is down" can be compared to baseline from the diagnostics export; the abandonment half is `RV.233`'s end-event, so fold this into `RV.225`/`RV.233`'s one telemetry brief - three metrics, one seam.
- Journey stage it closes: the metric line ("capture abandonment when fallback is down: no different from baseline").
- Consequence today: the metric is unmeasurable - nothing in telemetry distinguishes a capture whose fallback was down, and an abandoned capture emits nothing at all.
- Severity: **polish** (no user-facing effect; the behaviour is correct, only the measurement is absent).
- Check: L1 - a capture committed after a seeded transport failure emits the gateway-outcome flag; a capture committed after a within-budget answer emits the opposite; assert field names, never a domain value (hard rule 12). Same fold-in pattern as `RV.225`.
- Scenario id: F4.

## Could not settle

- Whether the "quota spent" branch should be marked N/A or PARTIAL: the "no upsell mid-capture" half holds today, but only because the gateway is unmetered and 402 collapses to a silent `.answered`; the moment Pro metering ships, `PJ.18` and PR.22's quota reconciliation become the owning rows. Marked N/A because the tier itself is `[v2]` and the owner deferred it (P6.16) - the same call `docs/TASKS.md:600` records.
- Whether `PJ.18`'s `[v2]` marker will ever need to become a v1 row: its L4 seam (`GatewayCaptureUITests`) already exercises the seeded failing-transport path today (`GatewaySeedTransport.failure`), so the hint is a rendering addition over a transport seam that exists - nothing in F4's text blocks it, and it stays a `[v2]` promise.
