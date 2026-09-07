# RV.99 - deleting a car needs a confirmation the user actually sees, and it must name the car

## RESOLVED by the product owner, 2026-09-07: the confirmation EXISTS

The row was filed because the report ("a car deletion from a garage doesn't have a confirmation of
the action") and the source disagreed. **The product owner has now checked on their own device and
confirms the confirmation appears.** So the reproduction half of this row is CLOSED - do not spend
the run on it, and do not re-litigate it.

What the source shows, for context you can rely on without re-deriving:

- `VehicleDetailView` presents `.alert("Delete this car?")` with a destructive **Delete** and a
  **Cancel** (`ios/App/Sources/VehicleDetail/VehicleDetailView.swift:57-64`).
- It is the **only** delete path. The single affordance that raises it is the header's Delete button
  (`ios/App/Sources/VehicleDetail/VehicleDetailSections.swift:50-59`,
  `vehicleDetailDeleteButton`); `GarageView` and `CarSwitcherView` have no delete affordance.
- The archived car's header Delete routes to the same `showDeleteConfirm`.

**So this row is now exactly one defect: the alert never names the car.** "Delete this car?" is
identical whichever row you arrived from, and in a five-car garage it does not say which car is
about to go. That is what makes a destructive confirmation weak even when it appears - and it is the
likely reason the original report was filed at all.

## What to build

1. **Name the car in the confirmation**: "Delete Volvo V60?" rather than "Delete this car?". A
   destructive action states its target. This is the row.
2. **Check the RU form declines correctly.** This is not a formality: the car name is
   user-typed and drops into a Russian sentence. Read the rendered Russian for grammar and word
   order, not just overflow, and use a **full localised phrase per language** - never a concatenation
   of "Delete" + name (hard rule 10; `"%@ spend"` composed as `"%@ расходы"` rendered "АВГУСТ
   РАСХОДЫ", which is the bug this rule exists for). A long name must not push the alert's buttons
   off screen - check a 30-character name in RU.
3. **Fix whatever the reproduction found**, if it found anything.

## The copy fence is now SETTLED - the promise is true

The alert's message promises *"It moves to Recently deleted for 30 days, and so does every entry."*
**`RV.98` has landed** (commit `dbd93bd`): a tombstoned car is listed on Recently deleted as one row
naming the car and its entry count, with a Restore that returns the car **and** the rows that went
down with it. So **keep the promise exactly as it is** - it is now true, and hard rule 7 is
satisfied. Do not weaken it, and do not re-check whether RV.98 landed; it did.

If your naming change makes the message read awkwardly beside the new title, adjust the MESSAGE for
readability only - never the promise it makes.

## Explicitly out of scope

- Building the Recently deleted car row (`RV.98`).
- `RV.100` (Home rendering a deleted car after the last one goes).
- Adding a delete affordance to the Garage or the car switcher. If the reproduction shows a user
  expects one there, **report it as a finding** - do not build it.
- Changing what delete DOES (`softDeleteVehicle` is correct).

## Tests

Read the current `swift test` count yourself before you start and report before -> after.

- **L4 `VehicleDetailUITests`** (and `GarageUITests` if a Garage path exists at all): deleting a car
  requires an explicit confirmation **whose text contains that car's name**, and **Cancel leaves the
  garage untouched** - assert the car is still there afterwards, not merely that the alert dismissed.
- **L4**: the **archived** car path asserts the same - it routes to the same `showDeleteConfirm`, so
  it must name its car too.
- **L1** for whatever pure piece the title composition ends up in (the localised phrase), if any.
- Suites: name them explicitly and report the observed count - a filter matching nothing prints
  "0 tests ... passed".

### Vacuous traps, named

- **Asserting the alert merely EXISTS.** It does, on every path - the owner confirmed it. A test
  that only proves the alert appears re-proves what is already known and covers nothing this row is
  about.
- **Asserting the title string without asserting the car NAME is in it.**
- **Testing only the live-car path** when the report may be about the archived one.
- Asserting Cancel dismissed the alert without asserting the car **survived**.
- A fixture with one car, where "does it name the right car" cannot fail. Seed at least two.

### Mutations (run each, report, restore byte-for-byte)

1. Revert the title to the car-less "Delete this car?" -> the naming test must fail.
2. Make Cancel fall through to the delete -> the Cancel test must fail.

**A mutation that PASSES is a finding** - say so rather than moving on.

## Screenshots

EN **and** RU, **dark**, into `design/screenshots/`, named `RV.99-vehicle-detail-delete-confirm.png`
and `-ru.png`, showing the confirmation with the car named.
- Capture **outside** a test run - `simctl` and `xcodebuild test` fight over the device.
- RU: `xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU`.
- **Verify the EN/RU pair differs: `md5 -q a.png b.png`**, and report both hashes. RV.58 shipped an
  "RU" shot byte-identical to its EN one and could not tell.
- Seeds are idempotent and silently do nothing on a populated database - pass `-homeResetDatabase`
  alongside any seed.
- **You cannot see your own screenshots.** The orchestrator opens every one; do not claim they look
  right.

## Hard rules that decide things in this area

**5** (red lives only inside system dialogs - this alert is one of the few places it belongs) ·
**7** (every dead end names a next step that is REAL - the copy fence above) · **8** (nothing lost
silently) · **10** (EN + RU, full localised phrase, never concatenation) · **12** (never log a domain
value - a car's name is one) · **14** (it builds and it lints before anything else counts).

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
