# RV.136 (REOPENED) - the vehicle echo loop, third arm

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** If a file is in your way or a test is
red that is not yours, report it and carry on.

## Read this first: two fixes already shipped for this row and neither closed it

- **[RV.35]** fixed the record-level echo: re-dirtying on raw payload bytes, which do not converge
  across a lossy round-trip.
- **RV.136's first fix** (`85ba6d5`, 2026-09-09) corrected the `.fieldMerge` arm - `mergeVehicle`
  judged "did anything change" on the decoded Vehicle **and** the per-field version map, so an
  asymmetric map made a content-identical merge look like a new write.

Both were real and both are correct. **The loop is still happening**, and the cause is a third arm.

## The cause, pinned to a missing `case`

`RecordMerge.recordsEqual` (`ios/Sources/TankbookCore/Sync/RecordMerge.swift:143-160`) switches over
the synced entity types:

```swift
case FillUp, ChargeSession, ServiceRecord, Expense, Reminder,
     Station, Tariff, TireSet, Attachment, Preferences   // ← every entity but one
default:
    // "An entity type this build does not understand has no typed decode
    //  to reason at; the record is opaque, so bytes are the honest comparison."
    return local.payload == remote.payload
}
```

**`Vehicle` has no case.** So a Vehicle reaches `default:` and is compared **by raw payload bytes** -
which is exactly what the comment at the call site says was the bug:

`SyncEngine.swift:313-318`:
```swift
// RV.35: "differs" is judged at the decoded level (`RecordMerge.recordsEqual`),
// never the raw payload bytes, which do not converge across a lossy
// round-trip - re-dirtying on those bytes was the echo loop.
if !RecordMerge.recordsEqual(local.record, remote.asRecord())
    || local.record.deleted != remote.deleted {
    try repository.markDirty(id: remote.id, entityType: remote.entityType)
    tally.dirtiedByPull += 1
}
```

So RV.35 fixed the echo for every entity **except the one that was looping**, and RV.136's first fix
corrected a different arm on the assumption this one was covered.

## The evidence, on a build that contains both previous fixes

Server log, `clientVersion=1.0.0+925` (= commit `c92bb67`, which is after `85ba6d5`). The same
vehicle `01a07029-f166-72b2-b883-77eac7bb169e` is in **every push of the session** - 08:04:38,
08:07:46, 08:10:16, 08:34:05, 08:35:20, 08:56:01 - and is the **only** record in two of them, each
consuming an SCN.

Device diagnostics from the same session:
```
08:56:01 sync.merge recordsApplied=1 dirtiedByPull=1
```
`dirtiedByPull` is the counter RV.136's first fix ADDED. It is now catching the loop that fix did
not close, which is the counter doing its job.

**Confirm this before you build on it.** Reproduce it in a test first: two Vehicle records that
decode equal but whose payload bytes differ (a re-encoded number, a reordered key, a date without
fractional seconds - `RecordMerge.swift:128-139` lists the real cases) must currently report
`recordsEqual == false`.

## What to build

1. **Add the `Vehicle` case** so a Vehicle is compared at the decoded level like everything else.
2. **Make the omission impossible to repeat.** A `default:` that silently degrades to bytes is the
   trap: any entity missing from that switch re-dirties on every pull, and nothing fails when a new
   entity type is added. Make the switch **exhaustive over the synced entity types**, or add a test
   that enumerates them and fails when one has no case. Keep the byte fallback only for a record type
   this build genuinely cannot decode, which is what its comment actually describes - say which shape
   you chose and why.

**S9 must survive**: a genuinely edited Vehicle still re-dirties and still pushes (hard rule 8). The
previous fix's test for that (`aGenuineFieldMergeIsStillStoredDirtyAndStillPushes`) must stay green.

## Explicitly out of scope

- The `.fieldMerge` arm and `mergeVehicle`'s guards - fixed in `85ba6d5`, leave them alone.
- [RV.154] (a push costs three DB round trips per record) and [RV.155] (the pull cursor), both filed
  from the same logs.
- The `preferences` record that also appears in some pushes: `Preferences` HAS a case, so if it is
  still echoing the cause is different. **Report it if you see it; do not chase it here.**

## Docs to read before writing (in order)

1. `docs/SYNC.md` -> S9 and the payload contract.
2. `CLAUDE.md` hard rules 2, 8, 12.

## Checks

Re-measure the baseline yourself and report what you observe. As left, `main` was **1786 tests / 205
suites, all green**, **808** localization keys at 100% RU.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0. From the root, **not** `ios/`.
3. `cd ios && swift test` - full, never subsetted; report the count.
4. UI suites: none expected - this is core sync. If you touch `ios/App/Sources`, name the suite and
   its observed, non-zero count.
5. Localization gate - exit 0; report keys and RU percentage.
6. Release build only if you touch a `#if DEBUG` seam. Say which applies.

Verify by **exit code** (`echo $?`), and report the codes you observed.

### Tests you must add

- **L1, and it FAILS TODAY**: two Vehicle records that decode equal but differ in payload bytes are
  `recordsEqual`. Use a real lossy-round-trip difference, not a contrived one.
- **L1**: every synced entity type has a case - adding a type without one fails this test. This is
  the test that stops a fourth arm.
- **L3, the row's whole point**: an idle account across **two** foreground cycles pushes **zero**
  records with a Vehicle present. Assert the transport's **push count**. One cycle cannot show it.
- **L1**: `dirtiedByPull` is 0 across an idle cycle - the counter is now the regression signal.
- **L1**: a genuinely edited Vehicle still re-dirties and pushes (S9, hard rule 8).

### Vacuous traps, named

- Adding the Vehicle case and leaving `default:` reachable by the next entity - that is this bug
  waiting for the next entity type.
- Asserting the merge RESULT rather than the push count across two cycles.
- A fixture with byte-identical payloads, where the bug cannot appear.
- Making the `.local` arm never re-dirty, which closes the loop by losing local edits (hard rule 8).

## Never stash, move or `git checkout` to get a "clean baseline"

Write the test, run it against the unmodified code, then make the change - or mutate one line to
prove the test's teeth. **Do not** `git stash`, `git checkout`, or move files out of the tree: an
agent did that on 2026-09-08 and a bad `mv` loop destroyed three of its own new files. The headline
test genuinely fails today, so run it first and show that output.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**.
Use `pgrep -x xcodebuild`. **Never `pkill -f`.**

## Report back

Every check with the **exit code you observed** and the observed count; whether each test was **run
or only written**; the failing-then-passing output for the headline test; which shape you chose to
make the switch safe against a future entity type and why; whether `Preferences` shows the same
symptom; and anything you found and did not fix.
