# RV.251 - a guest with two cars has no car switcher on Home

**Scenarios: J1 · first launch (the guest Home), J7c · the all-cars reminder list.** Sibling of
`RV.197`. Found verifying `RV.247`: its L4 switches cars on Home through `carSwitcherButton`,
which only `HomeView`'s signed-in layout renders (`HomeView.swift:406`, `HomeEmptyStates.swift:93`);
`HomeGuestLayout` has none. A guest can add a second car from the Garage, so the state is
reachable, and a car switcher is not a sync feature (hard rule 1's spirit).

## Build

Render the SAME car switcher on the guest Home when the guest has more than one car - the control
`HomeView` uses, not a copy. Zero or one car keeps today's guest layout unchanged. Then remove
`-seedSettingsSignedIn` from `RemindersRV247UITests` and show its two tests pass as a guest, as
`RV.197` did for three suites; if they still need the seed, say exactly why.

## Tests

- **L4 `ColdLaunchJourneyUITests`, FAILS TODAY**: a guest with two cars switches on Home and the
  log follows the selection.
- **L1**: the layout decision (`HomeLayout`, `RV.197`'s core function) exposes the switcher on car
  count alone - no session parameter, so it cannot be gated on account state.
- EN + RU frames of the guest Home with two cars; capture lines.

## Mutation - named

Gate the switcher on the session again; the cold-launch L4 goes red. Byte-identical restore.

## Vacuous trap

A second switcher view for guests.

## Widened 2026-09-12 - the whole guest-parity seam in this dispatch

The 2026-09-12 journeys walk found three more places where `HomeGuestLayout` diverges from the
signed-in Home for no account-related reason. **Fix all four in this one change - same seam, same
rule (the SAME control, never a copy), one commit:**

- **`PJ.100`** - the guest "Type it" (`HomeGuestLayout.swift:218`) is a plain button to
  `.confirmManual`; the signed-in `typeItControl` (`HomeView.swift:422-444`) is the
  `CaptureEntryForm.doorMenuForms` menu. Render that control. L4: guest "Type it" exposes Service
  and Expense with the signed-in identifiers; picking Service opens `ServiceEntryView`.
- **`PJ.101`** - the guest `noCarCard` (`:272-284`) has no button; the signed-in no-car layout has
  the filled `Route.addVehicle` button (`HomeEmptyStates.swift:72-82`). Render it. L4: guest, no
  car, tabbed Home - the button opens Add car.
- **`PJ.200`** - no `HomeRemindersEntryRow` in the guest branch (`HomeView.swift:256` is
  signed-in only). Render the same row with `Route.remindersAll`. L4: guest with one car - the row
  is present, opens the merged list, "New reminder" reachable. **This one is a finding against
  reviewed J7d**; its status line is already cleared.

Prefer making `HomeLayout` (RV.197's core decision) the single place that says what the guest
branch shows, so the next parity gap cannot be introduced by editing one layout and not the other -
if that is more than this change should carry, say so and do the four renders directly.

Screenshots: guest Home with two cars (RV.251), guest Home with the reminders row and the Type-it
menu open (PJ.100/PJ.200), guest no-car Home (PJ.101) - EN + RU, dark. Mutations: one per row,
named above; report each verbatim. Suites: `ColdLaunchJourneyUITests`, `RemindersRV247UITests`,
each in its own invocation with counts.
