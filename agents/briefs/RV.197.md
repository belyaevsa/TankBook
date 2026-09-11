# RV.197 - a user with no account can log a fill-up and then never see it

**Scenarios: J8b · look at the receipt again, and J3 · the five-second fill-up.** `[!]` - this is on
users' phones today. **It is dispatched alone**, before anything else in J3.

## The defect

Found 2026-09-10 by `RV.165`'s cold-launch walk, on its first run, and confirmed again on 2026-09-11
when `RV.206`'s agent found `ExpenseCaptureUITests` passing only on a Keychain session a previous
run had left behind. `HomeView.isGuest` (`HomeView.swift:190`) renders `HomeGuestLayout` whenever
the Keychain holds no session, and that layout is a garage card, a capture card, an import card and
a privacy line - **there is no log stream in it**. The guest Home offers *Type it*
(`HomeGuestLayout.swift:192`), so the entry saves; it is simply never shown again.

**Hard rule 1 in its plainest form** - *no screen is ever sync-gated* - and the Log is gated on
account state. It contradicts the launch commitments that sign-in IS registration and that the app
is useful before you have one. **443 UI tests missed it because every Log test signs in first.**

## What to build

The guest Home shows the log stream the signed-in Home shows - the SAME `LogStream` view, not a
second one - once the user has an entry. Decide what the guest layout looks like with zero entries
(today's cards are the right empty state) versus one or more (the log must appear), and whether the
Log **tab** is reachable as a guest at all - walk `AppTabBar` and `SCREENMAP.md`. If the tab is
hidden for guests, that is the same defect one screen over; fix it in this row.

**Read `docs/JOURNEYS.md` J1 and J3 first** - J1 promises "fresh install to first logged entry
under 3 min"; that entry must then be visible. `docs/SCREENMAP.md`'s Home inventory and the
`HomeGuestLayout` artboard: if the artboard has no log, the artboard is wrong and this row says so.

## Tests

- **L4 `ColdLaunchJourneyUITests`, and it FAILS TODAY**: from a cold launch with **no session**,
  type a fill-up, save, and find it on Home and in the Log. No `-seedSettingsSignedIn`. This is
  the exact walk that found the bug; make it the test that keeps it fixed.
- **L1**: `HomeView`'s layout choice depends on entry count, not on session state, for the log
  stream specifically - asserted from the view model or the layout enum, whichever decides.
- **Remove the accidental session dependency** `RV.206`'s agent found: `ExpenseCaptureUITests`
  gained `-seedSettingsSignedIn` to become deterministic. Once the guest Home shows the Log, that
  seed should be **unnecessary** - remove it from that helper and show the suite still passes
  guest. If it does not, that is a finding.
- EN + RU frames of the guest Home with one entry; capture lines added.

## Mutation - named

Restore the guest branch that omits the log stream; the cold-launch L4 goes red. Byte-identical
restore; outputs verbatim.

## Vacuous traps

- A second log list for guests.
- Passing the test by seeding a session.
- Showing the entry on Home and leaving the Log tab unreachable.
