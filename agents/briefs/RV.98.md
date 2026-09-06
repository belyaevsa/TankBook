# RV.98 - a deleted car is promised to Recently deleted and must actually arrive there

## The defect, and it is bigger than the row says

The confirm alert says *"It moves to Recently deleted for 30 days, and so does every entry"*
(`ios/App/Sources/VehicleDetail/VehicleDetailView.swift:57-64`) and `performDelete` (`:333-346`)
calls `softDeleteVehicle` - a tombstone, correctly. Then the promise breaks in two places at once.
**Both are measured in the source; do not re-derive them.**

1. **The car is nowhere.** `RecentlyDeletedView.reload()`
   (`ios/App/Sources/RecentlyDeleted/RecentlyDeletedView.swift:346-364`) queries exactly
   `repository.deletedEntries()` and `repository.deletedReminders()`. **Nothing queries deleted
   vehicles.** The car is tombstoned, invisible and **unrestorable by any surface in the app** -
   hard rule 8 broken in the words the app says out loud, which is worse than silence.
2. **And the screen is flooded with the car's entries.** `softDeleteVehicle`
   (`ios/Sources/TankbookCore/Persistence/Repository.swift:69-79`) tombstones the vehicle **and
   every vehicle-scoped row at the same stamp**, and `deletedEntries()`
   (`ios/Sources/TankbookCore/Persistence/Repository+RecentlyDeleted.swift:15-42`) filters on
   `deletedAt != nil` with **no vehicle filter at all**. So deleting the owner's 500-entry car puts
   **500 individual entry rows** on Recently deleted, each with its own Restore pill - and they
   render **named after the deleted car**, because the screen's vehicle lookup falls back to
   `repository.vehicle(id:)` (`Repository.swift:105`), which does not filter tombstones. The user
   who deletes a car sees a wall of its entries and no car.
3. **Restoring one of those rows makes an orphan.** `restoreEntry` clears that entry's tombstone
   while the **vehicle stays tombstoned**, so the entry is live and belongs to a car that is not.
   Home, Trends and the Log all read `liveVehicles()`, so the row is live and reachable from
   nowhere.

**What is already right, and must not be rebuilt:**
- **`restoreVehicle` (`Repository.swift:82-95`) is correct and complete.** It restores the vehicle
  **and the rows that share the vehicle's `deletedAt` stamp**, while rows the user had deleted
  individually keep their own tombstones. The group-restore semantics this row needs already exist.
- **The purge is correct and answers the row's open question.** `purgeTombstones`
  (`Repository.swift:586-612`) deletes entry tombstones past the cutoff first, and deletes a vehicle
  tombstone only when **none of its rows are still live**. So a car and the entries that went down
  with it purge together at the 30-day boundary; the entries never outlive their vehicle, and a
  restored (live) row keeps its vehicle tombstone alive rather than being cascaded away. **State
  this in the doc as the answer - do not change the purge.**

## What to build

1. **A tombstoned car is a row on Recently deleted**, with the same 30-day countdown and the same
   Restore affordance the entry and reminder rows have. Add the repository query it needs
   (`deletedVehicles()`, alongside `deletedEntries()`/`deletedReminders()`, in
   `Repository+RecentlyDeleted.swift` - that file exists to keep `Repository.swift` under the lint
   ceiling, so put it there).
2. **Restore brings the whole car back** - the car and the entries tombstoned with it. That is
   decided, and it is what `restoreVehicle` already does; wire the row to it, do not write a new
   restore. Rows the user deleted individually **before** the car went stay deleted, which is also
   already correct.
