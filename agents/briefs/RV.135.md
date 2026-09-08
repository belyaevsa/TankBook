# RV.135 - EUR rates older than today can never be fetched

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.

## The defect, and it is one line

Product owner, 2026-09-08: *"there are no rates for the past 10 years. Backend must request them if
unavailable."* They are right, and the whole demand path is correct **except the EUR feed**.

- `IRateFeed.FetchAsync(DateOnly date, string baseCurrency, ...)` takes a date (`IRateFeed.cs:44`).
- `RateBackfillService.cs:208` passes the requested **historical** date straight through.
- `CisRateFeed` honours it: `:106` builds `?date_req=dd/MM/yyyy`, which is what [RV.20] fixed.
- **`EcbRateFeed` ignores it.** `:17` hardcodes
  `https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml` - *today's* file - and `:47-48`
  then correctly refuses to serve it for any other date (`fileDate != date` returns empty).

So the guard is right and **no wrong rate is ever stored**; the failure is that every past EUR date
answers empty, permanently. The class comment states the assumption that fails: *"past-date
corrections use a feed that serves that date"* - and **for EUR no such feed exists.** CBR serves
RUB, NBK serves KZT, ECB is the only EUR source and it is daily-only.

This is the base the device asks on: [RV.111]'s demand drain calls `fetchSpan(base: .eur)`, so the
ask is well-formed, the queue accepts it, a pass runs, and nothing can ever come back. That is why
the owner's oldest imported rows stay rate-pending and why [RV.111]'s dead-end copy fires.

**A second cost, worth fixing in the same change**: every pending historical date currently causes a
**full GET of the daily file** which is then discarded. Fifty pending dates make fifty useless
requests to ECB.

## What ECB actually publishes

- `eurofxref-hist.xml` - the **full** daily series since 1999.
- `eurofxref-hist-90d.xml` - the last 90 days.

Confirm both URLs yourself before building on them. Design for the common case (a recent import)
using the 90-day file and the rare case (a decade-old import) using the full history.

## Design questions ALREADY CLOSED

1. **Keep the `fileDate != date` guard, in whatever shape you build.** Whatever is stored for a date
   must have come from **that date's row** in the file, never from today's. A feed that silently
   serves the wrong day would put a wrong rate into someone's cost history - hard rule 3, and far
   worse than the current absence.
2. **Do NOT widen `CarryBackWindowDays`.** It is 14, measured against CBR's New Year gap
   (`RateOptions.cs:26-34`), and carrying forward cannot help here anyway: for a 2015 date there is
   no earlier published EUR row to carry from.
3. **Bound the upstream cost.** One backfill pass asking N historical dates must **not** make N
   downloads of a history file. Fetch once per pass and satisfy every date it covers.
4. **`RateOptions.BackfillBatchSize` (50) stays** - it is what bounds the burst.

## What to build

- A historical EUR source behind the existing `IRateFeed` seam. Whether that is a second
  registered feed or one feed choosing its URL by how far back the date is, **decide and say why**.
  Both are registered the same way in `Program.cs:278-284`.
- **Write the shape into `docs/SCHEMA.md` -> Reference data -> Exchange rates** in the same change:
  which source answers which date range, and the date-guard rule.
- Mind the ordering in `RateBackfillService.cs:198-208` - it loops feeds per date. Whatever you add
  must not make the CIS feeds fetch a EUR date, or the EUR feed fetch a RUB one.

## Explicitly out of scope

- `RatesJobService` (the daily publish) and the carry-forward rule.
- The device side entirely - [RV.111] already asks correctly.
- [RV.136] (the vehicle push loop).

## Docs to read before writing (in order)

1. `docs/SCHEMA.md` -> Reference data -> Exchange rates (**the authority**).
2. `docs/API.md` -> `GET /rates/pack`.
3. `CLAUDE.md` - hard rules 3 and 12.
4. `docs/TESTING.md` -> L2, and note the ECB feed is currently **never exercised by the suite** -
   that is part of why this went unnoticed.

## Checks

Baseline: backend **423 tests**, `dotnet build` 0, `dotnet format --verify-no-changes` 0.
**Re-measure it yourself** and report what you observe.

1. `cd backend && dotnet build` - 0.
2. `cd backend && dotnet test` - 0, report the count (it must rise).
3. `cd backend && dotnet format --verify-no-changes` - 0.
4. iOS gates are **not required** - you touch no Swift. Say so rather than skipping silently.

### Tests you must add

- **L2**: a 2015 EUR date requested through `/rates/pack` is published by a backfill pass and served
  on the next request. This is the row's whole point; a test that stops at "it was enqueued" proves
  nothing.
- **L2**: the rate stored for that date equals **that date's** value in the fixture, not today's.
  Build the fixture with two different dates so a feed returning the wrong row fails.
- **L2**: one pass over many historical dates makes a **bounded** number of upstream requests -
  assert the number against a counting stub, not that it "works".
- **L1**: a date the history genuinely lacks (a weekend) resolves by the documented carry rule or
  stays absent - never guessed.

### Vacuous traps, named

- Asserting the request was **enqueued** rather than that a rate came back.
- Testing with **today's** date, which already works.
- Re-downloading the history per date and calling it fixed.
- **Removing the `fileDate != date` guard** to make dates resolve - that trades an absence for a
  wrong number in someone's money history.
- Asserting the feed returns non-empty without asserting **which** date's values it returned.

## Never `pgrep -f` for a build process

Your brief is part of your command line. Use `pgrep -x dotnet`. Never `pkill -f`.

## Report back

Every check with the **exit code you observed**, whether each test was **run or only written**,
which of the two designs you chose for the historical source and why, and the measured number of
upstream requests one pass makes. Name any closed decision you think is wrong and stop there.
