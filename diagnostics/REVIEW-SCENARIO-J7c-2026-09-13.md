# REVIEW-SCENARIO run: J7c · Reminder lifecycle - 2026-09-13 (second walk, after RV.247 and RV.248)

**Run id:** REVIEW-SCENARIO-J7c-2026-09-13 · **Walked by:** the orchestrator (product owner, 2026-09-12: walks are not dispatched) · **Tree:** `6aad8b18`

## Verdict

**IMPLEMENTED.** The first walk (`REVIEW-SCENARIO-J7c-2026-09-12.md`) proposed two rows and both
shipped: `RV.247` (the merged list's *Type amount* logs to the reminder's own car) and `RV.248`
(done and dismissed rows, with their reasons, in a History section - the owner's option (a)).
`PJ.24` (scan the invoice from the completion sheet) is `[v1.x]` by the tier table and is N/A for
the v1 verdict; its marker now leads the row so the index reads it that way.

## Ticked rows found to be untrue

None. `RV.247`: `ReminderCompletionSession.Pending.vehicleId` carried into the entry route;
`RemindersRV247UITests` 2/2 as guests (re-run for `RV.251`). `RV.248`: walked to code in its tick
and below; the orchestrator's mutation (history keeping active rows) went red on 2 of 6 L1s.
`RV.74`, `RV.78`: cited from the first walk, unchanged.

## Promise-to-code map

| Promise (J7c) | Status | Evidence |
|---|---|---|
| Complete → "Done! Log the cost?" → entry pre-filled (category, title, today, odometer); scan or type | MET | `ReminderCompleteSheet.swift` (*Log the cost?* / *Skip*); `RemindersUITests.testCompleteOpensTheSheetAndSkipRecurs`, `testTypeAmountLandsInTheEntryWithThePrefill` |
| the next cycle is scheduled, anchored at completion, never the original due | MET | `ReminderLifecycle.complete(_:completionDate:…)` (`ReminderLifecycle.swift:201-219`) computes the next occurrence from `completionDate`; the doc at `:13` states it |
| declining the cost log is first-class (`.done` without an entry) | MET | *Skip* on the sheet; `testSkipMovesANonRecurringRowIntoHistory` (updated by RV.248 to assert the row lands in History as *Completed*) |
| Reschedule: push the due date/odometer, a fired notification re-arms | MET | `ReminderLifecycle.reschedule` (`:247`); banner *Push a week* → `ReminderBannerAction.snooze` (`ReminderNotificationActions.swift:28`), `testSnoozeResponseReArmsAndTheArmedRequestCarriesTheCategory` (real-center, skips on a dropping daemon per RV.258) |
| Delete: tombstone, 30-day undo | MET | `testDeleteAlertStatesTheThirtyDayTruth`; Recently deleted lists reminders (`DeletedEntries.swift:64`) |
| Dismiss with an optional reason → History with the reason as caption; completion count beside done rows | MET | `ReminderLifecycle.dismiss` (`:304`) → `ReminderHistory` rows (`Service/ReminderHistory.swift`), `ReminderHistorySection.swift`; frames `RV.248-reminder-history` EN + RU opened: *Sold the tires*, *Completed · Shell Service · 2 times* |
| a fired reminder's tap lands on the merged list with its completion sheet (RV.74) | MET | `testReplayedReminderTapLandsOnRemindersWithItsCompletionSheet`, `testReplayedUnknownTapIsInert` |
| banner actions Mark done / Push a week route through the one lifecycle (RV.78) | MET | `ReminderNotificationActions.category()` registers `.complete` and `.snooze` (`:24,28`); `TabRoots.swift` handles both through `ReminderLifecycle` |
| reachable in Release (PJ.4) | MET | Home reminders row (`HomeRemindersEntryRow`, now on the guest Home too - `PJ.200`) and the VehicleDetail row (`testVehicleDetailRowReachesTheRemindersScreen`) |
| Success metric | N/A | metrics |

## Sequence trace (one reminder, fired, completed with a cost)

1. The banner fires; *Mark done* opens the app on the merged list with the completion sheet over
   the reminder's own live car (RV.74).
2. *Log the cost?* → *Type amount* → ServiceEntry pre-filled, saved to the reminder's `vehicleId`
   (RV.247).
3. `ReminderLifecycle.complete` marks the row `.done(entryId)` and, when recurrence is set, creates
   the next occurrence anchored at the completion date/odometer.
4. The live list shows the next occurrence; the completed row is read back in History, naming the
   entry it logged and the count of completions of that title on that car (RV.248).
5. A dismissal instead of a completion lands in the same History with its reason.

The reminder's car is the fact carried end to end: the deep link selects it, the entry writes to
it, History groups by it.

## Proposed rows

None.

## Not settled

- The History caption *"a reason helps the app learn"* stands by the owner's decision (a); no
  consumer learns from the reason today and no row owns one. Noted, not filed - the owner chose
  the history surface over the learning claim's removal.