3. **The car's co-tombstoned entries do not appear as separate rows.** This is the decision that
   fixes defect 2 and defect 3 together: an entry whose tombstone stamp matches its vehicle's came
   down **with the car** and comes back **with the car**, so it belongs under the car's row, never
   beside it with a Restore of its own that would strand it on a deleted vehicle. Entries the user
   deleted individually still list exactly as they do today. **Say how many entries the car's row
   covers** ("Volvo V60 and 512 entries" or the row's equivalent) - the count is derived, never
   stored (hard rule 2).
4. **Reuse the existing row shape.** `DeletedReminderRow`
   (`RecentlyDeletedView.swift:372+`) is the precedent: same card, title + countdown + Restore. Do
   not invent a new visual language and do not add a new colour - there is no separate artboard for
   a car row, and `design/screens/RecentlyDeleted.dc.html` is the authority for the screen's look.
5. **The empty-state and intro copy must stay true.** The intro says "Deleted entries stay here for
   30 days" (`:65-73`); once cars appear it is no longer only entries. Fix the copy, EN **and** RU,
   as a full localised phrase per language - never concatenation (hard rule 10; "%@ spend" composed
   as "%@ расходы" is the bug this rule exists for).

## Explicitly out of scope

- **The alert copy** (`RV.99` owns it). Do **not** weaken the promise to match the missing surface -
  the promise is right and the surface is what is missing.
- `RV.100` (Home rendering a deleted car). Different screen, different defect.
- Changing `softDeleteVehicle`, `restoreVehicle` or `purgeTombstones`. They are correct.
- The sync half (what a second device does with a car's tombstones). `RV.100` records it as an open
  question; do not guess it here.

## Tests

Read the current `swift test` count yourself before you start and report before -> after; other rows
land in parallel, so any number quoted in a brief is stale.

- **L1**: a tombstoned vehicle appears in the new query, with its deletion stamp and its days-left.
- **L1**: restoring it returns **the car AND the entries that went down with it** to live, while an
  entry deleted individually **before** the car stays tombstoned.
- **L1**: a car with entries produces **one** car row and **no separate rows** for the entries that
  share its stamp - assert the entry rows are absent, not merely that the car row is present.
- **L4 `RecentlyDeletedUITests`**: delete a car from Vehicle detail, open Recently deleted, the car
  is listed with its countdown; Restore returns it to the Garage **and its entries to the Log**.
- Suites: `RecentlyDeletedUITests`, plus `VehicleDetailUITests` if the delete path's own assertions
  move. Name the observed count - a filter matching nothing prints "0 tests ... passed".

### Vacuous traps, named

- **Asserting the tombstone exists in the database.** It already does - that is not the defect. The
  defect is that nothing shows it.
- **Testing with a car that has no entries.** That hides defect 2, defect 3 and the entire restore
  question - the fixture must have entries, and one entry deleted separately beforehand.
- Asserting the car row is present without asserting its **Restore actually restores**.
- Asserting a count of rows without asserting **which** rows: the flood is the bug, so the assertion
  must fail if the car's 500 entries are still listed individually.
- A fixture whose entry tombstones were all written by the same call as the car's, with none deleted
  individually - it cannot tell "came down with the car" from "deleted on its own", which is exactly
  the distinction the fix turns on.

### Mutations (run each, report, restore byte-for-byte)

1. Make the car's Restore call `restoreEntry`-style single-row restore instead of `restoreVehicle`
   (car back, entries still tombstoned) -> the group-restore test must fail.
2. List the car's co-tombstoned entries as their own rows again -> the no-flood test must fail.
3. Restore the individually-deleted entry too (ignore the stamp comparison) -> its test must fail.

**A mutation that PASSES is a finding** - say so and grow the test until it fails, rather than moving
on. Four mutations passed on 2026-09-06 and each meant the test did not cover the claim its row was
written for.

## Docs to reconcile

`docs/SCHEMA.md` (what deleting a car tombstones and what restoring it brings back; the purge
ordering answer above), `docs/SCREENMAP.md` (Recently deleted now lists cars), `docs/ERRORS.md` if
any empty-state or next-step copy changes.

## Hard rules that decide things in this area

**2** (the entry count on the car's row is derived, never stored) · **7** (every dead end names its
next step) · **8** (nothing lost silently - the whole row) · **10** (EN + RU through the String
Catalog, a full localised phrase per language) · **12** (never log a domain value - a car's name is
one; log ids and counts) · **14** (it builds and it lints before anything else counts).

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
