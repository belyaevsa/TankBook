# RV.19 + RV.20 – the CIS rate feed serves one currency of five, and ignores its date

Two rows, **one brief and one PR**, because both live in
`backend/src/Tankbook.Api/Rates/CisRateFeed.cs` and dispatching them separately would collide.

Backend only. Touch no `ios/` file.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`. **Do not run `git add` or `git commit`.**

## Write code first, explore second

Both diagnoses are complete and were verified against the live feeds on 2026-09-03. Confirm them in
the code, then write.

## RV.20 – the feed ignores the date it is handed

`FetchAsync(date, baseCurrency, ct)` fetches the feed's **default** document (always today's) and
then returns `[]` unless the document's own `Date` attribute equals `date`.

CBR supports `?date_req=dd/MM/yyyy` and serves the requested day - **verified**:
`https://www.cbr.ru/scripts/XML_daily.asp?date_req=15/08/2026` returns `<ValCurs Date="15.08.2026"`.
The code never passes it.

- **Latent, not live**: `RatesJobService` only ever asks for `today`, so nothing is wrong in
  production right now. It becomes real the moment anything backfills, and hard rule 3 makes
  `rateDate` the **entry** date, so backfill is a question of when.
- **One symptom IS live**: on a weekend or holiday CBR serves the last published document, dated
  Friday. The `fileDate != date` guard throws that away entirely rather than using it as the last
  published rate. Carry-forward covers the gap, so the waste is invisible.

Pass the requested date. Then decide, and **write down which you chose**: does a document dated
*earlier* than the request count as that day's rate (the last published value, which is what
carry-forward would have produced anyway), or as nothing? Either is defensible; silently keeping
today's behaviour is not.

## RV.19 – four of the five currencies are thrown away, and KZT should not come from Moscow

`docs/SCHEMA.md` says the CIS source covers **RUB/KZT/AMD/GEL/BYN**. The method ends:

```csharp
return [new RateQuote("RUB", rubPerEur)];
```

Its own comment says the rest "would need cross-rates; a production feed serves them directly in EUR
base, which is a feed swap, not a code change." **That comment is now out of date**: the CBR
document already carries all five, measured from the committed fixture on 2026-09-03 —

| code | nominal | value (RUB) |
|---|---|---|
| KZT | 100 | 18.9762 |
| AMD | 100 | 23.8909 |
| GEL | 1 | 33.1414 |
| BYN | 1 | 28.3496 |
| EUR | 1 | 100.8287 |

so the cross-rate through RUB is arithmetic you already have:
`quotePerEur = rubPerEur / (value / nominal)`.

**But for KZT that is the wrong number.** The cross-rate gives **531.34 KZT/EUR**; the National Bank
of Kazakhstan's own official rate for the same day is **526.99** — **0.8% apart**, about 40 KZT on a
4800 KZT fill, and NBK is the authoritative rate for a currency Kazakh users actually spend.

**Add a second feed, `NbkRateFeed`**, registered as its own `IRateFeed` beside the others in
`Program.cs` (~line 274), with its own `RateSources` tag. Verified endpoints:

- `https://nationalbank.kz/rss/get_rates.cfm?fdate=dd.MM.yyyy` — **UTF-8** (no windows-1251 trap),
  `<item>` elements with `<title>EUR</title>`, `<description>526.99</description>`, `<quant>1</quant>`.
  A past date works: `fdate=15.08.2026` returns `536.18`.
- It quotes **X per KZT**, so EUR-base needs the same inversion shape as above. Read `<quant>`; do
  not assume 1.

A separate feed, not a branch inside `CisRateFeed`, so a failure in one cannot take the other down -
`RatesJobService` already counts `SourcesFailed` per feed.

**Do not silently prefer one source per currency without recording why.** `exchange_rates.source` is
already a column; two sources disagreeing by 0.8% is data a user may one day have to reconcile.
State in your report what happens when both publish KZT for the same date.

## Explicitly out of scope

- `EcbRateFeed`, the carry-forward logic, the `/v1/rates` endpoint shape, the client.
- The windows-1251 registration (RV.15, already done - do not undo the static constructor).
- Any `ios/` file.

## Read before writing

1. **`CLAUDE.md`** - hard rule 3 (money is a pair; `rateDate` = entry date), rule 12 (never log
   domain values - a rate is reference data and loggable as shape, a user's amount is not), rule 14.
2. `docs/SCHEMA.md` → **Reference data → Exchange rates**, including the RV.15 paragraph added
   2026-09-03 naming the CBR encoding.
3. `backend/src/Tankbook.Api/Rates/` - `IRateFeed.cs` (the `RateQuote` contract and `RateSources`),
   `CisRateFeed.cs`, `RatesJobService.cs`.
4. `backend/tests/Tankbook.Api.Tests/Rates/CisRateFeedEncodingTests.cs` - **the model to follow**:
   tests run against a real captured response, and the fixture itself is asserted so a later
   recapture cannot quietly invalidate the test.

Extend `docs/SCHEMA.md` in the same change, and mark both rows in `docs/TASKS.md`.

## Tests

Capture real responses as fixtures next to
`backend/tests/Tankbook.Api.Tests/Rates/Fixtures/cbr-xml-daily-windows1251.xml` and wire them in the
csproj the same way. Then:

- The cross-rate arithmetic pinned **against a fixture**, not recomputed in the assertion - an
  assertion that redoes the division passes against any division, including the wrong one. Assert the
  expected KZT/AMD/GEL/BYN values you worked out by hand from the table above.
- A past date returns **that day's** quotes (RV.20), against a fixture captured for that date.
- The weekend case asserted separately, matching whichever answer you chose.
- NBK parses, and its EUR quote is a positive number - **and** that it differs from the CBR
  cross-rate, which is the whole reason the feed exists.

**Vacuous-assertion traps, named:**
- Asserting only "not empty". The broken feed returned a non-empty list too - it had RUB.
- Recomputing the expected value with the same formula the code uses. Both would be wrong together.
- A fixture saved as UTF-8 for the CBR feed - that silently removes the RV.15 regression coverage.

**Mutation-check both fixes** and report whether you saw each test go red: drop the `date_req`
parameter, and drop the cross-rate loop.

## The baseline gate (CLAUDE.md rule 14)

    cd backend
    dotnet build Tankbook.slnx --configuration Release ; echo "BUILD=$?"
    dotnet format --verify-no-changes ; echo "FORMAT=$?"
    dotnet test Tankbook.slnx --configuration Release --no-build ; echo "TEST=$?"

**Judge by the exit code you echoed.** The suite is **316 tests, 0 skipped** today; both numbers must
hold. A run printing `Passed!` with tests skipped is a shrunken gate - Testcontainers needs docker.

`dotnet format` also fails on xUnit analyzer warnings; fix them rather than suppressing.

Match the process NAME if you check for a running build (`pgrep -x dotnet`). **Never `pgrep -f` or
`pkill -f`** on a build/test pattern - an agent's brief is part of its command line.

## No screenshots

Backend only. Say none applies; do not fabricate one.

## Report back

- Exit codes for build, format, test - numbers, not prose. Test count and **skipped** count.
- The new test names, and whether you saw each mutation go red.
- The expected cross-rate values you derived, and how you derived them.
- What happens when CBR and NBK both publish KZT for the same date.
- Which answer you chose for a document dated earlier than the request, and why.
- Files changed, doc sections extended, anything unfinished - named plainly.
