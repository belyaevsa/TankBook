# RV.14 – the device pushes its own records back, forever

Production, idle account: one vehicle pushed **six times in seven minutes** (22:05:39, 22:07:17,
22:08:35, 22:09:13, 22:11:10, 22:12:50), `Accepted=1` and `Conflicts=0` every time, with each
`sync.pull` returning exactly what the previous push had just written. Battery, cellular data and an
SCN that grows without bound while nothing happens.

**This is the highest-risk task in the backlog. Read the whole brief before writing anything.**

## Where you may write

Only inside this worktree. **Do not run `git add` or `git commit`.** Do not touch
`docs/TASKS.md` — the orchestrator marks the row after verifying.

## The cause, already traced. Confirm it; do not re-hunt it.

`ios/Sources/TankbookCore/Sync/RecordMerge.swift` → `mergeVehicle` has exactly **three** exits:

1. either side `deleted` → `mergeRecord` (record-level LWW)
2. either payload fails to decode → `mergeRecord`
3. **everything else → `.fieldMerge`**

There is no fourth. Two live, decodable, **byte-identical** vehicles still come out `.fieldMerge`,
because the function reports *how it merged*, never *whether anything changed*.

`ios/Sources/TankbookCore/Sync/SyncEngine.swift` → `applyPull`, `case .fieldMerge`:

```swift
// S9: the merged Vehicle is a new write - store it dirty so it pushes.
let touched = try repository.applyRecord(result.keep, syncState: .dirty)
```

**Unconditionally dirty**, with no comparison against what was already there. So:

```
pull returns the vehicle → mergeVehicle → .fieldMerge (always)
  → applyRecord(.dirty) → next cycle pushes it
    → server assigns a new SCN → next pull returns it again → repeat
```

It cannot break on its own: after a merge `updatedAt = max(local, remote)`, and a tie never reaches
LWW anyway because `mergeVehicle` returns before comparison matters.

**Two things already ruled out, so you do not spend the run on them:**

- `payloadMemory` is **persisted** in the app (`DatabaseSyncPayloadMemory`, `AppSync.swift:39`), not
  session-scoped. It is not the cause.
- The fill-up that also appears in some pushes is most likely genuine user editing during the walk.
  The **vehicle in every single push** is the signature of this defect. Do not widen scope to chase
  the fill-up unless your own test shows it looping too.

## What to build

Report `.fieldMerge` only when the merge actually produced something new. Three outcomes:

| merged equals | meaning | what `applyPull` should do |
|---|---|---|
| the remote | nothing local to push | apply as **synced** at the remote's SCN |
| the local | already correct here | record the SCN, **do not dirty** |
| neither | a genuine new write | `.dirty` is right, exactly as today |

## THE TRAP, and it is the whole reason this is a pro task

**Do not compare raw payloads.** The tempting one-liner is to make `applyPull` diff
`result.keep.payload` against the local bytes and skip the dirty. That reintroduces precisely the
fragility already sitting in the `case .local` arm:

```swift
if local.record.payload != remote.payload || local.record.deleted != remote.deleted {
    try repository.markDirty(...)
}
```

A raw byte comparison **never converges** under any lossy round-trip — JSON key ordering, decimal
formatting (`1.0` vs `1`), a field the server normalises, a re-encode that reorders a dictionary.
It would swap one infinite loop for a subtler one.

Compare the **decoded `Vehicle` plus its field versions**, which is the level the merge itself works
at. `Vehicle` is `Equatable`-able and `mergedVersions` is a `[String: Date]`.

## THE DANGER, stated plainly

This is the code that decides whether a user's edits ever reach the server. Get it wrong in the
other direction and **a genuine merge silently stops pushing** — and that failure is invisible,
because a record that never pushes looks exactly like a record with nothing to push. Hard rule 8:
*nothing lost silently*.

So the S9 half must be proven still to work, not assumed. `docs/SYNC.md` S9 is the scenario:
two devices each change a different Vehicle field, and **both changes must survive and reach the
server**. If your change makes S9 stop pushing, you have traded a wasteful bug for a data one.

## Explicitly out of scope

- The `case .local` arm's raw-payload comparison. It is a real fragility and it is **not** what
  drives this loop — the vehicle never reaches that arm. Note it in your report; do not fix it here.
- `RecordMerge`'s LWW path for non-Vehicle entities.
- The sync trigger frequency — that is RV.18, dispatched separately.
- Any `ios/App` UI file, and anything under `backend/`.

## Read before writing

1. **`CLAUDE.md`** — hard rule 8 (nothing lost silently) above all, plus 2, 3, 13 and 14.
2. `docs/SYNC.md` — the conflict scenarios **S1–S9**, especially **S9** (the Vehicle field merge)
   and S1/S4 (the overwrite log). Your change must leave every one of them true; if it changes what
   any of them promises, the doc moves in the same change.
3. `ios/Sources/TankbookCore/Sync/RecordMerge.swift`, `SyncEngine.swift`, `SyncTransport.swift`.
4. The existing `RecordMerge` and sync-engine tests — they encode S1–S9 and are your regression net.

## Tests

- `cd ios && swift test` — **1154 today; the number must not fall.** No simulator is needed; this is
  core, so `swift test` is the whole gate for the logic.
- **L1**: `merge(local: X, remote: X)` on two identical live vehicles must NOT report `.fieldMerge`.
- **L2/L3 (the one that proves the bug is gone)**: one record pushed, then pulled back **unchanged**,
  must settle to `.synced` and **push no second time**. A single-cycle test will not show a loop —
  drive at least two cycles and assert the second pushes nothing.
- **S9 must still pass**: two devices, different fields, both changes survive and the merged record
  still pushes. Add it explicitly if the existing suite does not already assert the push.
- Drive the vehicle path with an **empty `payloadMemory`** in at least one test — that is the state
  after a relaunch, and it changes which `fieldVersions` are computed.

**Vacuous-assertion traps, named:**
- Asserting the winner is `.local` or `.remote` without asserting the **sync state written**. The bug
  is the `.dirty`, not the label.
- A test that pulls once. The loop needs a second cycle to appear; one pull proves nothing.
- Comparing payload bytes in the assertion — if the test uses the same comparison as the fix, both
  are wrong together and agree.

**Mutation-check and report it**: restore the unconditional `.dirty` and confirm your loop test goes
red. A test that passes with the old line back is not a test for this bug.

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    swiftlint lint ; echo "LINT=$?"          # from the repo ROOT
    cd ios && swift test ; echo "TEST=$?"

**Judge by the exit code you echoed**, not by skimming. Zero lint **errors**.

You do **not** need `xcodebuild` or the simulator for this task, and another agent is using them —
**do not run them.** If you believe you need a UI test, say so in your report instead.

Match the process NAME if you check anything (`pgrep -x swift`). **Never `pgrep -f` or `pkill -f`**
on a build/test pattern — an agent's brief is part of its command line, and on 2026-08-24 exactly
that killed another agent 48 minutes into its task.

## No screenshots

Core logic; nothing visual. Say none applies rather than fabricating one.

## Report back

- Exit codes for `swift build`, `swiftlint`, `swift test` — numbers, not prose.
- Unit-test count before and after.
- **Whether you saw the loop test fail with the unconditional `.dirty` restored.**
- **How you satisfied yourself S9 still pushes** — this is the answer that will be read hardest.
- What you compared to decide "nothing changed", and why that comparison converges.
- Anything you could not finish, named plainly.
