# REVIEW-SCENARIO run: F2 · Scan recognized wrong data - the most dangerous failure - 2026-09-12c (re-walk, after RV.270)

**Run id:** REVIEW-SCENARIO-F2-2026-09-12c · **Walked by:** the orchestrator (product owner, 2026-09-12: walks are not dispatched) · **Tree:** `701c0a26`

## Verdict

**IMPLEMENTED.** The previous walk (`REVIEW-SCENARIO-F2-2026-09-12.md`) found every promise MET; its status line was cleared
on 2026-09-12 when `RV.270` surfaced - an open v1 row the walk had read as the shipped `RV.243`
because both carried that id. `RV.270` is shipped (`701c0a26`); the one stage it touched is
re-walked below. Nothing else in the journey text changed.

## Ticked rows found to be untrue

None. `RV.270` walked to code: `FuelKindNormalizer.isBoilerplate` (`FuelKindNormalizer.swift:97`)
runs before any fuel token is read in `isProductLine` (`:72`) and `normalize` (`:128`); it rejects
the unit legend (*для нефтепродуктов* / *для КПГ*), the `1 ед.=` shape and slash-lists. The
orchestrator's mutation (guard off) turned the `receipt-062` L1 red on `fuelKind → .lpg`.

## Promise-to-code map (the stage RV.270 touched)

| Promise | Status | Evidence |
|---|---|---|
| The residue - a confident-wrong pre-fill (a fuel kind from till boilerplate) is the F2 shape the walk of 2026-09-12 could not see, because its row hid under a shipped id | MET | `receipt-062` now abstains (nil) instead of committing `lpg`; `receipt-063` still resolves petrol95 (`RV270FuelKindBoilerplateTests` 3/3); the whole-class check `noReceiptCommitsAFuelKindItsExpectedContradicts` fails the next boilerplate read; the harness stays at 255/300 because the wrong kind and the abstention miss the same cell - the score could not see this defect, the contradiction check does |
| the normalizer is not taught the OCR glyph | MET | no `МИ95` vocabulary added; the fix is where a kind may come FROM, not what it looks like |
| an abstention is an empty field the user fills, never a fact | MET | nil kind renders the Confirm chip row unselected (hard rule 13 - a default input) |

## Proposed rows

None. `ReceiptNoiseFilter`'s `unitConvention` pattern still misses OCR-damaged `ед` spellings,
so the legend line reaches the value finders (it no longer sets a kind); a noise-filter decision,
noted in RV.270's tick, not a promise of this story.
