# RV.229 - the import review labels a consumption outlier "Breaks the timeline"

**Scenarios: F6b · a flagged import row is fields, F2 · the residue.** Small; the seam is named.

`ImportConversion.classify` (`ImportConversion.swift`, re-find by `.timelineConflict`) maps EVERY
validation flag to `.timelineConflict`, whose row label is *Breaks the timeline*
(`ImportReviewView.swift:128`) and whose *Fix* opens the odometer editor. A `.consumption` flag
(`RV.218`'s `ConsumptionOutlier`, CHECK 5) therefore surfaces under the wrong words with the wrong
next step - the litres may be the misread field. Hard rule 7.

## Build

Give the import review its own kind for a consumption flag: label *Unusual consumption*, next
step *check litres / odometer*, through the same `F9aFixRow` vocabulary `RV.218` reused on the
edit screen - one classification switch, one label table, EN + RU full phrases. A row carrying
BOTH a timeline flag and a consumption flag keeps the timeline kind (the timeline is the harder
error); say so in the switch.

## Tests

- **L1, FAILS TODAY**: a candidate whose validation carries only a `.consumption` flag
  classifies to the new kind, not `.timelineConflict`; one carrying both classifies to timeline.
- **L4 `ImportUITests` EN + RU** on a seeded absurd-litres row: the review shows the new label
  and its next step. Screenshots `RV.229-import-review-consumption` EN + RU, dark.

## Mutation - named

Map `.consumption` back to `.timelineConflict`; the L1 goes red. Verbatim.
