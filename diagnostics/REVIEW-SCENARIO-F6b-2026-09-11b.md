# REVIEW-SCENARIO: F6b · second walk (RV.220 + RV.221 + RV.191, commit 7d4e1fc6)

- **Run:** REVIEW-SCENARIO-F6b-2026-09-11b
- **Scenario:** `F6b` (`docs/JOURNEYS.md:609`)
- **Prior run:** `REVIEW-SCENARIO-F6b-2026-09-11` (NOT IMPLEMENTED, defects R1/R2)
- **Verdict: IMPLEMENTED**

## Ticked rows found to be untrue

None. RV.220 and RV.221 are true as walked (below).

## The two prior defects, re-walked

| Prior finding | Was | Now |
|---|---|---|
| R1 – keep and leave-out share one toggle | `importAsIs`/`leaveOut`/`.noFuel` all called `toggleSkipped`, so a keep tap dropped the row | `keep(sourceRow:)` un-skips idempotently (`ImportFlowModel+Wizard.swift:162-164`), `leaveOut(sourceRow:)` is the only skip (`:167-169`); `importAsIs` → `keep` (`ImportReviewView.swift:375`), `leaveOut` → `leaveOut` (`:382`), `.noFuel` primary → `keep` (`:423`), `skipAll` → `leaveOut` (`:48-51`). **MET** |
| R2 – station rendered nowhere | `fieldGrid` had no station cell; carried end-to-end but shown only in the Log | `ImportReviewRow.stationName` (`ImportConversion.swift:213`) threaded from `candidate.trimmedStation` → `ConvertedFill.stationName` → `partition`/`timelineRows` (`:358`, `:398`, `:405`, `:422`); `fieldGrid` renders `ImportStationCell` when non-empty (`ImportReviewView.swift:248-250`). **MET** |

## Promise-to-code map (re-check of prior PARTIAL/MISSING rows only)

| Journey promise | Status | Evidence |
|---|---|---|
| Row renders parsed, labelled fields - date, **station**, litres, price, total, odometer, note | **MET** | station cell `ImportReviewView.swift:248-250` + `ImportStationCell` (`ImportReviewRowFields.swift:94-105`); litres/price/total/odometer `:251-277`; date+note in header title `:112-119`. Seven fields present on a fill row; the `.noFuel` field list (date/total/odometer/note) matches the journey's non-fill bullet - station is a fill field only. |
| A non-fill row is offered as what it is, commits as service/expense with `provenance = .import`, never silently dropped | **MET** | `.noFuel` primary action is `keep` (`ImportReviewView.swift:418-424`); a kept row commits via `importRecords` (`ImportFlowModel+Wizard.swift:223-240`); only `leaveOut` skips. The inversion is gone. |

Unchanged MET rows from the first walk (marker-only, blank-never-0, raw line one tap away) were not re-opened by the diff: `volumeMarked`/`priceMarked`/`odometerMarked` (`ImportReviewView.swift:281-296`), `ImportOdometerCell` blank `– km` and `ImportFieldCell` unchanged except the new `valueLineLimit` parameter.

## Sequence trace

1. Pick export → parse → server returns candidates + unparsed rows (F6/F6a). Unchanged.
2. Preview → "N rows need a look" → Review. Unchanged.
3. `rebuildClassification` → `ImportReviewClassifier.partition` mints rows with `stationName` threaded (`ImportConversion.swift:357-358`, `:398-422`).
4. Row renders parsed fields incl. station; one broken field amber; blank `– km`, never `0`.
5. `.noFuel` row shows date/total/odometer/note + "Import as service" (keep) + "Leave out" (skip).
6. Done → preview → Import → `importRecords` writes kept fills + service/expense records.

Where a fact stops being carried:
- **Station** is now displayed at step 4 (RV.221) - the earlier display gap is closed; no data loss.
- **The user's keep/drop intent** is now carried at step 5 (RV.220): keep is idempotent, leave-out is the only skip. The inversion that lost "the user wants this row" before step 6 is gone.

## Proposed rows

None. R1/R2 are closed by RV.220/RV.221; no new missing promise found in the re-check scope.

## Not settled

- **Volume/price remain the marked operands of a cross-check mismatch but only the total is editable** ("Fix" opens `ImportTotalEditorCell`, `ImportReviewView.swift:403-417`). Unchanged from the first walk, still a product call: whether the review list should also edit volume/price, or total-only is intended. The journey's "an extracted value becomes an editable field" sentence is rendered, not a per-field text-box promise; the first walk left this open rather than filing it, and it is outside this run's re-check scope.
- **Default keep vs left-out** (first walk "not settled" #2) is now resolved by RV.220 in favour of default-kept: a fresh `.noFuel` row is not skipped (`ImportFlowModel+Wizard.swift:171-179`), so an untouched row commits. Consistent with "never silently dropped at commit" and the ≥60% resolve metric.
