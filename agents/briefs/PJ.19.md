# PJ.19 - station suggestion: the logic is written and never called

**[v1.1]**, product-owner priority (2026-08-31). Journey gap: J4 station, F3, `docs/VISION.md:63`.

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** If a file is in your way or a test is
red that is not yours, report it and carry on.

## Part of this row's premise is already stale - check before you build

The row says to *"replace the inert action-coloured 'Nearby suggestion' label
(`ManualFillUpSections.swift:518-522`)"*. **That label no longer exists** - `Nearby` appears nowhere
in `ios/App/Sources`. What is there now is a plain `Menu` of the user's stations with a
`stationLabel(selection)` and an "Not set" / «Не указана» placeholder. The dead-label half of the row
is done; **do not go looking for it.**

What is genuinely missing, confirmed:

- **No ranking exists anywhere.** There is no station-ranking function in `TankbookCore` - the only
  station helpers are persistence (`Repository.liveStations`) and import normalisation
  (`ImportStation`).
- **No location is ever read.** `CoreLocation` appears in no source file; `Coordinate`
  (`Entities.swift:489-493`) is a plain lat/long value type on `Station`, not a location client.

So the row is: **build the ranking and the permission-optional location that feeds it, and use it to
pre-select a station in the Confirm sheet.**

## What to build - exactly as the docs already specify it

The behaviour is **already written down**; implement what is there rather than designing it again:
`docs/JOURNEYS.md` -> J4 "Station suggestion - the logic", `docs/SCHEMA.md` -> Station, and
`docs/ERRORS.md` -> Confirm. Read all three first. In outline, and the docs win where they differ:

- Rank the user's **favourite / known** stations by distance from the current `CLLocation` **when
  location is authorised**, and apply the **last-visit fuel-kind default**.
- **Location is never required** (hard rule 1: no feature may require the network, and a permission
  the user declines is the same shape). With no permission, no location fix, or no stations, the
  ranking returns **nil** and the sheet shows exactly what it shows today. A suggestion is a bonus,
  never a gate, and its absence is a non-event - **not** an error, a prompt or a banner.
- The suggestion is **pre-selected and changeable** (hard rule 13: the app suggests, the user
  decides). Once the user picks a station, that is their choice for that entry - no later ranking
  pass may move it.
- **Ask for permission at the moment it buys something**, never at launch (`docs/NOTIFICATIONS.md`
  states the equivalent rule for notifications; follow the same principle and record the decision).

**The ranking itself belongs in `TankbookCore` as a pure function over injected coordinates**, not in
the view: it must be testable with no simulator, no permission and no `CLLocationManager`. Keep the
platform location client at the app layer behind a small seam the core does not know about.

## Explicitly out of scope

- Station brand normalisation and the `detectedCountry` hint - that is [RV.115], undelivered, and it
  must not be pulled in here.
- Creating or editing stations, and the Garage's station management.
- Any network call for places, geocoding or a station directory. **A server-side station lookup would
  break hard rules 1 and 9** - this is a local ranking over the user's own stations.
- [RV.146]'s currency chips, though they sit on the same sheet.

## Docs to read before writing (in order)

1. `docs/JOURNEYS.md` -> J4 "Station suggestion - the logic" - **the authority for the ranking**.
2. `docs/SCHEMA.md` -> Station (fields, `favorite`, `lastUsedAt`, `defaults`).
3. `docs/ERRORS.md` -> Confirm, and F3.
4. `docs/SECURITY.md` - a coordinate is a domain value: **never logged** (hard rule 12).
5. `CLAUDE.md` hard rules 1, 7, 12, 13.

**Extend the docs in the same change** where the implementation settles something they leave open -
in particular when the permission is asked for, and what happens on a denied or restricted
authorisation.

## UI suites to run

`TankbookUITests/ConfirmManualUITests`.

## Tests you must add

- **L1, the substance**: the ranking over **injected** coordinates and favourites returns the
  expected order - assert the ORDER, not membership.
- **L1**: with no permission, no fix, or no stations, the ranking is **nil** and nothing is
  pre-selected.
- **L1**: the last-visit fuel-kind default is applied from the ranked station.
- **L1**: no coordinate, station name or distance is ever logged (hard rule 12).
- **L4** (`ConfirmManualUITests`): no stations -> no suggestion label at all; seeded stations plus an
  injected location -> the suggestion is **pre-selected and still changeable**.
- **L1**: a user's explicit pick is not overridden by a later ranking pass (hard rule 13).

## Vacuous traps, named

- Looking for the "Nearby suggestion" label the row names - it is already gone.
- Testing against the simulator's real location, so the test passes only on your machine. **Inject
  the coordinate.**
- Requiring permission for the sheet to work, or surfacing a denial as an error (hard rules 1 and 7).
- Putting the ranking in the view, where it cannot be tested without a simulator.
- Asserting a suggestion **appears** without asserting **which** station and that it can be changed.
- Logging a coordinate or a station name (hard rule 12).

## Screenshots

`design/screenshots/PJ.19-station.png` and `-ru.png`: the Confirm sheet with a suggested station
pre-selected. A second pair with no stations (no suggestion) is worth having, since "shows nothing"
is half the contract.

## Report back

Every check with the **exit code you observed** and the observed counts; whether each test was **run
or only written**; where you put the ranking and how the location seam is injected; when the
permission is asked and what a denial does; what the docs already settled versus what you had to
decide; and anything you found and did not fix.

## Never stash, move or `git checkout` to get a "clean baseline"

To show a test fails before the fix: **write the test, run it against the unmodified code, then make
the change.** If the change is already written, prove the test's teeth with a **mutation** - revert
the one line the test is about, run it, restore the line. **Do not** `git stash`, `git checkout`, or
move files out of the tree: on 2026-09-08 an agent did that and a bad `mv` loop destroyed three of
its own new files. Assume you are not alone in this checkout.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**.
Use `pgrep -x xcodebuild`. **Never `pkill -f`.**

## Standing checks

Re-measure the baseline yourself and report what you observe. As left, `main` was **1702 tests / 190
suites**, **777** localization keys at 100% RU.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0. From the root, **not** `ios/`: the `excluded:`
   paths are root-relative and from `ios/` it reports thousands of phantom errors.
3. `cd ios && swift test` - full, never subsetted; report the count.
4. `xcodegen generate`, then the UI suites named above **by name**, each with its **observed,
   non-zero** count. A filter matching nothing prints "0 tests ... passed" and still exits 0.
5. Localization gate - exit 0; report the key count and RU percentage. **Every new user-facing
   string is EN and RU** (hard rule 10).
6. Release build only if you touch a `#if DEBUG` seam (a test seed is one). Say which applies.

Verify by **exit code** (`echo $?`), not by skimming output, and report the codes you observed.

**Screenshots**: EN **and** RU, **dark** theme, captured **outside** any running test (`simctl` and
`xcodebuild test` fight over the device). Pass `-homeResetDatabase` alongside any seed. RU:
`xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU`.
RU runs 20-30% longer and short strings expand worst. **You cannot see your own screenshots** - the
orchestrator opens every one. State what you captured; do not assert it looks right.
