# RV.36 – a carried-forward placeholder permanently displaces the real rate

Backend only. Touch no `ios/` file — another agent is working there.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`. **Do not run `git add` or `git commit`.**
**Do not touch `docs/TASKS.md`** — the orchestrator marks the row after verifying.

## The defect, measured in production

`RateRepository.UpsertAsync`:

```sql
INSERT INTO exchange_rates (date, base, quote, rate, source)
VALUES (@Date, @Base, @Quote, @Rate, @Source)
ON CONFLICT (date, base, quote) WHERE deleted_at IS NULL DO NOTHING
```

`DO NOTHING` does not distinguish a **published** row from a `:carried-forward` placeholder. So once
a placeholder occupies a slot, the genuine rate published later that same day **can never take its
place**.

This is systematic, not occasional. ECB publishes around 16:00 CET; the rates job runs every 6 h
from process start; any deploy or restart in the morning makes the day's first pass carry forward.
The production database for **2026-09-03, base EUR** proves it:

| source | count |
|---|---|
| `cis` | 4 |
| `nbk` | 1 |
| `ecb:carried-forward` | **29** |

Twenty-nine ECB quotes for the 3rd, every one of them holding the **2nd's** rate, and no later pass
can correct them. Hard rule 3 makes `rateDate` the entry date, so a fill on the 3rd converts at the
2nd's rate — silently, and permanently.

## What to build

A **published** row must be able to supersede a `:carried-forward` row for the same
`(date, base, quote)`. Everything else stays as it is:

- a published row must **never** overwrite another published row — that is the append-only guarantee,
  and it is about real data, not placeholders;
- a carried row must not replace another carried row (nothing gained, and it churns `published_at`).

`RateSources.IsCarried(source)` already exists to make the distinction — use it rather than matching
on a string suffix at the call site.

## The fence that matters

**Entry snapshots are NOT rewritten.** Hard rule 3: *snapshots immutable, backfill fill-blanks-only*.
An entry that already converted at the carried rate **keeps that rate**, and that is correct — it is
what the user was shown and what the money pair records. This change only stops **future**
conversions inheriting a stale number. If you find yourself touching anything that rewrites a stored
`money` value, stop: that is a different task and it is forbidden by rule 3.

## Explicitly out of scope

- `CarryForwardAsync`'s own logic — it works; RV.30 confirmed the ECB majors are present.
- The `CarriedForward` counter — it reports rows inserted per pass, which is honest (RV.30).
- The backfill of missing historical dates — that is **RV.32**, a separate row.
- The feeds themselves, and any `ios/` file.

## Read before writing

1. **`CLAUDE.md`** — hard rule 3 (money is a pair, snapshots immutable) and rule 14.
2. `docs/SCHEMA.md` → **Reference data → Exchange rates**, including the rows added today for
   RV.15/RV.19/RV.20. Your change alters what `:carried-forward` means in practice — it becomes a
   *replaceable* placeholder rather than a permanent one — so the doc moves in the same change.
3. `backend/src/Tankbook.Api/Rates/RateRepository.cs`, `IRateFeed.cs` (`RateSources`),
   `RatesJobService.cs`.
4. `backend/tests/Tankbook.Api.Tests/Rates/` — the tests added today are the model: they run against
   **captured real responses** and assert the fixture itself, so a later recapture cannot quietly
   invalidate them.

## Tests

- The suite is **336 tests, 0 skipped** today; both numbers must hold.
- L2, all three cases, because the rule is a triple and any one alone is not the rule:
  - a carried row **is** replaced by a later published row for the same slot;
  - a published row is **not** replaced by another published row;
  - a carried row is **not** replaced by another carried row.
- Assert the stored `source` **and** `rate` after each, not just the row count — a replacement that
  updates the source but keeps the stale rate would pass a count-only assertion.

**Vacuous-assertion traps, named:**
- Asserting `UpsertAsync` returned 1. That tests the return value; assert what is in the table.
- Testing only the replacement case. Without the two negatives, a fix that lets anything overwrite
  anything passes — and that silently destroys the append-only guarantee.

**Mutation-check** and report it: restore the blanket `DO NOTHING` and confirm the first case fails.

## The baseline gate (CLAUDE.md rule 14)

    cd backend
    dotnet build Tankbook.slnx --configuration Release ; echo "BUILD=$?"
    dotnet format --verify-no-changes ; echo "FORMAT=$?"
    dotnet test Tankbook.slnx --configuration Release --no-build ; echo "TEST=$?"

**Judge by the exit code you echoed**, not by skimming output. `dotnet format` also fails on xUnit
analyzer warnings — fix them rather than suppressing. Testcontainers needs docker for the
Postgres-backed tests; a run printing `Passed!` with tests skipped is a shrunken gate, not a pass.

Match the process NAME if you check for a running build (`pgrep -x dotnet`). **Never `pgrep -f` or
`pkill -f`** on a build/test pattern — an agent's brief is part of its command line.

## No screenshots

Backend only. Say none applies rather than fabricating one.

## Report back

- Exit codes for build, format and test — numbers. Test count and **skipped** count.
- The three test names, and whether the mutation went red.
- Confirmation that no stored `money` value is rewritten by your change, and how you know.
- Files changed, doc sections extended, anything unfinished — named plainly.
