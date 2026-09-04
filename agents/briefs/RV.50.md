# RV.50 – the rate backfill queue never drains

From production logs, 2026-09-04. **Twenty consecutive passes**, 06:21 → 07:56, every one reading:

```
rates.backfill · Processed=50 Published=0 CarriedForward=0 SourcesFailed=0
```

Fifty is exactly `BackfillBatchSize`. A full batch is drained every five minutes and **nothing is
published, nothing carried, and nothing even fails** — including across 06:56–07:31, a window with
**no device traffic at all**, so it is not fresh demand.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios` — **`backend/` and `docs/` only.**
**Do not run `git add` or `git commit`. Do not touch `docs/TASKS.md`.** Touch no `ios/` file.

**Never move, rename or delete a file you did not create.** Two other sessions work in this
checkout. There is a git worktree at `.claude/worktrees/rv48` that is **not yours** — `swiftlint`
reports errors from inside it; ignore them, they are not your gate. If something else is broken and
is not yours, **report it and carry on**.

## What is already established — do not re-derive, but do confirm

`SettleAsync` **is** called unconditionally for every date in the batch
(`RateBackfillService.cs:101-104`) and deletes by `(base, date)`
(`RateRepository.cs:258-265`). The rows are being removed. **So they are being put back.**

**The prime suspect is a predicate mismatch between the two ends:**

- **`RecordRequestAsync`** (`:53-71`) enqueues a date when `!sources.IsSubsetOf(families)` — i.e.
  when **any** feed family lacks a row for it.
- **`BackfillDatesAsync`** (`:154-158`) *skips* a feed when `families.Contains(feed.Source)` — i.e.
  it only fetches from feeds that have **no** row.

A date that one feed covers and another structurally never will therefore satisfies "enqueue me"
forever, while the backfill correctly concludes there is nothing to fetch. Enqueue → no-op → settle
→ re-enqueue. `SourcesFailed=0` fits: no upstream call is being made at all, so the work is being
**skipped**, not failing.

**Confirm this before building.** You cannot reach production, so **reproduce it as a test** — that
is both the confirmation and the regression guard:

> seed a `(date, base)` that no feed can fill, run `ProcessPendingAsync` **twice**, and assert the
> queue is **empty on the second pass**.

If that test passes against today's code, the diagnosis above is **wrong** — say so plainly, and
report what the real mechanism is. A brief's diagnosis is a hypothesis, and RV.6 proved this month
that a filed row's stated premise can be false.

## What to fix

**The two predicates must agree on granularity.** Decide whether "covered" means *every feed family
has a row* or *this date has a usable rate*, and apply the **same** test on both sides. As long as
they differ, a date that is legitimately unfillable looks pending to one end and finished to the
other, forever.

**A date that cannot be filled must be recorded as ANSWERED, not merely settled**, so it is never
re-enqueued. RV.32's own row already called for this — *"a date answered 'nothing published' must be
recorded as answered, distinct from 'not yet asked'"* — and the carry-back rule was believed to have
dissolved the need. It did not, for dates outside the 14-day window.

**Do not fix it by making the pack stop enqueuing.** The pack's job is to say what the device needs;
if it stops asking, a date that becomes fillable later is never picked up. Fix the disagreement, not
the messenger.

## Costs, so you weigh them correctly

Today's cost is **DB churn, not money** — no upstream requests are burned, since the work is skipped.
Do not overstate it. The real damage is that **`rates.backfill` is useless as a health signal**: the
line looks identical whether the system is healthy or wedged, so the next person to read it will
assume the backfill works. A fix should leave the log able to distinguish those two states — say how
yours does.

## Read before writing

1. **`CLAUDE.md`** — hard rules 3 (money is a pair; rate snapshots are immutable), 9 (the server
   validates structure, never domain meaning), 12 (shape-only logging), 14.
2. `docs/SCHEMA.md` → **Exchange rates** (the demand-driven backfill and the two-way resolution rule
   with its measured 14-day bound), `docs/API.md` → `/rates/pack` as the backfill trigger.
3. `backend/src/Tankbook.Api/Rates/` — `RateBackfillService.cs`, `RateRepository.cs`,
   `RateOptions.cs`, `RateBackfillHostedService.cs`; and `backend/tests/…/Rates/RateBackfillTests.cs`
   for the existing L2 shape (real Postgres via Testcontainers).

## Tests

**Backend, 370 today; must not fall.**

- **The reproduction above is the headline test**: unfillable date → two passes → **queue empty on
  the second**. Assert the queue is empty, not that the pass "succeeded".
- **The counterpart, so the fix does not over-correct**: a date that IS fillable, or that becomes
  fillable after an earlier anchor arrives, must still be fetched and published — a fix that simply
  stops re-enqueuing everything would pass the first test and silently break the feature RV.32
  exists for. **Assert a published rate lands.**
- A date inside the 14-day window still carries back; one outside it stays honestly absent (existing
  behaviour — confirm it is unchanged).

**Vacuous-assertion traps, named:**
- Asserting `Processed == 0` on the second pass without asserting the queue is empty — a batch of
  zero could also mean the queue read broke.
- Asserting "the service ran without throwing". It has never thrown; that is the whole problem.
- Testing only the unfillable case. The over-correction is the dangerous half.

**Mutation-check and report it**: revert your predicate change, confirm the two-pass test goes red,
restore byte-for-byte, confirm green.

## The baseline gate (CLAUDE.md rule 14)

    cd backend && dotnet build ; echo "BUILD=$?"
    cd backend && dotnet format --verify-no-changes ; echo "FORMAT=$?"
    cd backend && dotnet test ; echo "TEST=$?"

**Echo the exit code from the COMMAND, never through a pipe** (`cmd | tail -2 ; echo $?` reports
`tail`'s status); redirect to a file instead. `backend/scripts/dev-up.sh` starts Postgres + MinIO
(plain `docker run`, no compose). Match the process NAME (`pgrep -x ...`); **never `pgrep -f`**.

## Report back

- Exit codes (captured, not piped), test counts before/after, the mutation result.
- **Whether the reproduction test failed first.** If it did not, the diagnosis above is wrong — say
  so and give the real mechanism.
- Which granularity you chose for "covered", and why.
- How a wedged backfill would now look different in the log from a healthy one.
- Confirmation the pack still enqueues (you fixed the disagreement, not the messenger), and that a
  fillable date still publishes.
- Anything you noticed that is not RV.50 — named separately.
