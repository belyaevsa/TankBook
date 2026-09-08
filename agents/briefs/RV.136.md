# RV.136 - one vehicle is pushed on every cycle, on an idle account

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** If a file is in your way or a test is
red that is not yours, report it and carry on.

## The symptom, from production

Device `787c4f6f`, build `1.0.0+857`, 2026-09-08 - three pushes in under three minutes on an
**idle** account:

```
07:25:40  push  vehicle                 Accepted  Conflicts=0  SCN 1339
07:27:33  push  vehicle + preferences   Accepted  Conflicts=0  SCN 1340-1341
07:28:06  push  vehicle                 Accepted  Conflicts=0  SCN 1342
```

The same id `01a07029-f166-72b2-b883-77eac7bb169e` is in **every** push, and the pull immediately
before each one returns that same row back to the device that wrote it. No data is lost - every
push is accepted, no conflict is raised - but `sync.push` stops meaning "something changed", and the
SCN churns forever.

**This has been "fixed" twice.** HANDOVER records it closed on 2026-09-03 ("the device was pushing
its own records back forever, on two paths"; one vehicle pushed 12 times in three hours on an idle
account). It is back on a later build. **A third fix that does not identify why the previous two did
not hold is not acceptable** - the row's own trap is "fixing one path and declaring it closed, which
is how this recurred".

## My hypothesis, pinned to lines - REPRODUCE IT BEFORE YOU CHANGE ANYTHING

The push is `Vehicle`-only, which matters: `Vehicle` is the one entity with **field-level merge**
(S9), and every other type goes through record-level LWW.

`SyncEngine.swift:318-322`, the `.fieldMerge` arm:

```swift
case .fieldMerge:
    // S9: the merged Vehicle is a new write - store it dirty so it pushes.
    let touched = try repository.applyRecord(result.keep, syncState: .dirty)
```

**Unconditionally dirty.** That is correct *if* `.fieldMerge` is only returned when something
actually merged. Whether it is depends entirely on the two equivalence guards in
`RecordMerge.mergeVehicle` (`RecordMerge.swift:99-107`):

```swift
if merged == remoteVehicle,
   mergedVersions == effectiveVersions(remoteVersions, fallback: remote.clientUpdatedAt) { ... }
if merged == localVehicle,
   mergedVersions == effectiveVersions(localVersions, fallback: local.clientUpdatedAt) { ... }
```

Both guards need the **decoded vehicle** AND the **field-version map** to match. The maps are built
differently on each side (`:76-83` vs `:185-191`):

- `mergedVersions[field] = max(localTime, remoteTime)`, per field, where a missing stamp falls back
  to that side's `clientUpdatedAt`;
- `effectiveVersions(side, fallback:)` fills every missing field with that **one** `clientUpdatedAt`.

**So when one side carries per-field stamps and the other does not, `mergedVersions` can equal
neither map even though `merged == remoteVehicle` byte for byte** - `max` picks the remote stamp for
fields the remote has stamped and the local fallback for the rest, producing a third map. Both
guards fail, `.fieldMerge` is returned, the row is stored `.dirty`, it pushes, the server stores it,
the next pull hands it back, and the cycle repeats. Forever. Vehicle only. Accepted, `Conflicts=0`.

A local vehicle can plausibly lack stamps: the four production writers
(`AddVehicleView.swift:170`, `VehicleDetailView.swift:288`, `TankLevelView.swift:417`,
`ImportFlowModel+Wizard.swift:313,324`) all call `upsertVehicle`, whose `syncState` **defaults to
`.dirty`** (`Repository.swift:59`) - check what they do and do not write into the field-version map.

**This is a hypothesis, not a fact.** Reproduce the loop in a test against the CURRENT code and show
it fails before you change a line. If it does not reproduce, **say so and report what you found
instead** - four of the orchestrator's recent diagnoses were wrong and an agent caught every one.
Reporting a negative is a successful run; making the test match the brief is not.

## The other candidates the row names - rule them out with evidence, not reasoning

- A launch-time recompute writing the vehicle back. **Hard rule 2 says stats are derived and never
  stored**, so a stats pass that touches the row is itself the bug.
