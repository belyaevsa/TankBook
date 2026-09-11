# RV.208 - entries already on users' phones may carry a dangling attachment id

**Scenarios: J3 · a mixed receipt, and J8b · look at the receipt again.** `[!]` - on users' phones.
**Dispatched alone.** This row is a DECISION with a migration behind it, and the decision is the
harder half.

## The defect

Raised by the `RV.173` agent from inside its own fix: the grouped-save path shipped with the
unconditional id stamp, so any user whose photo write failed on a mixed receipt has `Expense` rows
pointing at an `Attachment` that was never written. `RV.173` stops it recurring and does nothing
about rows that already exist. The symptom is silent until something dereferences the id.

## The decision, first

**Sweeping is not obviously right.** An id whose blob simply has not synced yet is NOT dangling;
a migration that cannot tell those apart deletes a valid link for every user mid-restore. **Read
`docs/SYNC.md` -> the blob pipeline** and establish, with citations, how "absent locally, pending in
sync" is distinguishable from "exists in no form" on this device. The states that matter:

1. `Attachment` row exists, rendition file absent, blob pending upload or download -> **not dangling**.
2. `Attachment` row exists, file absent, no pending transfer, `sha256` unknown to the server -> ?
3. No `Attachment` row at all for the id -> **dangling** (this is `RV.173`'s case).

Say which of these the migration can decide locally and which it cannot. **If a state cannot be
decided on-device, the honest answer is to leave it and let the viewer handle a missing rendition**
- `PJ.28`/`RV.37` already own that surface. Then this row ships the viewer behaviour and records the
reason, not a sweep.

## What to build, once decided

Either a one-time migration (`Migrations.swift`, numbered, idempotent, logged by SHAPE only - counts,
never ids) that clears **only** case 3, or the recorded decision plus whatever the viewer needs to
show *"the photo for this entry was never saved"* with its next step (re-attach - `RV.202` gives
the non-fill screen that door). **Both halves may be right**: sweep case 3, viewer for the rest.

## Tests

- **L1**: a row whose attachment is absent locally but pending in sync is **not** cleared.
- **L1**: a row whose attachment exists in no form (no `Attachment` row) is cleared - or, if you
  decided not to sweep, the viewer presents the next step for it.
- **L1**: the migration is idempotent - running twice changes nothing the second time.
- **L1**: nothing logged carries an id, a path or a name (hard rule 12).
- If the viewer changes: **L4 `EditEntryUITests`** EN + RU, the missing-rendition state and its
  next step.

## Mutation - named

Make the sweep clear case 1 as well (remove the pending-transfer check); the "pending is not
cleared" L1 goes red. If you shipped no sweep, the mutation is on the viewer: remove the next step
and its L4 goes red. Byte-identical restore; outputs verbatim.

## Vacuous traps

- Clearing every unresolvable id.
- A migration that runs on every launch.
- Deciding "leave it" without the viewer behaviour that makes leaving it safe.
