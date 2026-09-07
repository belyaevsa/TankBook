# RV.101 - the delete cascade resurrects the car it just deleted (S5a)

## The defect, established and written up already - do not re-derive it

`docs/SYNC.md` -> **S5a** carries the full analysis, produced by the [RV.100] agent from
`SyncEngine.applyPull` + `Repository+Sync.apply` and **verified with a deterministic L1 scenario**.
Read that section first; this brief pins the code.

Deleting a car tombstones the vehicle **and every vehicle-scoped row at one stamp**, and
`fetchDirtyRows` pushes in registry order, so the **vehicle tombstone reaches the server first and
its cascade follows**. On the second device:

1. the vehicle tombstone applies cleanly - `resurrectReferencedVehicles` returns immediately for
   `entityType == Vehicle` (`ios/Sources/TankbookCore/Sync/SyncEngine.swift:328-333`);
2. then the cascade arrives, and for **every** co-tombstoned entry and reminder
   `applyPull` calls `resurrectReferencedVehicles` (`:269`, `:293`), whose only guard is
   `entityType != Vehicle` - **it does not look at whether the pulled record is itself a
   tombstone** - so `repository.resurrectArchivedIfTombstoned(vehicleId:)` brings the car back as
   **archived** and marks it dirty;
3. the resurrected car is dirty, so device B **pushes it back** with a newer `updatedAt`, the
   server tombstone is overwritten, and device A pulls its own deleted car back.

**The deletion sticks on neither device**, and both land in S5's "came back from another device - it
stays archived" state although nobody logged anything after the delete.

## What to build

**Skip resurrection for a pulled record that is itself tombstoned.** The cascade must not resurrect
its own victim. `SyncPullRecord` carries `deleted`; the decision belongs where the guard already is.

