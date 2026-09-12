# REVIEW-SCENARIO: J7c · Reminder lifecycle

- **Run id:** REVIEW-SCENARIO-J7c-2026-09-12
- **Scenario:** `J7c` (`docs/JOURNEYS.md:433`)
- **Verdict:** **NOT IMPLEMENTED**

## Ticked rows found untrue

None. `RV.74`, `RV.75`, `RV.76`, `RV.77`, `RV.78`, `PJ.4`, `PJ.5`, `PJ.7` all hold against the code. The two findings below are **unowned promises**, not false ticks.

## Promise-to-code map

| Journey promise | Status | Evidence |
|---|---|---|
| Trigger: reminder fires | MET | `ReminderNotificationPlanner.plan` arms date/odometer/overdue `ReminderNotification.swift:129-216`; adapter attaches category `ReminderNotificationCoordinator.swift:12-33` |
| Trigger: user did the thing early | MET | complete button on every row incl. `.scheduled` `RemindersSections.swift:102-113` |
| RV.74 tap lands on merged list + completion sheet, live car selected | MET | `TabRoots.swift:472-487` (driveReminder selects live car); `RemindersView.swift:313-343` surfaces completion; `resolveDeepLinkedReminder` `:350-357` |
| RV.74 deleted reminder → plain list (hard rule 7) | MET | `RemindersView.swift:354` guard; `NotificationResponseParser` `.none` `ReminderBannerAction.swift:89-93` |
| RV.78 Mark done opens completion sheet (never silent `.done`) | MET | `ReminderBannerAction.swift:14-23`; `NotificationResponseParser.resolve` `:76-80` maps tap+complete to `.open` |
| RV.78 Push a week defers 7d and re-arms | MET | `ReminderLifecycle.snooze` `:276-285`; `ReminderNotificationCoordinator.snooze` `:408-432` routes through same reconcile |
| Complete: sheet "Log the cost?" | MET | `ReminderCompleteSheet.swift:114-163` (Type amount / Skip) |
| Complete: pre-fill category/title/today/odometer | MET | service `ServiceEntryView.swift:292-304`; expense `ExpenseEntryView.swift:366-372` |
| Complete: "scan the invoice or type a lump sum" | N/A (`PJ.24` v1.x) | sheet offers Type+Skip only; scan door lives inside ServiceEntry, not on the sheet (`docs/TASKS.md:797`) |
| Complete: next cycle anchored at completion, not due | MET | `ReminderLifecycle.complete` `:204-226`; preview + persist share one pure fn `ReminderCompleteSheet.swift:38-43`, `ReminderCompletion.persist` `:81-87` |
| Complete: declining is first-class (`.done(nil)`) | MET | `ReminderCompleteSheet.skip` `:260-267`; `ReminderCompletionSession.persistCompletion` `:32-53` |
| Reschedule: push due, fired re-arms | MET | `ReminderDraft.applied` resets `.attention→.scheduled` `:81-93`; form save → `reconcile` `ReminderFormView.swift:149-155` |
| Delete: tombstone + 30-day undo | MET | `Repository.swift:268,274` (`softDeleteReminder`/`restoreReminder`); `RecentlyDeletedView.swift:322-331`, `:400-443` |
| Dismiss-with-reason: keeps row with reason | MET | `ReminderLifecycle.dismiss` `:294-301`; status carries reason `Enums.swift:264` |
| Dismiss-with-reason: "teaches insights" / "keeps history" | **MISSING** | reason written `RemindersView.swift:195-207`, read by nothing; no surface shows `.done`/`.dismissed` rows |
| Loop warning: completion→entry→next-cycle is a loop, not a dead end | MET | `ReminderCompletionSession` + `ReminderOffer` (post-save) close both directions |
| Success metric: recurring auto-rescheduled 100% | MET | `ReminderLifecycle.complete` creates next occurrence unconditionally when recurrence + anchor exist `:205-226` |
| PJ.4 production entry point | MET | `HomeRemindersEntryRow` `HomeBanners.swift:164-200` → `.remindersAll`; VehicleDetail reminders row |

