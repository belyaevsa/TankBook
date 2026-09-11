# RV.158 + RV.138 - the rate drain and the carry-forward, one problem from two sides

**Scenario: F9 · currency rate unavailable for that date.** The two v1 rows holding F9 open. One
brief because they are the same multi-year-span problem: the client drains a span the server has
nothing for, and the server's carry-forward will fill any span it is given with a row per day.

## RV.158 - the client

`RateStore.fetchSpan` (`RateStore.swift:247-274`) walks a span in `packWindowDays = 400` chunks,
no pacing, no early exit: eight `/v1/rates/pack` requests in seven milliseconds, seven answered
empty (63 bytes) in 0-1 ms. An empty answer is indistinguishable from a served one, so the drain
that exists to resolve rate-pending rows cannot, no matter how often it runs. **Two halves**: the
client should stop walking once the server says "nothing before date X" - which needs the pack
response to carry its **coverage floor** (check `docs/API.md` for whether it already does; if not,
that is a one-field additive change, not a breaking one - say so); and the client should pace and
dedupe - one in-flight span per currency pair.

## RV.138 - the server

`RatesJobService.CarryForwardAsync` (`:104-125`) walks from the OLDEST published row to today for
every quote, inserting a row per gap day. `RV.135`'s deep backfill makes 2015 reachable: ~4,000
dates x ~30 quotes on one pass. Stepwise, not a smeared 2015 rate - a volume and occupancy problem,
not a wrong-number one. **Give it a horizon** tied to what devices can ask for, and make the walk
resumable so one pass never does years.

## Tests

Client **L1, FAILS TODAY**: a span whose floor the server states stops at the floor; a second
`fetchSpan` for the same pair while one is in flight does not issue requests. Backend: the
carry-forward respects its horizon and is idempotent across passes; `dotnet test` count reported.
**No `docs/API.md` breaking change** - if the floor field is new, document it as additive.

## Mutations - named

Client: remove the floor early-exit; the L1 goes red. Server: remove the horizon; the bounded-pass
test goes red. Verbatim, both.
