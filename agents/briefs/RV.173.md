# RV.173 - a failed photo write leaves the expenses pointing at nothing

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** **Agents never tick `docs/TASKS.md` and
never commit.**

**Scenario: J3 · The 5-second fill-up (receipt)** - the mixed-receipt branch. A change to what the
user is promised edits `docs/JOURNEYS.md` **in the same change** (`CLAUDE.md`, 2026-09-10).

## The defect

Reported by the [RV.149] agent from **outside its own fence**, and pre-existing.

On a **grouped save** - one slip that produces a fill-up plus one or more expenses - the accepted
`Expense` rows take the shared `attachmentID` from `ScannedSavePlan.expenses(from:)`. When the photo
write throws, the fill-up and the disk carry no attachment, and `RV.149` now says so honestly. **Its
expense siblings from the same slip keep a dangling id.**

**Nobody has reported it because the id is only dereferenced when something tries to show the
photo.** That is the whole danger: it is a silent hole in the data, which is hard rule 8's
territory, and it surfaces later as a viewer that opens onto nothing.

This is the `RV.149` defect one row over - and `RV.149` exists because `PJ.28`'s fix stopped at one
entry kind. **This is the third step of the same fence.**

## This brief's diagnosis is a hypothesis - confirm it before you change anything

Four of the orchestrator's diagnoses were wrong in one session and an agent caught every one.
**Reproduce it first**: make the photo write fail on a grouped save and show the stored `Expense`
rows carrying an `attachmentID` that resolves to no `Attachment`. **Report the state you observed
before changing anything.** If it does not reproduce, say so and say what would - do not fix a break
you could not see.

## What to build - and the decision is yours to make and state

`RV.149` already returns an outcome (`.nothingToWrite` / `.wrote` / `.lost`) instead of swallowing
the failure. **The grouped save must consume that outcome for every row it writes, not just the
fill-up.** Two honest shapes, and **you must choose one and write the reason**:

- **Write the group with no attachment ids at all.** The entry is saved, the photo is gone, the user
  is told once (`RV.149`'s message), and nothing points at anything missing.
- **Do not write the ids, and mark the group so a later attach can bind them.** More faithful to
  hard rule 8 if such a re-bind exists; **only choose it if the mechanism is real** - a flag nothing
  reads is `PJ.55`'s shape, and this codebase has three monuments to it.

**Whichever you choose: no row may reference an attachment that does not exist.** That is the
invariant; the rest is implementation.

## Explicitly out of scope

- `RV.171` - the guard over this seam. It is **sequenced after this row** precisely because it needs
  the seam you are about to settle, the same way `RV.170` waited for `RV.189`.
- `RV.204` - the block-vs-degrade contract asymmetry on the edit screen. Different screen, filed.
- The viewer's behaviour when a rendition is missing. `PJ.28`/`RV.37` own that, and it is the
  *symptom* surface, not the cause.

## Docs to read before writing (in order)

1. `ios/App/Sources/ConfirmManual/ManualFillUpReceiptSave.swift` - `RV.149`'s outcome contract, and
   the report that fires **after** the entry is on disk.
2. `ios/Sources/TankbookCore/Domain/ScannedSavePlan.swift` -> `expenses(from:)`, where the shared id
   is stamped.
3. `docs/SCHEMA.md` -> **Attachment**, and `purchaseGroupId` - the group these rows share.
4. `docs/ERRORS.md` -> the attach-failure row; **extend it if the grouped case says anything new**.
5. `CLAUDE.md` hard rules 7 and 8.

## Environment axes this crosses

**Storage failure is the row's own axis** - you must be able to force it; say how you did.
**Locale**: only if you add copy; if the existing `RV.149` message covers it, say so and ship no new
string. **Screenshots**: only if a user-visible surface changes - a save path that writes one fewer
id has no frame, and saying that is the right answer.

## If this adds a failure path, what makes it visible in production?

The failure already exists and is now reported once. If your shape introduces a new branch - a group
written without ids, say - add the shape-only event that answers *"did a grouped save drop its
attachment ids?"* - **counts only**, never a filename or an amount (hard rule 12).

## Tests you must add

- **L1, and it FAILS TODAY**: on a grouped save whose photo write throws, **no stored row references
  a missing attachment**. Oracle: every `attachmentID` on every written row resolves to a live
  `Attachment`, or is absent.
- **L1**: the fill-up and its expense siblings agree - either all carry the attachment or none does.
  A partial group is the defect.
- **L1**: the happy path is untouched - a successful grouped save still binds every row to the one
  attachment, with its `purchaseGroupId` intact.
- **L1**: the user is still told, exactly once, through `RV.149`'s existing report - not once per row.

Every expectation names its ORACLE. Report each suite's observed, **non-zero** count, filtered
**by suite name, not the file's**.

## The mutation you must run - I am naming it, do not choose your own

**Restore the unconditional id stamp** on the expense rows - today's behaviour - and show the
"no stored row references a missing attachment" L1 goes red naming the dangling id. Then restore
byte-identical and re-run. Report both outputs verbatim.

## Vacuous traps, named

- **Fixing the fill-up path again.** `RV.149` did that; this row is its siblings.
- Clearing the ids and not proving the happy path still binds them - half a fix, silently.
- Reporting the failure once per expense row, so a three-line slip shouts three times.
- A "pending attachment" flag nothing reads (`PJ.55`'s shape).
- Asserting the save succeeded rather than asserting the stored ids resolve.

## Never stash, move or `git checkout` to get a "clean baseline"

An agent's `git stash` + `mv` loop destroyed three of its own new files on 2026-09-08.

## Never `pgrep -f` for a build process

Your brief is in your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**. Use
`pgrep -x xcodebuild`. **Never `pkill -f`.**

## Concurrent work in this checkout

Another `opencode` run has been growing the receipts corpus since 2026-09-10 19:57 and holds
uncommitted changes in `Spike/ReceiptSpike/fixtures/`,
`ios/Sources/TankbookCore/Config/PumpPhotoGate.swift` and `ios/Tests/TankbookCoreTests/Corpus*`.
**Do not touch, revert or `git checkout` any of them.** Also pre-existing and **not yours**: four
`ReminderNotificationActionTests` failures, and `SyncWriteTriggerTests` ([RV.203]), which fails under
machine load and passes alone.

## Standing checks

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0 (from `ios/` it exits 2 with ~5000 phantom errors).
3. `cd ios && swift test` - full; report the count. **Run it alone.**
4. **`xcodebuild ... build` for the app target** ([RV.174]).
5. `xcodegen generate`, then any UI suite touched **by suite name**, non-zero count.

Verify by **exit code** (`echo $?`).

## Report back

**The state you observed before changing anything** - the dangling id, or the reason it did not
reproduce; **which shape you chose and why**; how you forced the write to fail; every check with its
**exit code observed** and counts; **the mutation's red-then-green output verbatim**; and **anything
you found and did not fix**.
