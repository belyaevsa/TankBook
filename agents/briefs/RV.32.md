# RV.32 – a foreign entry dated before today can never resolve its home amount

Backend only. Touch no `ios/` file — another agent is working there.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`. **Do not run `git add` or `git commit`.**
**Do not touch `docs/TASKS.md`.**

## The defect, every link verified

A user's fill dated **2 Sep** in EUR, on a RUB-home car, shows `IN RUB ≈ –  converts when online`
and `1 entry pending rates` — **forever**, not "until it syncs":

1. Hard rule 3 makes `rateDate` the **entry** date, so it needs EUR→RUB **for 09-02**.
2. No such row exists. The `cis` feed had never parsed a single response until RV.15 landed on
   2026-09-03, so there is **no RUB history before that date at all**.
3. Nothing will ever create it. `RatesJobService` calls `feed.FetchAsync(today, ...)` — **only
   today** — and `CarryForwardAsync` fills **forward** from the first published date; it never walks
   backwards.
4. The client is not at fault: `RateStore.packWindowDays` is 400 and it already asks
   `GET /v1/rates/pack?from=&to=`. The server simply has nothing for those dates.

## What to build

A backfill that fetches the dates we are missing. Both feeds already support it and both were
verified against a past date on 2026-09-03: CBR `?date_req=dd/MM/yyyy`, NBK `?fdate=dd.MM.yyyy`.

### It is DEMAND-DRIVEN, not a fixed window (product owner, 2026-09-03)

The trigger is *"a date we are asked for has no rate"*, **not** a rolling N days. The reason is
**import**: `POST /import/parse` lets a user bring in years of MFM history in one action, and a
400-day ceiling would leave everything older permanently pending — this same bug, one day later.

**The natural trigger already exists**: `GET /v1/rates/pack?from=&to=` is what the device asks, and
it is exactly the statement "I need these dates". Recommended shape — **serve what exists now, record
the gap, fill it in the background, let the device pick it up on its next refresh** (it already
refreshes on foreground, and PJ.8 backfills rate-pending entries silently when a rate arrives).
**Do not block the response on an upstream fetch**: 400 dates × 2 feeds is 800 requests and the
device is waiting.

**State in your report which shape you built**, and why.

### The gap rule: carry BACK, bounded at 14 days

A date with no published rate takes the **most recent earlier** known rate — look backwards only,
because the rate in force on the day of the fill already existed; a later one did not. Store it
`:carried-forward`, never `published` (RV.20), and note **RV.36 just landed**, so a real rate
published later can now supersede that placeholder.

**14 days, and the number is measured, not assumed.** CBR does not publish across the Russian New
Year: `date_req` for 01, 05, 08, 09, 10 and 12 January 2026 all return the document dated
**31.12.2025**, and the first January document is **13.01.2026** — a **13-day gap**. A 7-day window
would leave six days of January permanently unresolved in **RUB**, a home currency for this app.
Pin that window as a test; the holiday document is already captured at
`backend/tests/Tankbook.Api.Tests/Rates/Fixtures/cbr-xml-daily-2026-01-04-holiday-windows1251.xml`.

**The bound is not decoration.** Without it, an entry predating all rate history would silently take
some unrelated rate instead of staying honestly pending. A visible gap beats a plausible wrong
number in someone's cost history.

## Four things to get right

- **Bound the burst, dedupe, and be resumable.** A five-year import is ~1800 upstream requests. A
  backfill that restarts from zero on every deploy is its own outage. The insert is already
  `ON CONFLICT`, so idempotency is free — restartability is not.
- **A weekend needs no bookkeeping.** The carry-back rule resolves it from Friday and it is
  finished, so there is no "asked and got nothing" state to remember and no retry loop.
- **Carrying back must not hide a broken feed.** RV.15 went unnoticed for weeks precisely because
  nothing downstream looked wrong. `SourcesFailed` must still be reported while gaps are filled.
- **Never invent a rate.** Every stored row is either a real document for that date (`published`) or
  an explicit carry-back inside the window (`:carried-forward`). There is no third case.

## Explicitly out of scope

- The client. `RateStore` already asks for what it needs; **touch no `ios/` file.**
- `RateRepository.UpsertAsync`'s conflict clause — RV.36, landed today.
- The feeds' parsing — RV.15/RV.19/RV.20, landed today.

## Read before writing

1. **`CLAUDE.md`** — hard rule 3 (money is a pair; `rateDate` is the entry date; snapshots
   immutable) and rule 14.
2. `docs/SCHEMA.md` → **Reference data → Exchange rates**, including today's RV.15/19/20/36 bullets.
   Your change adds backfill to what that section promises; it moves in the same commit.
3. `docs/API.md` → the rates endpoints, if you change either one's behaviour.
4. `backend/src/Tankbook.Api/Rates/` — `RatesJobService.cs`, `RateEndpoints.cs`,
   `RateRepository.cs`, `CisRateFeed.cs`, `NbkRateFeed.cs`.
5. `backend/tests/Tankbook.Api.Tests/Rates/` — today's tests are the model: captured **real**
   responses, with the fixture itself asserted so a later recapture cannot quietly invalidate them.

## Tests

- **339 tests, 0 skipped** today; both numbers must hold. Testcontainers needs docker.
- L2, against captured fixtures:
  - a requested date with no row is fetched and stored **published** when a real document exists;
  - a date inside a publication gap is stored **carried-forward** from the most recent earlier rate;
  - a date **more than 14 days** past the last known rate is left **absent**, not invented;
  - the January window resolves end to end — 07.01.2026 gets 31.12.2025's rate, and 13.01 gets its own.

**Vacuous-assertion traps, named:**
- Asserting a row exists. Assert its **`rate` and its `source`** — a carried row holding the wrong
  day's value, or a published label on a carried value, both pass an existence check.
- Asserting the backfill "ran". Assert what is in the table afterwards.
- Testing only the happy path. The 14-day bound and the do-not-invent rule are the ones that protect
  a user's money.

**Mutation-check and report**: remove the bound, and confirm a far-past date stops being left absent.

## The baseline gate (CLAUDE.md rule 14)

    cd backend
    dotnet build Tankbook.slnx --configuration Release ; echo "BUILD=$?"
    dotnet format --verify-no-changes ; echo "FORMAT=$?"
    dotnet test Tankbook.slnx --configuration Release --no-build ; echo "TEST=$?"

**Judge by the exit code you echoed.** `dotnet format` fails on xUnit analyzer warnings — fix rather
than suppress. A run printing `Passed!` with tests skipped is a shrunken gate, not a pass.

Match the process NAME (`pgrep -x dotnet`). **Never `pgrep -f` or `pkill -f`** on a build/test
pattern — an agent's brief is part of its command line.

## No screenshots

Backend only. Say none applies rather than fabricating one.

## Report back

- Exit codes for build, format, test — numbers. Test count and **skipped** count.
- **Which trigger shape you built** (background fill vs on-demand) and why.
- How you bounded the burst and made it resumable.
- The mutation result for the 14-day bound.
- Files changed, doc sections extended, anything unfinished — named plainly.
