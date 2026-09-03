# RV.35 – `preferences` echoes through the record-level merge path

RV.14 fixed the `Vehicle` half of the sync echo loop and it is merged. **This is the other half**,
and production shows it live.

Core only. No simulator, no `xcodebuild` — another agent is using them.

## Where you may write

Only inside this worktree. **Do not run `git add` or `git commit`.** **Do not touch `docs/TASKS.md`.**

## The cause, already traced

`preferences` (the singleton `00000000-0000-7000-8000-000000000001`) is **not** a `Vehicle`, so it
never reaches `RecordMerge.mergeVehicle` — the code RV.14 fixed. It takes record-level LWW and lands
in `SyncEngine.applyPull`'s `case .local`:

```swift
if isLocalEdit(local.syncState) { return [] }
if local.record.payload != remote.payload || local.record.deleted != remote.deleted {
    try repository.markDirty(id: remote.id, entityType: remote.entityType)
}
```

That is a **raw byte comparison of two JSON payloads**, and it cannot converge across a lossy
round-trip — key ordering, decimal formatting (`1.0` vs `1`), a field the server normalises, a
re-encode that reorders a dictionary. Any of those makes the bytes differ while the *record* is
identical, so the row is re-dirtied, pushed, pulled back, and re-dirtied again.

**Production evidence (2026-09-03)**: preferences pushed at 07:03:46, then 09:47:44 and again at
09:48:19 **with a pull between them** — `Accepted`, `Conflicts=0`, the same shape as the vehicle loop.

## What to build

Compare **decoded values**, not bytes — the level the merge actually reasons at.

`RecordMerge` already proves the pattern for `Vehicle` (see the RV.14 change): it compares the
decoded entity plus its effective field versions, with a helper that mirrors the merge's own
fallback so the comparison and the merge cannot disagree about what "new" means. Do the equivalent
here for the generic path.

**This arm is generic across every non-Vehicle entity**, so your fix reaches fillUps, expenses,
services, tombstones and preferences alike. **Say in your report which types you actually
exercised** — "preferences works" is not evidence the class is fixed.

## THE DANGER — read this twice

The counterpart matters as much as the fix. **A record whose remote copy genuinely differs must
still be re-dirtied.** If you over-correct, a real divergence stops pushing — and that failure is
invisible, because a record that never pushes looks exactly like a record with nothing to push.
Hard rule 8: *nothing lost silently*.

So the pair of tests is the deliverable: it settles when nothing changed, and it still pushes when
something did. Mutation-check **both directions** and report both.

## Explicitly out of scope

- `mergeVehicle` and the `.fieldMerge` arm — RV.14, done and merged. Read it as the pattern; do not
  change it.
- The sync trigger frequency (RV.18) and the record-level LWW winner rules themselves.
- Any `ios/App` UI file, anything under `backend/`.

## Read before writing

1. **`CLAUDE.md`** — hard rule 8 above all, plus 2, 3 and 14.
2. `docs/SYNC.md` — conflict scenarios **S1–S9**; every one must still hold, and the doc moves in the
   same change if any promise changes.
3. `ios/Sources/TankbookCore/Sync/SyncEngine.swift` (`applyPull`), `RecordMerge.swift`, and
   `ios/Tests/TankbookCoreTests/SyncVehicleLoopTests.swift` — RV.14's tests, the model to follow.

## Tests

- `cd ios && swift test` — **1159 today; the number must not fall.**
- The loop test: a record pushed, pulled back **unchanged**, settles and pushes no second time.
  **Drive at least two cycles** — one pull cannot show a loop.
- The counterpart: a record whose remote copy genuinely differs is still re-dirtied and still pushes.

**Vacuous-assertion traps, named:**
- Asserting the merge winner without asserting the **sync state written**. The bug is the `.dirty`.
- A single-cycle test. The loop only appears on the second.
- Using the same comparison in the assertion that the fix uses — both would be wrong together and agree.

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    swiftlint lint ; echo "LINT=$?"          # from the repo ROOT
    cd ios && swift test ; echo "TEST=$?"

**Judge by the exit code you echoed.** Zero lint **errors**.

**Do not run `xcodebuild` or the simulator** — you do not need them and another agent is using them.
Match the process NAME if you check anything (`pgrep -x swift`); **never `pgrep -f` or `pkill -f`**.

## No screenshots

Core logic. Say none applies rather than fabricating one.

## Report back

- Exit codes for `swift build`, `swiftlint`, `swift test` — numbers. Test count before and after.
- **Which entity types you exercised**, not just preferences.
- **Both mutation results**: the loop test red with the byte comparison restored, and the
  still-pushes test red if you over-correct.
- What you compared to decide "nothing changed", and why that comparison converges.
- Anything unfinished, named plainly.
