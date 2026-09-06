# RV.100 - delete every car and Home still renders one

## The defect, pinned to two lines

Reported by the product owner 2026-09-06. `HomeView.load()` resolves the selection and, when there
is none, **returns without clearing what it already loaded**
(`ios/App/Sources/Home/HomeView.swift:460-462`):

```swift
guard let selected = carSelection.selectedVehicle(vehicles) else {
    return
}
```

`vehicles` is correctly set to empty on the line above (`:455-456`) and `VehicleSelection.resolve`
correctly answers nil. **The bug is that `vehicle`, `entries`, `stations`, `reminders`, `photoData`
and every derived tile keep their previous `@State`** (declared `:23-35`), so Home goes on rendering
a car that no longer exists: its name, its odometer, its consumption, its log rows, its month spend.

**Why it is worse than a stale screen**: every tile is derived (hard rule 2), so the user is looking
at statistics computed from **deleted** data - and the one screen that should now say "add your first
car" instead invites an entry against a car that is gone. An entry saved there would target a
tombstoned vehicle.

**The correct shape already exists in the codebase** - do not invent one:
- `RemindersView.refresh()` (`ios/App/Sources/Reminders/RemindersView.swift:377-381`) clears
  `rows = []` and `vehicle = nil` **before** returning.
- `TireSetsView.reload()` (`ios/App/Sources/TireSets/TireSetsView.swift:144-150`) clears four
  properties before returning.

**The zero-car surface also already exists**: `homeAddFirstCarButton`
(`ios/App/Sources/Home/HomeEmptyStates.swift:82`), covered for a fresh install by
`testNoCarYetRoutesToAddCar` (`ios/App/UITests/HomeUITests.swift:62`). This row is the **same state
reached by deletion**, which is a different path and passes today.

## I have already done the sibling audit - use it, do not repeat it

Every screen that resolves the shared selection, and what it does when the answer is nil:

| Screen | Line | Verdict |
|---|---|---|
| `HomeView.load` | `:460` | **Bare `return` - the defect** |
| `TrendsView.load` | `:180-182` | **Bare `return` - the SAME defect**, keeps `vehicle` and `entries` |
| `RemindersView.refresh` | `:377-381` | Correct - clears first |
| `TireSetsView.reload` | `:144-150` | Correct - clears first |
| `GarageView` / `CarSwitcherView` | `:370` / `:314` | Read `selectedVehicle(vehicles)?.id` into an optional; no retained derived state |
| The form screens (`ManualFillUpView:312`, `ServiceEntryView:252`, `ExpenseEntryView:284`, `TireSetFormView:109`, `PartsShelfView:68`, `EditEntryView+EntryResolution:58`) | - | Guard-and-return on a **presentation** path, not a dashboard holding derived tiles |

**Fix Home and Trends.** They are the two screens that hold derived state across a load. Leave the
rest alone and say in the report that you did.

## What to build

1. **Clear the derived state when the selection resolves to nothing**, in `HomeView` and in
   `TrendsView`, in the shape `RemindersView` already uses.
2. **Land on the real zero-car surface** the app already has - the Add-car path, not a blank screen
   and not an empty dashboard.
3. **The sync half is an OPEN QUESTION and must be answered, not guessed.** The product owner asked
   what happens when a device tombstones its last car: those tombstones push, and a second device
   must not resurrect the car or keep showing it. **Establish what happens today** by reading
   `SyncEngine`'s apply path and the S1-S8 scenarios in `docs/SYNC.md`, and **write the answer into
   `docs/SYNC.md`** - including whether the empty-garage state survives a pull. If the honest answer
   is "the second device keeps rendering it for the same reason Home did", say that and register it
   rather than fixing a second screen's worth of sync behaviour inside this row. **Do not write a
   guess as if it were established.**

## Explicitly out of scope

- `RV.98` (the car reaching Recently deleted) and `RV.99` (the confirmation).
- Fixing the form screens or the Garage/switcher rows listed as correct above.
- Changing `VehicleSelection.resolve` or `AppCarSelection` - both answer correctly today; the callers
  ignore the answer.

## Tests

Read the current `swift test` count yourself before you start and report before -> after.

- **L1**: the Home model with an empty vehicle list exposes **no vehicle and no entries** - whatever
  pure seam exists for it. If Home's state is only reachable through the view, say so and cover it at
  L4 rather than inventing a model layer for the test's benefit.
- **L4 `HomeUITests`**: with **one seeded car**, delete it, and Home shows the **zero-car state** -
  assert `homeAddFirstCarButton` is **present** AND the deleted car's name and odometer are
  **absent**. Both halves, or the test is vacuous.
- **L4**: the same for Trends - deleting the last car must not leave its chart and totals on screen.
- Suites: `HomeUITests`, `TrendsUITests`. Report the observed count - a filter matching nothing
  prints "0 tests ... passed".

### Vacuous traps, named

