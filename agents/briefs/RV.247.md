# RV.247 - "Type amount" from the all-cars reminder list logs to the selected car

**Scenario: J7c · reminder lifecycle.** `[!]` - hard rule 8: the record lands on the wrong car.
The one bug row holding J7c open. Found by J7c's walk, verified by the orchestrator.

The merged list (`HomeRemindersEntryRow` -> `.remindersAll`, `RemindersAllRows.swift:28-43`) shows
every active car's reminders. Completing a non-selected car's reminder opens the completion sheet,
and *Type amount* resolves the new entry's vehicle from `carSelection.selectedVehicle`
(`ServiceEntryView.swift:283`; `ExpenseEntryView` the same). The notification deep-link path is
right because `driveReminder` selects the car first; the list path never does. Two screens, each
correct, and the car is dropped between them - `RV.189`'s sequence shape.

## Build

**One mechanism.** Either carry the reminder's `vehicleId` through `ReminderCompletionSession.Pending`
(or the entry route) so ServiceEntry and ExpenseEntry write to it explicitly, or select the
reminder's car before the sheet opens. Prefer the first: an explicit vehicle on the entry cannot
be wrong by timing, and selection is UI state. Whatever you choose, the invariant is **the entry's
`vehicleId` equals the reminder's**, on both entry kinds, from both the list and the deep link.
Check `ReminderCompleteSheet`'s other routes (*mark done*, *type odometer*) for the same drop.

## Tests

- **L1, FAILS TODAY**: completing a reminder whose `vehicleId` is not the selected car yields an
  entry with the reminder's `vehicleId` - for a service AND an expense, in one test file.
- **L4 `RemindersUITests` EN + RU**: two cars seeded, the non-selected car's reminder completed from
  the merged list with a typed amount; the entry is in THAT car's log and not the other's. The
  **not the other's** half is the assertion that matters.
- No screenshots unless a screen changes.

## Mutation - named

Resolve the vehicle from the selection again on one entry kind; the cross-kind L1 goes red.
Byte-identical restore; verbatim.

## Vacuous traps

- Asserting the sheet shows the reminder's car name. It may; the entry is what is written.
- Fixing the service path and not the expense path.
