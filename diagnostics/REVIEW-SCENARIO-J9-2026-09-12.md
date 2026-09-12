# REVIEW-SCENARIO run: J9 · Anomaly nudge - 2026-09-12 (second walk, after RV.240 + RV.268)

**Run id:** REVIEW-SCENARIO-J9-2026-09-12 · **Walked by:** the orchestrator (product owner, 2026-09-12: walks are not dispatched) · **Tree:** `c1676fd5`

## Verdict

**IMPLEMENTED.** The first walk (`REVIEW-SCENARIO-J9-2026-09-11c.md`) held on one thing: a
dismissal reason collected and persisted that nothing read. The owner chose to drop it (`RV.240`)
and the journey text now promises only what ships - *the dismissed cause is not raised again*.
The same walk raised the act reminder being due today; `RV.268` gives it the shared one-year
default and opens it for edit. Every remaining promise walks to code below.

## Ticked rows found to be untrue

None. `RV.240`: `AnomalyDismissal { cause, dismissedAt }` (`AnomalyEngine.swift:50-54`), no
`reason` anywhere in the card, the store or the schema (grep in the RV.240 log; re-run here).
`RV.268`: `HomeView.actReminder` (`HomeView.swift:337-342`) builds the reminder with
`ReminderLifecycle.defaultDueDate` (`ReminderLifecycle.swift:57-60`, one year out) and
`actOnAnomaly` (`:353`) persists it and pushes `Route.reminderForm`; the orchestrator's mutation
(default = today) went red on 2 of 3 L1s. `RV.121`, `RV.148` [v1.1]: as the first walk found.

## Promise-to-code map

| Promise (J9 text) | Status | Evidence |
|---|---|---|
| app-detected consumption drift ("+12% over 3 months") | MET | `AnomalyEngine.minimumRelativeDrift = 0.12` (`:196`), rolling window vs the same window a year back (`baselineLagDays = 365`, `:168`), floors `minimumSegmentsPerWindow = 3` / `minimumRecentSegments = 1` (`:176,182`) |
| gentle `warn`-amber card in the Log, never a push alarm | MET | `AnomalyInsightCard` rendered from `HomeView.swift:286` in the Log; amber is `Theme.Palette.warn` (frame `RV.240-anomaly-card` opened); `docs/NOTIFICATIONS.md:27`: in-app only by default, push opt-in |
| tap explains the evidence: a chart of the drift and what it costs per month at the driver's own recent prices | MET | expanded card draws the two windows as bars (`AnomalyInsightCard.swift:161-186`) and the cost line from `AnomalyEngine.monthlyCostDelta` (`:261`) at recent prices (`monthlyCostAmount`, card `:123`); the RU frame shows *6.5 vs 5.4 · about 14.89 € a month more at current prices* |
| never a guessed cause (RV.121) | MET | the card names no cause; `docs/VISION.md` "What we will not tell a driver" cited in the card's doc comment |
| dismiss → the dismissed cause is not raised again | MET | `onDismiss` records `AnomalyDismissal(cause:dismissedAt:)` (`HomeView.swift:374-377`) into `AnomalyInsightStore` (`:34`); the engine skips a cause with a recorded dismissal (`AnomalyEngine.swift:234`), keyed by metric + evaluation month so one dismissal never mutes everything (`:14-18`) |
| act → creates a service reminder due next year and opens it for edit | MET | `actReminder` + `Route.reminderForm` above; `RV268-anomaly-reminder` frames show *12 сент. 2027 г.* in the form, editable |
| thresholds conservative, seasonality-aware, always dismissible | MET | 12% floor and the 3-segment floors; the baseline is the same calendar window a year earlier (seasonality by construction); dismiss is one tap, no confirmation |
| Success metric: acted on or dismissed ≥70% | N/A | a metric; `capture.pipeline`-style keys for it are not promised by the text |

## Sequence trace (one driver, a winter of +21%)

1. The Log renders; `HomeView` asks the engine for an anomaly over the vehicle's fills, filtered by
   the recorded dismissals (`HomeView.swift:51-60`) - derived every time, never stored (rule 2).
2. The card appears amber, collapsed: *Consumption up 21% vs last year*, the two figures.
3. Tap → the two-bar comparison and the monthly cost at recent prices; no cause is named.
4. *Dismiss* → one tap; the (metric, month) cause is recorded; the next recompute skips it; a
   different month's drift is a new cause and shows again.
5. *Create reminder* → *Check fuel consumption*, due one year out, opens in the reminder form with
   the date editable; the card's cause is recorded as dismissed at the same time (`:361`).

Nothing is lost between steps: the cause decided at 1 is the cause suppressed at 4 or 5.

## Proposed rows

None.

## Not settled

- **"A chart of the drift"** is drawn as two bars (the recent window against the year-ago
  window), not a series over time. The two-bar form does show the drift the card is about and is
  what the artboard draws; a time series would need the engine to expose per-window history it
  does not compute today. The C+D journeys walk of 2026-09-12 raised the same question; it is a
  product preference, not a gap, and stays unfiled unless the owner wants the series.
- `RV.268` made one year the default due date for EVERY custom reminder, not only the act one
  (the form's default was today). It matches the owner's words and is flagged in the row for
  confirmation.