- **Asserting the Garage is empty.** It already is - the defect is on Home.
- **Testing a fresh install rather than a deletion.** That is a different path and **passes today**,
  so such a test proves nothing about this row.
- **Asserting the car name is absent without asserting the zero-car surface is PRESENT** - a blank
  screen would pass that and is not the fix.
- Asserting `vehicles.isEmpty` - that was already true before the fix; the retained `vehicle` is
  the bug.

### Mutations (run each, report, restore byte-for-byte)

1. Restore the bare `return` in `HomeView` -> the Home zero-car test must fail.
2. Restore the bare `return` in `TrendsView` -> the Trends test must fail.
3. Clear `vehicle` but leave `entries` populated -> a test must fail. If none does, the assertion is
   only about the header and the log rows are untested - **that is a finding**; grow it.

**A mutation that PASSES is a finding** - say so rather than moving on.

## Screenshots

EN **and** RU, **dark**, into `design/screenshots/`, named `RV.100-home-zero-car.png` and `-ru.png`,
showing Home **after** deleting the last car (not a fresh install).
- Capture **outside** a test run; pass `-homeResetDatabase` with any seed (seeds are idempotent and
  silently do nothing on a populated database).
- RU: `xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU`.
- **Verify the pair differs with `md5 -q`** and report both hashes.
- You cannot see your own screenshots; the orchestrator opens every one.

## Docs to reconcile

`docs/SYNC.md` (the last-car tombstone answer above - the deliverable, not an optional extra),
`docs/SCREENMAP.md` if the zero-car route changes, `docs/JOURNEYS.md` if J1's empty state does.

## Hard rules that decide things in this area

**1** (no screen is ever sync-gated) · **2** (stats are derived - which is why rendering them from
deleted data is the harm here) · **7** (the zero-car screen names its next step: add a car) ·
**8** (nothing lost silently) · **10** (EN + RU, full localised phrase) · **14** (it builds and it
lints before anything else counts).

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`, and within it only:
`ios/Sources/TankbookCore/**`, `ios/App/Sources/**`, `ios/Tests/**`, `ios/App/UITests/**`, the docs
named in this brief, and `design/screenshots/**`.

**Never move, rename or delete a file you did not create.** Another session may be working in this
checkout. Expect files, and even a red test, that are not yours: **report them and carry on** - never
"clean the baseline".
Do NOT tick anything in `docs/TASKS.md` - the orchestrator ticks at merge. Do NOT commit.
No `git add -A`, `git checkout`, `git stash`, `git clean`.

## Write code first, explore second

The dominant failure mode is a run that reads everything and writes nothing. The cause is pinned to
lines above and is confirmed - do not spend the run re-deriving it. Where this brief leaves a
genuinely open choice, **take the smallest correct option and keep going**, then say in the report
which you took and what you rejected. Do not stop and wait on it. (`RV.74`'s first dispatch ran two
hours and wrote nothing, stuck on a question its brief left open.)

If a fence in this brief turns out to be wrong, **report it as a Residual rather than obeying
quietly** - a fence can be wrong the same way a diagnosis can.

## The baseline gate (CLAUDE.md rule 14)

From the **repo ROOT**, judged by exit code (`echo $?`), never by skimming output:
- `cd ios && swift build` -> 0
- `cd ios && swift test` -> 0, count reported (before -> after). Never subset it.
- `swiftlint lint` **from the repo root** -> 0 errors. From `ios/` it prints thousands of phantom
  violations; that false red has cost two sessions.
- `swift run --package-path ios localization-gate` from the root -> 0.
- `xcodebuild -project Tankbook.xcodeproj -scheme Tankbook -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:<the suites this brief names> test` -> 0.
  `swift build` does NOT compile `ios/App`; only `xcodebuild` does. Run `xcodegen generate` first if
  you added a file. **Check the observed count is non-zero.** Do NOT run the whole UI suite - that
  belongs to phase completion (2026-08-29 rule).
- **`$?` after a pipe is the pipe's exit code.** `dotnet test | tail` once reported 0 while the run
  aborted. Never judge a run by `... | tail`.
- **Never `pgrep -f` for a build** - your own brief is in your command line and you will match, and
  could kill, a sibling agent. Use `pgrep -x xcodebuild`.
- **Simulator contention produces false reds** with a *different* failing set each run, and a suite
  reporting "Executed 0 tests" beside its failures is kills, not assertions. Shut the simulators down
  and re-run once on a quiet machine before believing a red.

## Report back

1. Exit code of every gate, and observed test counts (before -> after).
2. Each mutation: what you broke, which named test failed, and that you restored it byte-for-byte.
   **A mutation that PASSES is a finding** - say so rather than moving on.
3. Screenshot paths and md5s, if this brief asked for screenshots.
4. What the user can now do that they could not before. If the honest answer for some case is
   "nothing changed", say so.
5. Anything in this brief that was wrong, as a Residual.
6. Whether the tests were actually **run**, not only written.
