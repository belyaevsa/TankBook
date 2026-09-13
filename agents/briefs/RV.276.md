# RV.276 - two fill-ups at one reading on one day flag each other

**Scenarios: F9a · odometer contradicts the timeline, J3 · the 5-second fill-up.** `[!]`.
Reported by the product owner 2026-09-13 with a screenshot: a fill-up at 401 544 km on 7 Oct 21
is flagged because the previous entry that day is another fill-up at 401 544 km; the card says
*the odometer must be between 401 545 and 401 777* and *no date between the neighbouring entries
works - check the odometer*. The odometer is right; the rule is wrong.

`RV.186` let an annotation (service, expense) share a reading but kept the strict increase
between two entries that MEASURE travel (`TimelineValidator.swift:110`:
`odo == previousOdo && measuresTravel(entry) && measuresTravel(previous)`). Two receipts from one
stop - a split payment, two products, the corpus's own `receipt-062`/`receipt-063` two minutes
apart at one till - are the same reading by construction and always conflict.

## Build

1. **The rule**: equality between two travel entries is a conflict only when their DATES differ;
   on one day it is one stop. Record it in `docs/SCHEMA.md` beside the invariant RV.186 wrote,
   and in `docs/JOURNEYS.md` F9a's text if it names the rule. The valid-range sentence
   (`RV.117a`) follows: with a same-day same-reading neighbour the window's bound is inclusive.
2. **The consumption math**: a zero-distance segment between two fills is one stop - fold the
   volumes into the next real segment; never divide by zero, never a CHECK 5 outlier, never an
   excluded entry. Read `ConsumptionEngine` and the four-drivers golden vectors
   (`docs/SCHEMA.md` → consumption) - the goldens must not move; add a case.
3. **The chart**: `TimelineNeighbourhoodCard.swift` overprints the labels of coincident points
   (`401 778 km` drawn over `401 544 km` at a shared x). Coincident points get one stacked label
   block, the same fix RV.188 made for the Trends chart - reuse its placement if it is shared,
   say so if it is not.

## Tests

- **L1, FAILS TODAY**: two fills, same day, same odometer - neither flagged, no suggestion;
  same odometer, different days - flagged as today (the vacuous trap is allowing both).
- **L1**: consumption over a zero-km pair equals the merged single fill's; the goldens unchanged.
- **L4 `EditEntryUITests` EN + RU** on a seeded pair (`TimelineNeighbourhoodTestSeed`): no amber
  on either entry, the chart's coincident labels legible. Screenshots
  `RV.276-same-stop-pair` EN + RU, dark.

## Mutation - named

Strict again (drop the same-day clause); the first L1 goes red. Verbatim.
