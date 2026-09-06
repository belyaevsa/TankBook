# RV.99 - deleting a car needs a confirmation the user actually sees, and it must name the car

## The row is a disagreement between a report and the source - resolve it on a DEVICE first

The product owner reported, 2026-09-06: *"a car deletion from a garage doesn't have a confirmation
of the action"*. **The source says otherwise, and that gap IS the row.** Measured, do not re-derive:

- `VehicleDetailView` presents `.alert("Delete this car?")` with a destructive **Delete** and a
  **Cancel** (`ios/App/Sources/VehicleDetail/VehicleDetailView.swift:57-64`).
- It is the **only** delete path in the app. The single affordance that raises it is the header's
  Delete button (`ios/App/Sources/VehicleDetail/VehicleDetailSections.swift:50-59`,
  `vehicleDetailDeleteButton`). **`GarageView` and `CarSwitcherView` contain no delete affordance at
  all** - grep them and confirm before you conclude anything.
- The archived car's header Delete (visible as `Удалить` in
  `design/screenshots/RV.81-vehicle-detail-archived-ru.png`) routes to the **same**
  `showDeleteConfirm`. That is source reading, not a device.

**So step one is a reproduction, and it is the deliverable of the first half of this run.** Boot the
simulator, seed a garage, and try to delete a car by every route a user has: the live car's Vehicle
detail, the archived car's Vehicle detail, and whatever the Garage and the car switcher offer.
**Report which path you took and exactly what appeared.** Three outcomes are all legitimate findings:

1. The alert never appeared on some path -> that is the defect; fix it.
2. The alert appeared but did not read as a confirmation -> say what it looked like and why.
3. The alert appeared and read correctly on every path -> **say so plainly.** The row is then about
   the naming half below, and "the report did not reproduce" is a real result, not a failure. Do not
   invent a defect to justify the row, and do not quietly assume the owner was wrong either.

**A likely contributor whichever way it goes: the alert never names the car.** In a five-car garage
"Delete this car?" does not say which, and the title is identical whichever row you arrived from -
so a user who is not certain what they are looking at gets no confirmation that they are deleting
the car they meant.

## What to build

1. **Whatever the reproduction shows, name the car in the confirmation**: "Delete Volvo V60?" rather
   than "Delete this car?". A destructive action states its target.
2. **Check the RU form declines correctly.** This is not a formality: the car name is
   user-typed and drops into a Russian sentence. Read the rendered Russian for grammar and word
   order, not just overflow, and use a **full localised phrase per language** - never a concatenation
   of "Delete" + name (hard rule 10; `"%@ spend"` composed as `"%@ расходы"` rendered "АВГУСТ
   РАСХОДЫ", which is the bug this rule exists for). A long name must not push the alert's buttons
   off screen - check a 30-character name in RU.
3. **Fix whatever the reproduction found**, if it found anything.

## The copy fence, and it decides what the message may say

The alert's message currently promises *"It moves to Recently deleted for 30 days, and so does every
entry."* **That promise is false until [RV.98] lands** - `RecentlyDeletedView` does not list deleted
cars at all, so the car is tombstoned, invisible and unrestorable.

- **If RV.98 has already landed** (check `git log` for it, and check that
  `RecentlyDeletedView` queries deleted vehicles - do not take my word for the state of the tree):
  keep the promise, it is now true.
- **If RV.98 has NOT landed**: the message **must not promise a restore the app cannot perform**
  (hard rule 7 - every error and every dead end names a next step that is real). Say what actually
  happens instead, and **report that you changed it and why**, so the orchestrator can put the
  promise back with RV.98.

Do not "fix" this by making RV.98's surface yourself - that is a different row with its own brief.

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
- **L4**: the **archived** car path asserts the same. The owner may well have been on it.
- **L1** for whatever pure piece the title composition ends up in (the localised phrase), if any.
- Suites: name them explicitly and report the observed count - a filter matching nothing prints
  "0 tests ... passed".

### Vacuous traps, named

- **Asserting the alert exists in the source rather than on a device.** That is precisely what makes
  this row ambiguous today, and repeating it delivers nothing.
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
