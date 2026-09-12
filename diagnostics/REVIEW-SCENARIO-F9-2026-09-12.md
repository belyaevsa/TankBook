# REVIEW-SCENARIO run: F9 – Currency rate unavailable for that date

- **Verdict:** IMPLEMENTED
- **Run id:** REVIEW-SCENARIO-F9-2026-09-12
- **Date:** 2026-09-12
- **Reviewed against:** `docs/JOURNEYS.md` F9 (lines 726–733), `docs/ERRORS.md` F9 rows, `docs/SCHEMA.md` → Exchange rates

## Ticked rows found to be untrue

None. Each closed row named in the context was walked to code:

| Row | Claim | Code evidence | Verdict |
|---|---|---|---|
| RV.158 | drain stops at server's `coverageFloor`, paces, dedupes | `RateStore.swift:378-393` (floor skip), `:212` `spanChunkPacing`, `:336-359` single-flight slot | true |
| RV.138 | carry-forward bounded horizon | `backend/.../RateOptions.cs:36` `CarryForwardHorizonDays = 400`, `RatesJobService.cs:102-116` | true |
| RV.135 | ECB historical feed | `backend/.../EcbRateFeed.cs:44-45` (`eurofxref-hist.xml`) | true |
| RV.139 | refresh records each branch | `RateStore.swift:234-282` (`noFetcher`/`deferred`/`joined`/`attempted`) | true |
| RV.140/RV.152 | rehome / convert-the-log | `MoneyBackfillService.swift:237-322` | true |
| RV.254 `[v1.0.x]` | `spanDays` log field | deferred; N/A for v1, cited not re-filed | N/A |

## Promise-to-code map

| # | Journey promise (F9 text) | Status | Evidence |
|---|---|---|---|
| 1 | Entry always saves with the original amount; conversion is metadata, never a save-blocker | MET | `ManualFillUpCurrencySupport.swift:419-429` `convertForSave` returns `money` unchanged on `.ratePending`; `CurrencyConversionCard.swift:20-21` "an option that never gates Save" |
| 2a | Rate arrives later → conversion fills in (PJ.8 S8 backfill, no DEBUG flag) | MET | `TabRoots.swift:529` (`runAutomaticPass` step `.rates` → `AppRates.refresh()`), `:340,361` (`scenePhase == .active` trigger), `ManualFillUpCurrencySupport.swift:95-106` (`refresh` → `store.refresh()` + `runBackfill()`), `MoneyBackfillService.swift:326-338` (fill-blanks-only at entry's own date) |
| 2b | Rate *never* exists → entry shows original currency + footnote count; user may set a manual rate per entry | MET | `HomeSections+LogStream.swift:61-66` and `TrendsView.swift:97-111` (`PendingRatesFootnote`); `PendingRatesFootnote.swift:53-87` (count + "Check for rates"); `CurrencyConversionCard.swift:181-188` (manual-rate row shown on `.ratePending`); `EditEntryView.swift:564-565` (manual rate reachable on edit) |
| 3 | Never apply today's rate to last month's fill silently | MET | `MoneyBackfillService.swift:329-333` (`outcome` looks up `entry.date`); `:313-322` (`convertedPair` uses `entry.date`); `ManualFillUpCurrencySupport.swift:385-388` (snapshot on form `date`) |
| – | Metric: entries stuck >7 days without a rate <0.5% | N/A | success metric (observability), not a behaviour promise |

## The brief's specific question: is the user TOLD when a date is below the floor, or left pending forever?

**Told.** The dead-end line `"No rate exists for these dates. Add a manual rate to each entry."` (`L10n+RV111.swift:7-14`) fires for any rate-pending row dated before the rolling pack window once a demand pass reached the provider:

- `demandDrain` → `fetchSpan` (`MoneyBackfillService.swift:126-127`). The RV.158 floor skip (`RateStore.swift:378-393`) jumps past below-floor chunks but still sets `mergedAny = true` on the first (empty) answer it actually fetched (`RateStore.swift:376`), so `reachedProvider` stays true even when the entire span is below the floor and the walk breaks (`RateStore.swift:388`).
- `demandDrain` then computes `hasUnresolvableRows` from `reachedProvider && stillPending>0 && hasRowsBeforeRollingWindow` (`MoneyBackfillService.swift:133-143`, `:166-174`).
- The footnote flips to the dead-end copy (`ManualFillUpCurrencySupport.swift:154` sets `demandPassLeftUnresolvableRows`; `PendingRatesFootnote.showsDeadEnd`, `:118-134`, renders it on both Home and Trends).

Every below-floor date (floor is `1999-01-04` from `EcbRateFeed.cs:85-86`; CIS/NBK state none, `CisRateFeed.cs:100`, `NbkRateFeed.cs:57`) is also before the 400-day rolling window, so the "below the floor" case is always covered by the "before the rolling window" dead-end test. A below-floor row therefore ends in the manual-rate next step, never an indefinite "Check for rates".

## Sequence trace (one user, one foreign entry whose date no feed serves)

1. Capture/import a foreign-currency entry → Save calls `convertForSave` (`ManualFillUpCurrencySupport.swift:419-429`), which returns the money pair unchanged when no rate exists → saved rate-pending (original amount exact, `homeAmount` nil). Save never blocks.
2. Home and Trends render "N entries pending rates" + "Check for rates" (`HomeSections+LogStream.swift:61-66`, `TrendsView.swift:97-111`).
3. Automatic path: launch/foreground `runAutomaticPass` → `AppRates.refresh()` → rolling pack (last 400 days) + S8 backfill fills only rows inside the window (`MoneyBackfillService.swift:326-338`). Pre-window rows stay pending.
4. User taps "Check for rates" → `drainPendingRows` → `demandDrain` → `fetchSpan` walks the pending span (skipping below-floor chunks per RV.158) → `backfill`.
5. Still-pending row dated before the rolling window → `hasUnresolvableRows` true → footnote flips to the dead-end line naming the manual rate (`MoneyBackfillService.swift:133-143` → `PendingRatesFootnote.showsDeadEnd`).
6. User edits the entry → conversion card's manual-rate row (`CurrencyConversionCard.swift:181-188`) → `Money.applyingManualRate` at the entry's own date.

**Fact carried end to end:** the entry's `date` (rateDate = entry date, never today) is honoured at every conversion site (`MoneyBackfillService.swift:329-333`, `:313-322`; `ManualFillUpCurrencySupport.swift:385-388`, `:406-408`, `:423-424`). No step in the chain substitutes today's or a neighbour day's rate.

## Proposed rows

None. Every F9 promise is MET and every deferred row (`RV.254 [v1.0.x]`) is out of v1 scope.

## Could not settle / non-blocking observations

- **A code comment overstates what its own function does** (`PendingRatesFootnote.swift:124`): the comment claims *"a row that entered the log afterwards (and was never demanded) keeps the check affordance"*, but `showsDeadEnd` (`:126-134`) returns the dead-end line for *any* pending pre-window row once `demandPassLeftUnresolvableRows` is set – it does not distinguish "entered afterwards". The flag is cleared only by `.nothingPending` (`ManualFillUpCurrencySupport.swift:150-151`) or an import commit (`:228`), never by the automatic S8 backfill or by a manually-typed pre-window foreign entry. Consequence: after one dead-end, a newly *hand-typed* pre-window foreign entry shows "No rate exists … add a manual rate" instead of "Check for rates". Minor (polish, ERRORS.md-level footnote copy, not the F9 journey text); the manual-rate next step is still correct, so nothing the journey promises is broken. Not filed as a row because the dead-end line remains honest for a pre-window date.
