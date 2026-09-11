# RV.155 - the pull cursor went backwards and re-fetched 274 records

**Scenario: J11 · new phone - the pull that restores it.** The only v1 row holding J11 open.

## The evidence

Production logs 2026-09-09, one device, one session: `SinceScn=1389 -> 1405`, `1405 -> 1589`, then
**`SinceScn=1405` again** returning 274 rows and advancing to 1679; the next pull is correct. Nothing
corrupts - rows are idempotent - but a device on a metered connection re-downloads the delta, and
on a large import that is the expensive direction.

**Hypothesis, to test not assume**: the cursor is persisted only at the END of a cycle, while a
40-second push (`RV.154`) holds the cycle open long enough for a second pass to start from the stale
in-memory value. Find the cursor's read and write sites in the sync client; reconstruct the
sequence from the log timestamps; say whether the hypothesis holds or what else does.

## Build

Persist the cursor when the pull that earned it **succeeds**, not when the surrounding cycle
finishes, and make a second pass read the persisted value. Never log a record or a scn value that
is a domain value (hard rule 12 - scn is a cursor, loggable; counts are loggable).

## Tests

- **L1, FAILS TODAY**: two overlapping cycles - the second starting after the first's pull returned
  but before its cycle ended - do not re-fetch; the second pull's `since` is the first's `next`.
- **L1**: a failed pull does not advance the cursor.
- Backend: no change expected; if the contract needs one, stop and report (`docs/API.md` changes
  are a breaking-change review).

## Mutation - named

Move the persist back to cycle end; the overlap L1 goes red. Restore; verbatim.
