# RV.150 - the save writes the station fields the suggestion ranks by

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** If a file is in your way or a test is
red that is not yours, report it and carry on.

## The defect

[PJ.19] shipped the 4-rung station ranking - nearest favourite, nearest known, the car's own most
recent, region - and it works. But **the save path writes none of the fields rungs 1 and 2 read.**

`ManualFillUpView.swift:646` sets `stationId` on the FILL-UP and never touches the `Station` row:
`lastUsedAt` stays nil, `defaults` stays whatever it was, and a station with no `location` never
gains one. Those fields are populated today only by an **import or a test seed**, so a user who
types every entry by hand builds a station list the ranking cannot order, and the feature quietly
degrades to rung 3 forever. PJ.19's agent found this and documented it as deliberately out of its
fence.

`Station` (`ios/Sources/TankbookCore/Domain/Entities.swift:445-483`) carries `location:
GeoCoordinate?`, `favorite: Bool`, `defaults: Defaults` (`fuelKind`, `fuelGrade`) and `lastUsedAt:
Date?`.

## The product decision, made 2026-09-09 - implement it, do not re-open it

**A save stamps the station, and a station with no location adopts the forecourt fix that PJ.19
already read - without asking, and without interrupting the save.** The product owner chose this
over prompting and over dropping the distance rungs. Do not add a confirmation, a toast, or a
first-time explainer at capture time.

**"Silently" means no prompt at the moment of capture. It does not mean invisible or permanent**, and
these four properties are part of the decision, not a softening of it:

1. **Visible and editable afterwards.** The station's location must be inspectable and changeable
   where per-station settings live (the Garage), and clearable. Hard rule 13's second half is
   explicit that a derived value must be editable *"again afterwards"*, and a coordinate the user can
   neither see nor remove would be the one derived value in the app that they cannot.
2. **Never overwrite a location a station already has.** Fill-blanks-only, exactly like the rate
   backfill. A user's own correction is theirs permanently (`docs/SYNC.md` -> Reference data).
3. **Documented, not hidden.** `docs/SECURITY.md` must say the app stores a coordinate per station,
   when it is captured and how it is removed; `docs/SCHEMA.md` -> Station must say the save writes
   it. A stored coordinate that no doc mentions is the thing that turns a product decision into a
   surprise.
4. **Never logged** (hard rule 12): a coordinate is a domain value. Not at any level, not in any
   build. Add a source-scan gate the way [PJ.19] did for its ranking.

If you conclude any of these four cannot hold, **stop and report** rather than shipping the capture
without them.

## What to build

- **`lastUsedAt`** stamped on the station the user confirmed, at save.
- **`defaults`** updated with what was actually bought there (the fuel kind, and the grade when there
  is one), so the last-visit default the ranking applies is real rather than derived.
- **`location`** adopted from the forecourt fix PJ.19 already read, **only when the station has
  none**, and only when a fix was actually available (no permission, no fix -> nothing happens, and
  that is a non-event, not an error - hard rule 1).
- All three ride the ordinary `.dirty` sync path like any other station edit; nothing new is needed
  for sync, but **check the S9/field-merge behaviour** for `Station` and say what you found. [RV.136]
  is the cautionary tale: a field written on every save is exactly the shape that produced an echo
  loop, so make sure a save that changes nothing writes nothing.

**Reuse PJ.19's reader.** `ForecourtLocationReader` already performs one bounded read per Confirm;
this row must not add a second read, a second permission ask, or a background fix.

## Explicitly out of scope

- The ranking itself ([PJ.19], shipped) and its rungs.
- Station creation, renaming, merging, and brand normalisation ([RV.115]).
- Any new permission prompt, and any background or continuous location.

## Docs to read before writing (in order)

1. `docs/SCHEMA.md` -> Station - **the authority, and extend it**.
2. `docs/SECURITY.md` - **extend it** with the stored coordinate, per property 3 above.
3. `docs/SYNC.md` -> Reference data (a user's own value is theirs permanently) and S9.
4. `docs/JOURNEYS.md` -> J4, where PJ.19 recorded this gap.
5. `CLAUDE.md` hard rules 1, 12, 13.

## UI suites to run

`TankbookUITests/ConfirmManualUITests`, `TankbookUITests/GarageUITests`, and whichever suite covers
the per-station settings you extend - **report its real name and observed count**.

## Tests you must add

- **L1**: a save stamps `lastUsedAt` on the chosen station, and changes nothing else about it.
- **L1**: the written `defaults.fuelKind` is the kind actually bought, not the one previously stored.
- **L1**: a station that **already has** a location is never overwritten by a later fix.
- **L1**: with no fix available, the save writes no location and does not fail.
- **L1, the point of the row**: after a save, the **ranking orders differently** - assert the ranking,
  not just the field. A test that asserts the field changed proves nothing about the feature.
- **L1**: nothing in the write path logs a coordinate (source-scan gate, as PJ.19 did).
- **L3**: two devices converge on the same station fields after a sync round, and a save that changes
  nothing produces no push ([RV.136]'s guard).
- **L4**: the station's location is visible and clearable in the Garage.

## Vacuous traps, named

- **Asserting the field changed without asserting the RANKING then orders differently** - the field
  is the mechanism, the ordering is the feature.
- A fixture whose stations came from a seed with `lastUsedAt`/`location` already populated - that is
  exactly the state that hides this defect today.
- Writing the location over one the station already has.
- Adding a second location read or a second permission ask.
- Stamping the station on every save regardless of change, which re-creates [RV.136]'s echo loop.
- Logging a coordinate, a station name, or a distance (hard rule 12).
- Shipping the capture without the Garage affordance that makes it removable.

## Screenshots

**EN and RU**, **dark**, outside any running test: the per-station settings showing a captured
location and the control that clears it. Commit as `design/screenshots/RV.150-station.png` and
`-ru.png`.
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

Re-measure the baseline yourself and report what you observe. As left, `main` was **1763 tests / 200
suites**, **799** localization keys at 100% RU.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0. From the root, **not** `ios/`.
3. `cd ios && swift test` - full, never subsetted; report the count.
4. `xcodegen generate`, then the UI suites above by name with observed, non-zero counts.
5. Localization gate - exit 0; report keys and RU percentage. **Every new string is EN and RU.**
6. Release build if you touch a `#if DEBUG` seam. Say which applies.

Verify by **exit code** (`echo $?`), and report the codes you observed.

## Report back

Every check with the exit code you observed and the observed counts; whether each test was **run or
only written**; the fail-then-pass or mutation evidence for the ranking test; what you found about
`Station`'s S9/field-merge behaviour and whether a no-op save pushes; where the Garage affordance
lives; and anything you found and did not fix.
