# RV.25 – a car added from the switcher never appears in Garage

Reported by the product owner: the new car shows in the top-left picker, then Garage lists only the
old one. **It reads as data loss and it is not** — the row is in the database; Garage is showing a
stale list.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`. **Do not run `git add` or `git commit`.**
**Do not touch `docs/TASKS.md`** — the orchestrator marks the row after verifying.

## The cause — TWO gaps, either of which alone reproduces it

Verified 2026-09-03. Fix **both**: a fix for one appears to work down one path and silently not the
other.

**(1) Garage never reloads.** `GarageView` has `.task { await load() }` and **nothing else** — no
`onChange`, no `toastCenter`. `.task` does not re-fire when a tab is switched back to. This codebase
already knows that: `ManualFillUpView` carries the comment *"a `.sheet` never re-triggers the
presenter's `.task` on iOS 26"*, and `HomeView` has **three** reload paths —
`.task`, `.onChange(of: carSelection.selectedID)` and `.onChange(of: toastCenter.revision)`.

**(2) Nothing raises a signal.** `AddVehicleView` saves with `repository.upsertVehicle(...)` and
**never calls `toastCenter.noteEntryChanged()`**, so no reload signal exists for anyone to hear.
Garage would not react even if it listened.

Home escapes the bug only by accident: it observes `carSelection.selectedID`, which the switcher
changes when it selects the newly added car.

## What to build

A reload signal on the car-add path, and an observer on Garage — mirroring what Home already does,
rather than inventing a second mechanism.

**Then audit the class, because this is a class and not an instance.** Other `.task`-only surfaces
with no change signal share the shape. **Check at least `TrendsView`, the Reminders list and the Car
switcher**, and **say in your report which are affected and which you fixed**. Do not silently
widen the change to unrelated screens — name them, fix the ones that are genuinely the same defect,
and list any you judged out of scope with the reason.

## Explicitly out of scope

- Any change to how a vehicle is saved, or to `AddVehicleView`'s form.
- Redesigning `ToastCenter` or introducing a new observation framework.
- The Garage row layout and its vitals.
- Any backend file.
- **RV.21's `TabRootHeader` just landed on all three tab roots** — you will be editing files it
  touched. Read its change first and build on it; do not revert or restructure the shared header.

## Read before writing

1. **`CLAUDE.md`** — hard rule 2 (stats are derived, never stored — a reload must recompute, not
   cache), rule 8 (nothing lost silently) and rule 14.
2. `docs/SCREENMAP.md` — the Garage node and the tab-root conventions.
3. `ios/App/Sources/Garage/GarageView.swift`, `ios/App/Sources/Home/HomeView.swift` (the three
   reload paths — the pattern to copy), `ios/App/Sources/Navigation/ToastCenter.swift`,
   `ios/App/Sources/AddVehicle/AddVehicleView.swift`.

## Tests

- `cd ios && swift test` — **1159 today; must not fall.**
- L4, and the shape of it decides whether the test is worth anything:
  **add a car, open Garage IN THE SAME SESSION, assert the new car is listed.**

**Vacuous-assertion traps, named — the first is the one that will catch you:**
- **A test that relaunches the app between the two steps passes against the bug**, because a cold
  start re-runs `.task`. It must be one continuous session.
- Asserting a car's *name* is present. Assert the **count rises** — a name assertion can pass on a
  seeded fixture that already contained it.
- Asserting `toastCenter.revision` incremented. That tests the counter, not the screen.

**Mutation-check both halves separately** and report both: remove the signal, and remove the
observer. Each alone must fail the test.

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    swiftlint lint ; echo "LINT=$?"          # from the repo ROOT
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "APPBUILD=$?"

**Judge by the exit code you echoed**, not by skimming. Zero lint **errors**; `file_length` at 700
is an error.

Match the process NAME (`pgrep -x xcodebuild`). **Never `pgrep -f` or `pkill -f`** on a build/test
pattern — an agent's brief is part of its command line, and on 2026-08-24 exactly that killed
another agent 48 minutes into its task.

"Failed to load the test bundle … executable couldn't be located" is contention, not a red — zero
tests executed. Re-run once.

## Screenshots

Only if a surface changed appearance. This fix changes *when* a list reloads, which a still frame
cannot show — **say none applies rather than fabricating one.**

## Report back

- Exit codes for build, swiftlint, app build, `swift test`, each UI suite — numbers, not prose.
- Test counts before/after; suites RUN; **both mutation results**.
- **Which other surfaces you audited, which were affected, and which you fixed** — with the reason
  for any you left.
- Files changed, doc sections extended, anything unfinished — named plainly.
