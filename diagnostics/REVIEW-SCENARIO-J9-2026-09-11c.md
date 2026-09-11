# REVIEW-SCENARIO run: J9 – 2026-09-11c (first walk)

- **Scenario:** `J9` (`docs/JOURNEYS.md`)
- **Run id:** REVIEW-SCENARIO-J9-2026-09-11c
- **Context:** First walk. PJ.32 is `[v1.x]` and not blocking. P6.1 (engine + card + dismiss-with-reason) is the closed row behind the surface; RV.121 (drop the "likely causes" line) is the closed row behind "never a guessed cause".

## Verdict

**NOT IMPLEMENTED** – every visible step of the loop works and is L1/L4-tested, but "dismiss teaches the model" is only half-realised: the reason is collected and persisted, yet nothing reads it. `AnomalyDismissal.reason` is dead data with no consuming code and no owning row, which is the "comment naming behaviour with no call site" shape this review exists to catch.

## Ticked rows found to be untrue

None. P6.1 and RV.121 are ticked and accurate against the tree: the engine, the warn-amber card, the evidence chart, the dismiss sheet and the "no guessed cause" removal all exist where those rows claim.

## Promise-to-code map

| Journey promise (J9) | Status | Citation |
|---|---|---|
| Trigger: app-detected consumption drift ("+12% over 3 months") | MET | `AnomalyEngine.detect` `AnomalyEngine.swift:206-251`; `minimumRelativeDrift = 0.12` `:200`; `rollingWindowDays = 90` `:157` |
| gentle `warn`-amber card in the Log | MET | `AnomalyInsightCard` `AnomalyInsightCard.swift:28-87` (warn fill `:56`); inline in the signed-in full layout `HomeView.swift:254-262` |
| never a push alarm | MET | act schedules no notification `HomeView.swift:298-299`; no anomaly-notification toggle exists, the anomalies preference is decoder-only `SchemaFieldWriterGuardTests.swift:36-39` |
| tap explains the evidence (chart of the drift) | MET | tap toggles `isExpanded` `AnomalyInsightCard.swift:93-127`; rolling-vs-baseline chart `:151-167` |
| what it costs per month at the driver's own recent prices | MET | `AnomalyInsight.monthlyCostDelta` `AnomalyInsight.swift:68-87` → `AnomalyEngine.monthlyCostDelta` `AnomalyEngine.swift:265-284`, priced at `HomeStats.unitPrice` `HomeStats.swift:254-261`; money line `AnomalyInsightCard.swift:134-143` |
| never a guessed cause | MET | no cause line anywhere; RV.121's removal pinned by test `AnomalyInsightUITests.swift:298-355` |
| dismiss ("it's winter") teaches the model | **PARTIAL** | reason collected (preset + custom) `AnomalyInsightCard.swift:288-377` and persisted `AnomalyInsightStore.swift:34-40`; the cause is suppressed `AnomalyEngine.swift:238`; **the reason itself is never read** – the only consumer of a dismissal is the cause-equality check `:238`, and no code reads `.reason` |
| act → creates a service reminder | MET | `actOnAnomaly` `HomeView.swift:300-316`; the `.custom` reminder completes onto the service path `ReminderCompletion.entryKind` `ReminderCompletion.swift:45-51` |
| thresholds conservative | MET | 0.12 derived from "1.5 sigma of the measured year-over-year spread" `AnomalyEngine.swift:188-200` |
| seasonality-aware | MET | 365-day-lagged baseline, same window one year earlier `AnomalyEngine.swift:172`, `:213-224` |
| always dismissible with a reason | MET | both actions always present `AnomalyInsightCard.swift:195-221`; sheet offers preset + free text `:288-377` |
| success metric ≥70% acted-or-dismissed | N/A | metric, not code |

## Sequence trace (one user, the Volvo, consumption drifts)

1. A car with a full prior year of fills, consumption up 12%+ and still elevated this month → `AnomalyEngine.detect` returns a verdict (`AnomalyEngine.swift:206-251`).
2. The card renders inline in the Log, below the vitals, above the recent entries (`HomeView.swift:254-262`). Reachable in Release: the only `#if DEBUG` block is a screenshot hook, not the card's existence (`AnomalyInsightCard.swift:64-81`).
3. Tap → evidence expands: chart (rolling vs baseline) + money line + the two buttons (`AnomalyInsightCard.swift:131-221`).
4. **Act** → `actOnAnomaly` creates the reminder ("Check fuel consumption", `.custom`, due today) and records a dismissal with `reason: nil` (`HomeView.swift:300-316`); `noteEntryChanged` reloads and the card leaves (`:322-326`).
5. **Dismiss with reason** → sheet → preset or free-text reason → `record(AnomalyDismissal(cause:reason:dismissedAt:))` (`AnomalyInsightCard.swift:374-377`) → `AnomalyInsightStore.record` writes to UserDefaults (`:34-40`) → card leaves.
6. **The fact stops being carried at step 5.** The reason is written to UserDefaults and never read again: the engine suppresses by `cause` alone (`AnomalyEngine.swift:238`), so "It's winter", "Changed tyres" and "Towing" are byte-identical in effect. The dismissal survives a relaunch (tested `AnomalyInsightUITests.swift:103-138`) but only within this install – persistence beyond that is PJ.32 (`[v1.x]`).

## Proposed rows

| Row | Deliverable | Closes | Consequence today | Severity | Check | Scenario |
|---|---|---|---|---|---|---|
| new (unnumbered) | Make the dismissal reason do something: read `AnomalyDismissal.reason` at an insight boundary (surface "dismissed as winter" on a later fire, or feed a seasonality adjustment), or record the product owner's decision that the reason stays inert data | J9 "dismiss teaches the model" | The four reasons are interchangeable – a user who explains "it's winter" gets the same outcome as "other"; the "teaching" is captured but never used, and the "feeds insight logic later" comment (`AnomalyEngine.swift:45-51`) names behaviour with no call site | gap | L1: a dismissal carrying reason "winter" is distinguishable at the engine/insight boundary from one carrying "tyres"; L4 `AnomalyInsightUITests`: the reason surfaces or otherwise changes a later state | J9 |

## Not settled

- **`docs/SCREENMAP.md:238` says the card "expands in place to the evidence (chart + causes)".** The code shows chart + money line and deliberately no cause (`AnomalyInsightCard.swift:15-19`, RV.121). "causes" is stale pre-RV.121 wording. Doc-drift only – the code is correct; fix the SCREENMAP line in the next change touching it.
- **`docs/NOTIFICATIONS.md:27` says the anomaly insight has an "optional local notification … opt-in"** with a `notifications.anomalies` toggle. No such notification or toggle exists; the field is decoder-only and already recorded as a live gap in RV.196's exception list (`SchemaFieldWriterGuardTests.swift:36-39`, "the product owner decides toggle-or-drop"). Not re-filed – the decision is already owned; the NOTIFICATIONS prose just needs reconciling to "in-app card only" once that decision lands.
