# REVIEW-SCENARIO run: J7d - 2026-09-12b (re-walk, after PJ.200)

- **Scenario:** `J7d` - A reminder is born (`docs/JOURNEYS.md:407-435`)
- **Run id:** REVIEW-SCENARIO-J7d-2026-09-12b
- **Report path:** `diagnostics/REVIEW-SCENARIO-J7d-2026-09-12b.md`
- **Context:** Re-walk. The first walk (`REVIEW-SCENARIO-J7d-2026-09-12`) found every promise MET and marked the scenario implemented. That status line was then cleared by the 2026-09-12 journeys walk (`PJ.200`): `HomeRemindersEntryRow` rendered only in the signed-in `fullLayout`, so a GUEST had no Home reminders row and J7d's discovery surface was account-gated. `PJ.200` shipped with `RV.251` (`e6972b3d`) - `HomeRemindersEntryRow` is now one shared view both layouts render. This walk re-checks ONLY the guest path of "Plan it" and "Discover it", plus anything the first walk gated on. `PJ.60` is the sole open row naming J7d and was reasoned N/A in the first walk; it is unchanged.

## Verdict

**IMPLEMENTED** - the guest path of "Plan it" and "Discover it" is now MET in code and proven reachable by `ColdLaunchGuestParityJourneyUITests.testGuestRemindersRowOpensTheMergedList`; nothing the first walk gated on changed.

## Ticked rows found to be untrue

None. `PJ.200` (`docs/TASKS.md:829`) is ticked and true in the tree:

- The guest Home renders the SAME `HomeRemindersEntryRow` the signed-in `fullLayout` renders - one shared view, not a copy: `HomeGuestLayout.swift:65-67` (`if vehicle != nil { HomeRemindersEntryRow(attentionCount: attentionCount) }`) and `HomeView.swift:258`. The view is defined once at `HomeBanners.swift:164-200`.
- The count is not account-gated: `attentionCount` is `dueRemindersAcrossCars`, computed in `load()` from `RemindersAllRows.rows` + `ReminderListGroups.attentionCount` (`HomeView.swift:500-504`) and passed into `HomeGuestLayout` at `HomeView.swift:196-198`, in the `isGuest` branch (`HomeView.swift:190`).
- The L4 test the row names exists and walks the guest door end to end: `ColdLaunchGuestParityJourneyUITests.swift:144-158` asserts the row is present (`homeRemindersRow`), opens the merged list, and the empty state's `remindersEmptyNewReminderButton` opens the form (`reminderFormSaveButton`).

## Promise-to-code map (guest path only; the rest is unchanged from the first walk)

| Journey promise (J7d) | Status | Citation |
|---|---|---|
| **Plan it** - the permanent "Reminders" row is present on Home for a GUEST, not just signed-in | MET | `HomeGuestLayout.swift:65-67` renders `HomeRemindersEntryRow` when a car exists; shared view `HomeBanners.swift:164-200` |
| The row navigates to the merged list (same route as signed-in, no session gate) | MET | `HomeBanners.swift:169` `NavigationLink(value: Route.remindersAll)`; `Destinations.swift:31` -> `RemindersView(scope: .allCars)` |
| The row's count is derived from the same live rows for a guest as for a signed-in user | MET | `HomeView.swift:500-504` computes `dueRemindersAcrossCars` from `RemindersAllRows` + `attentionCount`; passed to the guest layout at `HomeView.swift:196-198` |
| **Discover it** - zero reminders: the row still reads "Reminders", the empty list explains, one action is a filled button | MET | title is always "Reminders" (`HomeBanners.swift:175`); `RemindersView.swift:80-81` renders `RemindersEmptyStateView` when `rows.isEmpty`; filled `NavigationLink` "New reminder" `RemindersEmptyStateView.swift:35-46` |
| The empty state's "New reminder" opens the form, car-empty from the merged list | MET | `RemindersView.swift:241-243` passes `createRoute`; `:280-285` returns `.reminderForm(reminderID: nil, vehicleID: nil)` for `.allCars` |
| The form arrives with car as its first field, Save waits for the pick | MET (first walk) | `ReminderFormView.swift:65,113,118` |

The row renders only `if vehicle != nil` (`HomeGuestLayout.swift:65`). This is not a gap against "present whether or not anything is due": that phrase is about the reminder count, not the car count, and a user with no car has no reminders to create (the no-car guest gets the Add-car door, `HomeGuestLayout.swift:294-311` / `HomeControls.swift:122-136`).

## Sequence trace (guest, one car, discovery path)

Cold-launch guest adds a car -> Home renders the guest layout (`HomeView.swift:190-204`) -> `vehicle != nil` so `HomeRemindersEntryRow` renders (`HomeGuestLayout.swift:65-67`) with `attentionCount` computed in `load()` (`HomeView.swift:500-504`) -> tap -> `Route.remindersAll` (`HomeBanners.swift:169`) -> `RemindersView(scope: .allCars)` (`Destinations.swift:31`) -> no reminders so `rows.isEmpty` -> `RemindersEmptyStateView` (`RemindersView.swift:80-81`) -> filled "New reminder" (`RemindersEmptyStateView.swift:35-46`) -> `Route.reminderForm(reminderID: nil, vehicleID: nil)` (`RemindersView.swift:280-285`) -> form with car first, Save inert until a car is picked (`ReminderFormView.swift:113,118`).

**Where a fact stops being carried:** none. The car choice is deliberately empty from the merged list (hard rule 13 - the opener names no car), which is the documented behavior, not a lost fact. `testGuestRemindersRowOpensTheMergedList` walks this exact chain to the form.

## Proposed rows

None.

## Not settled

- **`PJ.60` (unchanged from the first walk).** Still open, still not a J7d journey-text promise: its reminder half is "already met by the shipped `ReminderOffer`"; its next-entry half lives only in `docs/SCHEMA.md:249`'s field comment, owned by no journey. It does not change this verdict.
- **The `[v1.1]` marker on the heading (unchanged).** The offer and every promise here shipped in v1; the marker is doc drift, and the brief only authorises the status line, not the heading.
