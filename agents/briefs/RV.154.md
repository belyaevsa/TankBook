# RV.154 - a sync push costs three DB round trips per record

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo, and only
under `backend/`.** Write code first, explore second. Do not commit; the orchestrator commits after
verifying.

**Another agent is working in this checkout right now on the iOS CLIENT.** Expect files under `ios/`
to change under you. **Never move, rename, revert or `git checkout` anything**, and do not touch
`ios/` at all. If something looks odd, report it and carry on.

## The defect, measured in production

Server logs 2026-09-09, the product owner's import. Four consecutive pushes:

```
BatchSize=93  DurationMs=41007
BatchSize=91  DurationMs=40019
BatchSize=90  DurationMs=39565
BatchSize=88  DurationMs=38125
BatchSize=3   DurationMs=1441      <- and a small one, for contrast
```

**~440 ms per record.** The import spent roughly nine minutes pushing. It is still bad on the
current build: `BatchSize=31 -> 13896 ms`, `BatchSize=33 -> 14789 ms` on `1.0.0+925`.

## What is NOT the cause - do not re-fix it

[RV.105] already collapsed the per-record transaction into one. `Commits=1` in every log line proves
it, and its comment records the ~578 ms fsync it removed. **The commit is not the problem.**

## The cause, pinned

Inside that single transaction, `SyncRepository.ApplyBatchAsync`
(`backend/src/Tankbook.Api/Sync/SyncRepository.cs:141+`) loops per record and awaits **three separate
round trips** each:

1. `QuerySingleOrDefaultAsync<RecordRow>(RecordColumns + " WHERE account_id = @AccountId AND id = @Id FOR UPDATE")`
2. `ScnAllocator.AllocateAsync(transaction, accountId)` - its own `INSERT ... ON CONFLICT ... RETURNING`
   (`backend/src/Tankbook.Api/Data/ScnAllocator.cs:16-26`)
3. `_db.ExecuteAsync(InsertSql | UpdateSql)`

90 records x 3 = **270 serialized round trips**, and 440/3 = **~145 ms per round trip** says the
database link is the cost, not the work. **Confirm this before building on it** - measure where the
time actually goes rather than trusting the arithmetic.

## What to build

**Collapse the round trips, not the transaction.** Three per-record calls become three per-BATCH
calls:

1. **One multi-row read** of the current rows (`WHERE account_id = @AccountId AND id = ANY(@Ids) FOR UPDATE`).
2. **One SCN range allocation** for the whole batch - `account_seq.next_scn + @count RETURNING` gives
   a contiguous block in one round trip instead of one call per new record.
3. **One multi-row write** - `INSERT ... ON CONFLICT DO UPDATE` over the batch, or `COPY` into a temp
   table then a single merge.

**The semantics [RV.105] protects must survive exactly:**

- a conflict or an idempotent replay is a **no-op inside the transaction**, never a rollback, so
  partial acceptance still works;
- every record still reports its own `Outcome` / `ErrorCode` / `Pointer` in the response
  (`docs/API.md`), in the same order;
- `AssignedScnRange` stays contiguous, strictly increasing, and matches what was actually assigned;
- `FOR UPDATE` locking behaviour is preserved - do not lose the row lock by batching the read.

**Measure before and after on a realistic latency.** The defect is **invisible on a local Postgres**,
where a round trip is ~0.1 ms and 270 of them cost nothing. Say how you measured.

## Explicitly out of scope

- Anything under `ios/` - another agent is there.
- [RV.155] (the pull cursor regressing). It may dissolve once a push is fast; it is not yours.
- The pull path, blobs, and the LLM gateway.

## Docs to read before writing (in order)

1. `docs/API.md` -> sync push: the response contract and per-record outcomes.
2. `docs/SYNC.md` -> the payload contract and what an SCN means.
3. `CLAUDE.md` hard rule 9 - the server validates structure, never meaning. This change must not
   start reading what a field means.

## Checks

Re-measure the baseline yourself and report what you observe.

1. `cd backend && dotnet build` - exit 0.
2. `cd backend && dotnet format --verify-no-changes` - exit 0.
3. `cd backend && dotnet test` - report the count. As left, the suite was **437**; re-measure.
4. iOS gates are **not** yours - do not run `swift build`, `swift test` or `xcodebuild`. Another
   agent is using that toolchain and the simulator.

Verify by **exit code** (`echo $?`), and report the codes you observed.

### Tests you must add

- **L2, the row's whole point**: a push of 200 records issues a **bounded, constant** number of DB
  commands. **Assert the command count, not the wall clock** - a timing assertion is meaningless on a
  fast local database and will flake in CI.
- **L2**: per-record outcomes are unchanged for a batch mixing accepted, conflicted and
  idempotent-replay records - same outcomes, same order.
- **L2**: SCNs assigned to a batch are contiguous and strictly increasing and match
  `AssignedScnRange`.
- **L2**: a rejected record still rejects **without rolling back** the accepted ones.
- **L2**: an empty batch still returns `Commits: 0` and touches nothing.

### Vacuous traps, named

- Measuring on a local Postgres and concluding it is fast.
- Batching the write but leaving the per-record `SELECT` or the per-record SCN allocation - that is
  two thirds of the cost still on the wire.
- Breaking partial acceptance to get one statement.
- Asserting elapsed time rather than command count.
- Losing `FOR UPDATE` semantics when the read is batched.

## Never stash, move or `git checkout` to get a "clean baseline"

Write the test, run it against the unmodified code, then make the change - or mutate one line to
prove the test's teeth. **Do not** `git stash`, `git checkout`, or move files out of the tree: an
agent did that on 2026-09-08 and destroyed three of its own new files. A second agent is live in this
checkout.

## Never `pgrep -f` for a build process

Your brief is part of your command line. Use `pgrep -x dotnet`. **Never `pkill -f`.**

## Report back

Every check with the **exit code you observed** and the observed test count; whether each test was
**run or only written**; **how you measured** the before and after and at what latency; the command
count per batch before and after; and anything you found and did not fix.
