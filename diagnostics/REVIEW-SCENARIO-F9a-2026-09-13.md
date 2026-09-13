# REVIEW-SCENARIO run: F9a · Odometer contradicts the timeline - 2026-09-13 (re-walk, after RV.276)

**Run id:** REVIEW-SCENARIO-F9a-2026-09-13 · **Walked by:** the orchestrator (product owner, 2026-09-12: walks are not dispatched) · **Tree:** `8771bbe3`

## Verdict

**IMPLEMENTED.** The 2026-09-11c walk found every promise MET and its status line stood until
`RV.276` refined the rule it was written against: two travel entries at one reading on one
calendar day are one stop, not a conflict (the owner's 7 Oct 21 pair). The trigger sentence,
the valid-range sentence and the consumption consequence changed; each is re-walked below.
Nothing else in the journey text changed.

## Ticked rows found to be untrue

None. `RV.276` walked to code: `TimelineValidator.invariantHolds` and both CHECK 1 arms
(`TimelineValidator.swift:110-117, 269-291`) require differing calendar days before equality
between two travel entries conflicts, on the one injected calendar; `ConsumptionEngine.
coalescedBoundaries` (`:354`, called at `:299`) folds a same-reading pair into one logical fill
before the segment pass; `TimelineNeighbourhoodChartLayout` groups coincident points under one
label. The orchestrator's mutation (same-day clause dropped) went red on the pair L1. `RV.186`,
`RV.192`, `RV.117a`, `RV.231`: their tests were updated where they encoded the strict rule and
stay green.

## Promise-to-code map (the sentences RV.276 changed; the rest stands from the 11c walk)

| Promise (F9a) | Status | Evidence |
|---|---|---|
| the reading strictly increases between the kinds that MEASURE travel … and two travel entries at one reading are one stop when their dates fall on the same calendar day | MET | `TimelineValidator.swift:117`; `RV276SameStopPairTests.sameDaySameReadingIsOneStopNotAConflict` (no flag, no suggestion); the different-days case still flags (`sameReadingOnDifferentDaysStillConflicts`) |
| the valid range names an honest window - inclusive of a same-day neighbour's reading | MET | `odometerRange` / `dateRange` (`:269-291`): the bound is inclusive when the neighbour shares the day, so the card can no longer say *between 401 545 and 401 777* against a 401 544 neighbour on the same day |
| a flagged segment is excluded from consumption until resolved; a same-stop pair is NOT a flagged segment | MET | `coalescedBoundaries` merges the pair - no zero-km segment, no dropped litres, no CHECK 5 outlier; the four-drivers goldens unchanged (`ConsumptionGoldenTests`) |
| the discrepancy is shown inline with the conflicting entry quoted, ranked suggestions, keep-as-is | MET (11c) | unchanged; frames `RV.276-same-stop-pair` EN + RU opened: the pair draws as one ink point with one label, only the genuinely falling fill is amber with its sentence |
| the chart around the entry is legible when points coincide | MET | `TimelineNeighbourhoodChartLayout` groups by calendar day and dedups identical readings (`RV276CoincidentLabelTests`) |

## Sequence trace (the owner's case: two receipts from one stop)

1. Two fill-ups on 7 Oct 21 at 401 544 km (a split payment). Save of the second: CHECK 1 sees
   equal readings, both travel entries, same calendar day → no flag, no suggestion.
2. The valid-range sentence on either entry names an inclusive window; the Edit-entry card draws
   one labelled point for the pair.
3. Consumption: the pair coalesces into one fill of the summed litres closing the segment at
   401 544; the next fill's segment starts there. No exclusion, no outlier.
4. The same two readings on different days still flag, with the odometer / date suggestions.

The fact carried end to end is the calendar day: it decides the flag, the window, and the
segment.

## Proposed rows

None. The 11c walk's one proposed row (the *keep as is* clause naming the accept door) was the
owner's `RV.231` decision and stands.

## Not settled

- A same-stop pair whose two receipts disagree on the odometer by one digit (a typo on one
  slip) is two readings and flags as today - correct, and the sentence now names an inclusive
  window. Noted, not a row.