## Sequence trace (one user, end to end)

Oil-change reminder fires at 09:00 (`ReminderNotificationPlanner`) → banner shows Mark done / Push a week (`UNNotificationScheduler` category) → user taps **Mark done** → `NotificationResponseParser` `.open(.reminder)` → `NotificationRouter` → `TabRoots.driveReminder` selects the live car → merged list with completion sheet → sheet "Log the cost?" → **Type amount** → `ServiceEntryView` pre-fills category/title/today/odometer → save → `persistCompletion` marks `.done(entryId)` + writes next occurrence anchored at completion → `reconcile` cancels the old notification, arms the next → sheet's `onChange(of: entrySheet)` sees `.done`, dismisses → list shows the next occurrence under Scheduled.

**The fact that stops being carried: the CAR.** The chain carries the reminder's car only on the notification deep-link path (`driveReminder` selects it). On the merged-list path - `HomeRemindersEntryRow` → `.remindersAll` (`HomeBanners.swift:169`) → `RemindersAllRows` merges every active car (`RemindersAllRows.swift:28-43`) - the complete button on a **non-selected** car's row opens the sheet, and "Type amount" resolves the entry's vehicle from `carSelection.selectedVehicle` (`ServiceEntryView.swift:283`, `ExpenseEntryView.swift:351`). `ReminderCompletionSession.Pending` carries `reminder`/`completionDate`/`completionOdometer` but never the vehicle (`ReminderCompletionSession.swift:17-21`), and neither entry route carries one (`SheetRoute.serviceEntry`/`.expenseEntry`, `Routes.swift:129-130`). Result: with car A selected, completing car B's reminder logs the service to **A**, and B's reminder completes against A's entry id. `ReminderCrossVehicleTests` covers the query/grouping only (`ReminderCrossVehicleTests.swift:49-151`); no test covers the completion→entry vehicle. The journey's own RV.74 note promises the opposite: *"Type amount, which logs to the selected car - follows the reminder"* (`docs/JOURNEYS.md:439-440`).

## Proposed rows (attach to J7c)

1. **"Type amount" from the merged list logs to the selected car, not the reminder's car.** Close J7c Complete / RV.74 note. Carry the reminder's `vehicleId` through `ReminderCompletionSession.Pending` (or the entry route) and have ServiceEntry/ExpenseEntry write to it, or select the reminder's car before opening the sheet - one mechanism, and the entry's vehicle must match the reminder's. User-facing today: a two-car driver completing a non-selected car's reminder from the merged list writes the cost to the wrong car and completes the reminder against a foreign entry id. Severity **bug**. Done: L1 the hand-off writes to `reminder.vehicleId`, not the selected car; L4 `RemindersAllCarsUITests` - seed two cars, select A, complete B's reminder via Type amount, assert the entry lands on B and B's reminder `.done(entryId)` references B's entry.

2. **Reminder dismiss-with-reason is collected, persisted, synced and read by nothing; the copy promises "stays in your history - a reason helps the app learn" and neither half exists.** Close J7c Delete note ("keeps history and teaches insights", `docs/JOURNEYS.md:456`; `docs/SCHEMA.md:294,301`). `RemindersView.swift:195-207` collects and `ReminderLifecycle.dismiss` `:294-301` persists a reason no code reads back; there is no surface for `.done`/`.dismissed` rows. Decide (a) surface reminder history and make the reason feed something, or (b) drop the reason field and fix the copy - the `RV.240` shape, but for `ReminderStatus.dismissed(reason:)`, a different field than `AnomalyDismissal.reason`. Severity **gap** (decide-or-drop). Done: under (a) L1 the stored reason renders / feeds; L4 EN+RU; under (b) field + copy removed, `SCHEMA.md` amended.

## Not settled

- Whether "reminder history" (completed "oil changed 3× on time", `docs/SCHEMA.md:294`) is in v1 scope at all, or v1.x. That scoping question is folded into proposed row 2's decide-or-drop and needs the product owner's answer before the row is written.
