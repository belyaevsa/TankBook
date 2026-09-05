# RV.60 – does the rate backfill actually drain? Measure it.

Filed 2026-09-04 from a production log. **This row is an INVESTIGATION first and a fix only if the
measurement demands one.** Do not assume there is a bug; do not assume there is not.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios` – **`backend/` and `docs/` only.**
**Do not run `git add` or `git commit`. Do not touch `docs/TASKS.md`.** Touch no `ios/` file.
**A sibling agent may be working in `ios/`** – ignore it. **Never move, rename or delete a file you
did not create.**

## What the log shows

Two passes five minutes apart, identical both times:

    14:52:45  rates.backfill Processed=50 Published=0 CarriedForward=0 SourcesFailed=0 Answered=50
    14:57:45  rates.backfill Processed=50 Published=0 CarriedForward=0 SourcesFailed=0 Answered=50

`Answered` is RV.50's own field, so the mechanism RV.50 added IS firing. But `Published=0` with a
constant `Processed=50` is also the steady-state signature RV.50 existed to remove, and **the log
alone cannot tell "draining a large backlog, 50 at a time" from "re-answering the same 50 forever".**

## Two corrections to the original row – do not chase these

The row that filed this pointed at `ReopenAnsweredAsync` (`RateBackfillService.cs:244`) as the
re-queue suspect. **That is probably wrong, and I checked before writing this brief:**

1. `ReopenAnsweredAsync` sits **after** the quotes-empty guard and after `UpsertAsync` – it runs
   only when a feed actually returned quotes and something was published. The log says
   `Published=0`, so on these passes it almost certainly never fired.
2. `Processed=50` is **exactly `RateOptions.BackfillBatchSize` (50)**, the batch cap
   (`RateBackfillService.cs:131`, `RateRepository.cs:245 LIMIT @BatchSize`). So `Processed=50` means
   only "the queue held at least 50", which is entirely consistent with an ordinary backlog.

**The most likely answer is therefore that it IS draining, slowly.** Your job is to establish which
it is with a number, not to find a bug that may not exist. **Reporting "it drains correctly, here is
the evidence" is a complete and successful outcome for this row.**

## What to do

**1. Measure the depth across several passes.** Query the pending count directly – the queue table,
not the log line – before and after each pass, and show the series. If it FALLS, say so and stop:
report the drain rate and how long the observed backlog would take to clear at
`BackfillBatchSize` per `PurgeInterval`/pass, and whether that is acceptable.

**2. If it is FLAT, find what re-queues.** Then, and only then, the mechanism matters. Trace it to a
line rather than naming a suspect.

**3. If it drains but too slowly to be useful, say so as a product observation** – do NOT widen
`BackfillBatchSize` as the fix. That hides a non-draining queue behind a bigger number, and if the
queue is genuinely draining it is a tuning question for the product owner, not a defect.

**4. Also in scope, and small:** `llm.extract` logs `QuotaBefore=6 QuotaAfter=7`, which reads as a
quota INCREASING when it is a usage counter going up. Rename the fields to say what they count.
Hard rule 12 permits counts and codes, so this is a clarity fix, not a privacy one. Check
`docs/LOGGING.md`'s event table and fix it in the same change.

## Read before writing

1. **`CLAUDE.md`** – hard rules 12 (counts and codes loggable, domain values never), 14.
2. `docs/LOGGING.md` – the event table and what each field means; `docs/SCHEMA.md` – reference-data
   services and the rate model.
3. `backend/src/Tankbook.Api/Rates/RateBackfillService.cs` (`RunPassAsync`, `RecordRequestAsync`,
   the `ReopenAnsweredAsync` call site), `RateRepository.cs` (`GetPendingBatchAsync`,
   `MarkAnsweredAsync`, `ReopenAnsweredAsync`), `RateOptions.cs`,
   `backend/tests/Tankbook.Api.Tests/Rates/` for the existing L2 shape.

## Tests

**Backend 387 today; must not fall.**

- **The headline L2: a seeded backlog shrinks pass over pass and reaches ZERO.** Assert the pending
  COUNT at each pass, never `Published` – a pass that publishes nothing but correctly answers rows
  is doing its job, which is exactly why `Published` is the wrong signal.
- **L2: a row that can never be answered stops being retried, with a defined terminal outcome.**
  If no such bound exists, that is a finding – report it rather than inventing one silently.
- L2: a backlog larger than `BackfillBatchSize` takes the expected number of passes – pins the cap's
  behaviour so a future change to it cannot silently stall the queue.
- If you find a genuine re-queue loop: a test that fails before your fix and passes after.

**Vacuous-assertion traps, named:**
- **Asserting one pass returns `Answered > 0`.** True today, and true when the bug is present.
- Asserting `Published > 0` – on an unfillable date, publishing nothing is correct.
- Asserting the pass "completed" or did not throw. Mechanism, not outcome.
- Seeding a backlog smaller than the batch size, which cannot show draining at all.

**Mutation-check and report it** (only if you change behaviour): break the drain – e.g. skip
`MarkAnsweredAsync` – and confirm the shrink-to-zero test goes red. Restore byte-for-byte, confirm
green. **If you change nothing because the queue drains correctly, say so and skip the mutation** –
say that plainly rather than inventing a change to justify the row.

## The baseline gate (CLAUDE.md rule 14)

    cd backend && dotnet build ; echo "BUILD=$?"
    cd backend && dotnet format --verify-no-changes ; echo "FORMAT=$?"
    cd backend && dotnet test ; echo "TEST=$?"

**Echo the exit code from the COMMAND, never through a pipe**; redirect to a file instead.
`backend/scripts/dev-up.sh` starts Postgres + MinIO (plain `docker run`, no compose).
Match the process NAME (`pgrep -x ...`); **never `pgrep -f`**.

## Screenshots

None applies – backend only. Say so rather than fabricating one.

## Report back

- Exit codes (captured, not piped), test counts before/after.
- **The pending-count series across passes** – the number this row exists to produce. State plainly
  whether it drains, and at what rate.
- Whether `ReopenAnsweredAsync` fires at all on a `Published=0` pass (I believe not – confirm).
- Whether an unanswerable row has a retry bound, and what happens when it is exhausted.
- The `QuotaBefore`/`QuotaAfter` rename, and what `docs/LOGGING.md` now says.
- Anything you noticed that is not RV.60 – named separately.
