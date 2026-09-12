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