- `lastKnownOdometer`, or a units/currency default, being re-derived and re-saved on foreground.
- The pull applying the device's own row with the wrong `syncState` on a path other than
  `.fieldMerge` - note `SyncEngine.swift:313-316` already guards the record-level path with
  `recordsEqual` (RV.35's fix), and that guard's absence on the Vehicle path is the asymmetry this
  brief is about.

Name, for each, whether it is possible or impossible **and the line that settles it**.

## What to build

**1. `.fieldMerge` must not re-dirty a row that did not change.** Whether the fix belongs in the
guards (make the version-map comparison express "no local change" correctly) or at the call site
(do not store `.dirty` when the merged record is equivalent to what the server just sent), **choose
one, say why, and make sure S9 still holds**: a genuinely merged Vehicle - one where the local side
really did win a field - must still be stored dirty and must still push. Breaking that loses a local
edit, which is hard rule 8.

**2. Say why the 2026-09-03 fixes did not cover this.** One paragraph in your report. If the answer
is that they fixed the record-level path and never the field-merge path, say that plainly - it is
the most useful sentence in the run.

**3. Shape-only observability, if it is cheap.** `docs/LOGGING.md` permits shape. A line recording
that a pull re-dirtied a row (entity type and a count, never a field value - hard rule 12) would
have made this diagnosable from one session's log instead of three builds. Add the row to
`docs/LOGGING.md` in the same change if you add the line.

## Explicitly out of scope

- The push batching and timeouts ([RV.97], already fixed).
- [RV.143] (a home-currency change arriving by sync must re-home entries) - you will be reading the
  same merge code. Do not fix it here; it has its own row.
- Changing the S9 field-merge policy itself, or which fields are merge-tracked.
- The `preferences` record in the 07:27:33 push, unless your evidence shows the same cause.

## Docs to read before writing (in order)

1. `docs/SYNC.md` -> S9 and the payload contract - **the authority for this task**.
2. `docs/API.md` -> sync push/pull, for what an SCN means.
3. `docs/LOGGING.md` if you add a line; `CLAUDE.md` hard rules 2, 8, 12.

## Checks

Baseline on `main` as left: **1675 tests / 187 suites**, **777** localization keys at 100% RU,
`swift build` 0, `swiftlint lint` 0 errors **from the repo ROOT**. **Re-measure yourself and report
what you observe** - do not copy these numbers into your report.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0.
3. `cd ios && swift test` - full, never subsetted; report the count.
4. UI suites: **none expected** - this is core sync. If you touch `ios/App/Sources`, name the suite
   you ran and its observed count, and check the count is non-zero (a filter matching nothing prints
   "0 tests ... passed" and still exits 0).
5. Localization gate - exit 0; report the key count.
6. Release build - only if you touch a `#if DEBUG` seam. Say which applies.

Verify by **exit code** (`echo $?`), not by skimming output, and report the codes you observed.

### Tests you must add

- **L3, the row's whole point**: an idle account across **two** foreground cycles pushes **zero**
  records. Assert the transport's **push count**, not the absence of an error. One cycle cannot show
  this - the loop needs the second to appear.
- **L1**: applying a pulled row that is equivalent to the local one leaves it **CLEAN**. This test
  must **fail against the current code** - show that output.
- **L1, the guard against over-fixing**: a genuinely merged Vehicle, where a local field wins, is
  still stored **dirty** and still pushes (S9, hard rule 8).
- **L1**: the asymmetric-version-map case explicitly - one side with per-field stamps, one without,
  decoding to the same vehicle - resolves to "nothing to push".
- **L1**: whatever recompute runs at launch does not write the vehicle.

### Vacuous traps, named

- **Asserting the push succeeded** - it always did. `Accepted, Conflicts=0` is the symptom, not the
  health check.
- **Testing a single cycle**, when the loop needs two to show.
- **Fixing one path and declaring it closed** - this is the third occurrence; name why the previous
  two did not hold.
- Making `.fieldMerge` never dirty, which closes the loop by losing local edits (hard rule 8).
- Comparing raw payload **bytes** to decide equivalence - `RecordMerge.swift:128-139` explains why
  that does not converge across a lossy round-trip, and it is the mistake RV.35 already corrected.
- Logging a field value, a name, or anything but shape (hard rule 12).

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**.
Use `pgrep -x xcodebuild`. **Never `pkill -f`.**

## Report back

Whether the loop **reproduced**, with the failing-then-passing test output; every check with the
**exit code you observed**; whether each test was **run or only written**; which fix shape you chose
and why S9 still holds; **why the 2026-09-03 fixes did not cover this**; each of the other candidates
marked possible/impossible with the line that settles it; and anything you found and did not fix.

## Never stash, move or `git checkout` to get a "clean baseline"

To show a test fails before the fix: **write the test, run it against the unmodified code, then make
the change.** If the change is already written, prove the test's teeth with a **mutation** - revert
the one line the test is about, run it, restore the line.

**Do not** `git stash`, `git checkout`, or move files out of the tree to get a clean baseline. On
2026-09-08 an agent did exactly that and a bad `mv` loop destroyed three of its own new files; the
same loop would have taken a concurrent session's uncommitted work. Assume you are not alone in this
checkout.
