# RV.105 - sync push costs 578 ms per record, and it is four seconds from re-entering RV.97

## The measurement, from production - do not re-measure to confirm, measure to IMPROVE

Owner's server log, 2026-09-07 05:08-05:17 (device `787c4f6f`, build `1.0.0+806`), pushing the
513-row MFM import:

| Batch | Records | Server `DurationMs` | ms/record |
|---|---|---|---|
| 05:08:12 | 69 | 39 841 | **577** |
| 05:16:45 | 93 | 53 688 | **577** |
| 05:17:40 | 92 | 53 140 | **578** |

All `Accepted=n, Conflicts=0, Rejected=0`. Linear to three significant figures, so this is a **fixed
per-record cost** - not payload size, not CPU. Pulls in the same minutes return 69 records in
**1 021 ms**, so push is ~50x dearer per record than pull.

**The cause, read from the source.** `SyncRepository.ApplyChangeAsync`
(`backend/src/Tankbook.Api/Sync/SyncRepository.cs:118-137`) opens a transaction, runs
`SELECT … FOR UPDATE`, allocates an SCN, writes, and commits - and `SyncService` calls it **once per
change** in a loop (`backend/src/Tankbook.Api/Sync/SyncService.cs:70,100`). A 92-record batch is
**92 serialized commits**; ~578 ms is what one commit costs on that host.

**Why it is urgent, calculated not feared.** [RV.97] gave the client a **120 s** upload budget and
capped a batch at **64 KB or 200 records, whichever binds first**. Fill-ups are large enough that
64 KB binds at ~90 records - but a batch of **smaller** records (a delete cascade, reminders,
preferences) binds on the **count**, and **200 x 578 ms = 115.6 s against a 120 s budget**. One
slower disk day and the client abandons a push the server is still committing, which is [RV.97]
again at a bigger number.

## The tension IS the row - do not resolve it by ignoring one side

**One transaction for the whole batch is the obvious fix and it breaks a stated contract.**

- `docs/SYNC.md:668` promises **partial batch acceptance** (idempotent by id + `baseScn`): one
  conflicting record must **not** roll back the other 91.
- The class comment on `SyncRepository` states the second invariant: SCNs are allocated inside the
  row's own transaction so that *"committed SCNs are contiguous and commit in order, which is what
  lets a pull cursor page the stream without ever skipping an in-flight commit"*. `Pull_UnderConcurrentWrites_NeverSkipsARecord`
  is the test that owns it. A redesign that breaks this can lose a record from the pull stream
  **permanently**, which is far worse than slowness.

Shapes worth measuring, in this order:

1. **One transaction per batch, per-record outcomes collected inside it** - a conflict becomes a
   no-op within the transaction rather than a rollback, so partial acceptance survives.
2. **Batched SCN allocation** - one range for the batch instead of N allocations.
3. **A multi-row upsert** for the accepted set once conflicts are known.

Take the smallest change that moves the number and say which you took and what you rejected. **Do
not** lower [RV.97]'s record cap: that hides the cost behind more round trips and leaves the
per-record price untouched.

## Explicitly out of scope

- The client ([RV.97] shipped and is confirmed working in this same log - bounded batches, every one
  accepted, no `499`).
- Changing the pull path, which is already fast.
- Postgres tuning, connection pooling or host changes - the fix is in how many transactions the code
  opens.

## Tests

Backend row: `cd backend && dotnet build`, `dotnet test`, `dotnet format --verify-no-changes`.
Report counts before -> after (it was 410).

- **L2, the row's point**: a push of **200 records** - the maximum a client may legally send -
  completes well inside the 120 s budget. **Report ms per record before and after**; the total alone
  does not predict the 200-record case.
- **L1/L2**: a batch containing one conflicting record still returns `accepted` for the others and
  `conflict` for that one (`SYNC.md:668`).
- **L2**: SCNs assigned by a batch stay contiguous and in commit order, and a pull cursor paging the
  stream during concurrent pushes never skips a record - `Pull_UnderConcurrentWrites_NeverSkipsARecord`
  must still pass, and say explicitly that you ran it.

### Vacuous traps, named

- **Timing a batch of 5 records**, where 578 ms x 5 is invisible.
- **Reporting total duration without ms/record** - the per-record number is the one that predicts
  the failure.
- **Making the batch atomic and calling partial acceptance an acceptable loss** without a
  product-owner decision written into `docs/SYNC.md`.
- **Testing on a laptop SSD and concluding the fsync cost is gone** - the production host is the
  measurement that matters; say which machine your numbers come from.

### Mutations (run each, report, restore byte-for-byte)

1. Revert to a transaction per record -> the 200-record timing test must fail (report both numbers).
2. Make a conflicting record roll back the batch -> the partial-acceptance test must fail.

**A mutation that PASSES is a finding** - say so and grow the test until it fails.

## Docs to reconcile

`docs/SYNC.md` (the push transaction shape and what partial acceptance now means mechanically),
`docs/PRACTICES.md` if a new tunable appears - and it belongs in the compiled/operational column,
not remote config.

## Hard rules that decide things in this area

**8** (nothing lost silently - the SCN contiguity invariant is what stops a record vanishing from the
pull stream) · **9** (the server stores opaque records; this changes how they are written, never what
is read) · **12** (shape-only logging - counts and durations, never a payload) · **14** (for this row
that is `dotnet build` + `dotnet format --verify-no-changes`).

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