**S5 must keep working exactly as it does.** It exists for the real case: device B logged a **new,
live** entry to a car that device A deleted, and that entry must bring the car back as archived with
its Garage banner ("Volvo V60 came back from another device with 1 new entry - it stays archived.
Delete again?"). That is `docs/SYNC.md` S5 and it is correct. **A fix that silences S5 is a
regression, not a fix** - it would lose an entry's car and strand the entry, which is hard rule 8.

**Do not** solve it by ordering the push stream, by making the client re-delete, or by having the
device ignore its own echo. An echo that self-corrects is still an echo, and a device that re-pushes
a delete every cycle is [RV.97]'s shape again - which this project has already paid for once.

## Explicitly out of scope

- The Home/Trends rendering half ([RV.100], shipped): the screens already clear correctly.
- Changing `softDeleteVehicle`, `restoreVehicle`, `purgeTombstones` or the push order.
- The Recently deleted surface ([RV.98], shipped).
- Server changes of any kind - the server stores opaque records and this is entirely client-side
  (hard rule 9).

## Tests

Read the current `swift test` count yourself before you start and report before -> after.

- **L1, the fix**: applying a pulled **tombstoned** entry that references a locally-tombstoned
  vehicle leaves the vehicle **tombstoned and NOT dirty**. Assert both - a dirty tombstone still
  echoes, so `deletedAt` alone is not the assertion.
- **L1, the case that must not regress**: applying a pulled **live** entry that references a
  locally-tombstoned vehicle still resurrects it **as archived**, still marks it dirty, and still
  produces whatever S5 surfaces today.
- **L2/L1 scenario**: the full round trip - device A deletes its last car, device B pulls the
  vehicle tombstone **and** the cascade, and the car stays gone on B; B pushes nothing back; A does
  not get it back. The [RV.100] agent wrote and deleted a throwaway version of exactly this - write
  the keeping version.
- Suites: whichever core sync suite owns `applyPull`. No UI suite is required; say so if you agree.

### Vacuous traps, named

- **Testing only the tombstoned-entry case**, which lets a fix that breaks S5 pass green.
- **Asserting `deletedAt` without asserting the row is not dirty** - the echo is driven by the dirty
  flag, not by the tombstone.
- A fixture whose car has **no entries**, where the cascade this row is about does not exist.
- Asserting the guard's source rather than the behaviour of applying a pulled record.

### Mutations (run each, report, restore byte-for-byte)

1. Remove the new tombstoned-record condition -> the S5a test must fail.
2. Skip resurrection for **every** non-vehicle record (over-fix) -> the S5 live-entry test must fail.

**A mutation that PASSES is a finding** - say so and grow the test until it fails.

## Docs to reconcile

`docs/SYNC.md` - S5a already describes the defect and names this fix as its own row; update it to
record what shipped, and keep S5 intact beside it.

## Hard rules that decide things in this area

**8** (nothing lost silently - which is why S5 must survive: an entry whose car vanished is lost) ·
**9** (no server change; the client owns merge semantics) · **12** (log shape only) · **14**.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`, and within it only:
`ios/Sources/**`, `ios/App/Sources/**`, `ios/Tests/**`, `ios/App/UITests/**`, `backend/src/**`,
`backend/tests/**`, `design/screenshots/**`, and the docs named in this brief. **If your row's "out
of scope" says not to touch a tier, that fence wins over this list.**

**Never move, rename or delete a file you did not create.** Another session may be working in this
checkout. Expect files, and even a red test, that are not yours: **report them and carry on** - never
"clean the baseline".
Do NOT tick anything in `docs/TASKS.md` - the orchestrator ticks at merge. Do NOT commit.
No `git add -A`, `git checkout`, `git stash`, `git clean`.

## Write code first, explore second

The dominant failure mode is a run that reads everything and writes nothing. The cause is pinned to
lines above. Where this brief leaves a genuinely open choice, **take the smallest correct option and
keep going**, then say which you took and what you rejected. Do not stop and wait on it.

**My diagnosis can be wrong** - it has been several times this month, and the agent was right every
time. If what you measure does not match what this brief claims, **say so and report the
measurement**; that beats a fix built on a wrong premise.

## The baseline gate (CLAUDE.md rule 14)

From the **repo ROOT**, judged by exit code (`echo $?`), never by skimming output:
- `cd ios && swift build` -> 0; `cd ios && swift test` -> 0, count reported (before -> after). Never
  subset it.
- `swiftlint lint` **from the repo root** -> 0 errors. From `ios/` it prints thousands of phantom
  violations; that false red has cost two sessions.
- `swift run --package-path ios localization-gate` from the root -> 0.
- **If you touched `backend/`**: `dotnet build` -> 0, `dotnet test` -> 0 (count before -> after),
  `dotnet format --verify-no-changes` -> 0.
- **If you touched `ios/App/`**: `xcodebuild -project Tankbook.xcodeproj -scheme Tankbook -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:<the suites this brief names> test` -> 0.
  Run `xcodegen generate` first if you added a file. **Check the observed count is non-zero.**
- **A change touching a `#if DEBUG` seam also builds RELEASE**
  (`xcodebuild -configuration Release ... build`).
- **`$?` after a pipe is the pipe's exit code.** Never judge a run by `... | tail`.
- **Never `pgrep -f` for a build** - your own brief is in your command line and you will match, and
  could kill, a sibling agent. Use `pgrep -x xcodebuild`.
- **Watch the file-length ceiling**: several files sit at 699-700 lines and the lint error is a hard
  700. If your change pushes one over, split it the way the codebase already does (`+Wizard`,
  `+Cars`, `L10n+…`), never by deleting comments.

## Report back

1. Exit code of every gate, and observed test counts (before -> after), per tier you touched.
2. The measurement this row asked for, in numbers.
3. Each mutation: what you broke, which named test failed, that you restored it byte-for-byte.
   **A mutation that PASSES is a finding** - say so rather than moving on.
4. Screenshot paths and md5s, if this brief asked for screenshots.
5. What the user can now do that they could not before. If the honest answer for some case is
   "nothing changed", say so.
6. Anything in this brief that was wrong, as a Residual.
7. Whether the tests were actually **run**, not only written.
