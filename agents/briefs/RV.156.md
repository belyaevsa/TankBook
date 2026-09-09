# RV.156 - nothing in the app can create a station

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** If a file is in your way or a test is
red that is not yours, report it and carry on.

## The defect

Product owner, 2026-09-09: *"station on an entry stays 'unset', it's not clickable."* Their device
reports `rowCount.station=0`.

`ManualFillUpSections.swift:544-553` renders a **non-interactive** `inkSoft` placeholder when
`stations.isEmpty`, and the comment says why: *"nothing to choose from yet, so nothing to tap... The
location-based suggestion is PJ.19; until it ships this row promises nothing."* **PJ.19 shipped**
(`b6ea56d`) and does not close this - it RANKS existing stations and creates none.

**`upsertStation` has zero non-seed callers in `ios/App/Sources`.** The only writer is the import
path (`ImportStation`). So a user who types their entries has an empty station set forever, and
three shipped features stand on a door that was never built: PJ.19's ranking has nothing to rank,
[RV.150]'s stamp has nothing to stamp, and the Garage Stations list
(`ios/App/Sources/StationSettings/StationsListView.swift`) shows a list nothing can add to.

## Reuse the deterministic minting that already exists - this is the design decision

`ImportStation.station(for:existing:now:)`
(`ios/Sources/TankbookCore/Import/ImportStation.swift:29-42`) already does exactly what creation
needs: it trims the name, returns the existing station when one matches, and otherwise mints one
whose **id is a deterministic function of the name** (`stableID(for:)`).

Its own comment states the property that matters here: *"two devices parsing the same file resolve to
the same station."* **The same holds for two devices typing the same name** - so reusing this helper
makes independent creation converge instead of producing duplicates, which is the failure mode a
random UUID would guarantee. Reuse it (move or generalise it if its current home is wrong - say
which and why); **do not write a second minting rule**, and do not merge or rename existing stations
(that is [RV.115] and is out of scope).

## What to build

**A way to name a station, reachable from both places the user notices they want one.**

1. **The entry's Station row becomes interactive in BOTH states.** With no stations it offers the
   add path instead of a dead label; with stations it keeps today's menu and gains the same entry at
   its end. A user with one station must be able to add a second - offering it only in the empty
   state is a named trap below. The row is shared by Confirm and Edit entry
   (`ManualFillUpStationRow`, used at `ManualFillUpView.swift:157` and `EditEntryView.swift:539`), so
   fix it once.
2. **The Garage Stations list gains an add affordance**, so the door exists where stations are
   managed and not only mid-entry.
3. **A created station is selected on the entry that created it** - creating one from the row and
   then having to pick it again is a dead end in slow motion.

**A name is enough.** `favorite`, `defaults` and `location` are filled by use - [RV.150] already
stamps `lastUsedAt`, `defaults` and the forecourt fix on save - so do not ask for them up front.
**Decide and record what an empty or whitespace-only name does**, and what happens when the typed
name matches an existing station (the helper returns the existing one, which is almost certainly the
right behaviour, but the UI must not silently look like it created a second).

**A station is a synced entity** (`docs/SCHEMA.md` -> Station; record-level LWW, confirmed by
[RV.150]): creating one is an ordinary `.dirty` write and needs nothing new for sync.

**Fix the stale comment** at `ManualFillUpSections.swift:545-549` in the same change - it cites PJ.19
as the thing that will make the row live, and PJ.19 has shipped (`CLAUDE.md` -> Code comments:
current truth only).

## Explicitly out of scope

- Station brand normalisation, deduplication and merging - [RV.115].
- PJ.19's ranking and [RV.150]'s stamping. Both already work; this row gives them input.
- Renaming or deleting stations, unless the Garage list already has those affordances.

## Docs to read before writing (in order)

1. `docs/SCHEMA.md` -> Station.
2. `docs/JOURNEYS.md` -> J4 (the station journey) - **extend it** with the creation door.
3. `docs/SCREENMAP.md` if you add a route; `docs/ERRORS.md` if you add a message.
4. `CLAUDE.md` hard rules 7, 13, 15.

## UI suites to run

`TankbookUITests/ConfirmManualUITests`, `TankbookUITests/EditEntryUITests`,
`TankbookUITests/StationSettingsUITests`, `TankbookUITests/GarageUITests`. Report each observed,
**non-zero** count.

## Tests you must add

- **L4, the row's whole point**: on a car with **no** stations, the Station row is tappable and
  reaches a way to name one; the named station is then **selected on the entry**.
- **L4**: on a car **with** stations the menu still works **and** offers the add path.
- **L4**: the Garage Stations list can add one, and it appears in the list.
- **L1**: creation goes through the shared deterministic helper - the same name typed twice yields
  **one** station, not two. Assert the id, which is what makes two devices converge.
- **L1**: a created station is written `.dirty` and syncs like any other entity.
- **L1**: [RV.150]'s stamp then fills `lastUsedAt` and `defaults` on it at the next save - the two
  rows compose.
- **L4**: EN and RU at the largest text size.

## Vacuous traps, named

- Asserting the row is `isHittable` rather than that tapping it **produces a station** - [RV.84]
  measured `isHittable` returning true for an element **86% clipped**. Assert the frame against the
  window.
- Adding the affordance only to the empty state, so a user with one station can never add a second.
- Minting a random UUID instead of the deterministic id, which guarantees duplicates across devices.
- Auto-creating a station from typed text without the user naming it (hard rule 13).
- Merging same-named stations - that is [RV.115].
- Leaving the comment that cites PJ.19 as the reason the row is dead.

## Screenshots

**EN and RU**, **dark**, outside any running test: the Station row on a car with no stations showing
the add path, and the created station selected on the entry. Commit as
`design/screenshots/RV.156-station-add.png` and `-ru.png`.
RU: `xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU`.
**`simctl launch` on an already-running app silently ignores new arguments** - `terminate` first and
wait for the relaunch, or the "RU" shot is the EN one with a different clock. **You cannot see your
own screenshots**; state what you captured.

## Never stash, move or `git checkout` to get a "clean baseline"

Write the test, run it against the unmodified code, then make the change - or mutate one line to
prove the test's teeth. **Do not** `git stash`, `git checkout`, or move files out of the tree: an
agent did that on 2026-09-08 and a bad `mv` loop destroyed three of its own new files.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**.
Use `pgrep -x xcodebuild`. **Never `pkill -f`.**

## Standing checks

Re-measure the baseline yourself and report what you observe. As left, `main` was **1793 tests / 205
suites, all green**, **808** localization keys at 100% RU.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0. From the root, **not** `ios/`.
3. `cd ios && swift test` - full, never subsetted; report the count.
4. `xcodegen generate`, then the UI suites above by name with observed, non-zero counts.
5. Localization gate - exit 0; report keys and RU percentage. **Every new string is EN and RU.**
6. Release build if you touch a `#if DEBUG` seam (a test seed is one). Say which applies.

Verify by **exit code** (`echo $?`), and report the codes you observed.

## Report back

Every check with the **exit code you observed** and the observed counts; whether each test was **run
or only written**; whether you reused `ImportStation.station(for:)` or moved it, and why; what an
empty name and a duplicate name do; where the Garage add affordance lives; and anything you found
and did not fix.
