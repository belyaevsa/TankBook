# REVIEW-SCENARIO-F6b-2026-09-12 (first walk)

**Scenario:** `F6b` - A flagged import row is fields, not a line of CSV (`docs/JOURNEYS.md`)
**Run id:** REVIEW-SCENARIO-F6b-2026-09-12

## Verdict

**IMPLEMENTED.** Every promise F6b makes is MET with a `file:line` citation. The one new
finding is a mislabelled navigation button (polish, proposed below); it is a copy defect on the
review screen's chrome, not a gap in F6b's promise, so it does not block the verdict. No ticked
row is untrue.

## Ticked rows found to be untrue

None. Walked `RV.229` (consumption outlier kind), `RV.220` (keep/leave-out flip-flop removed),
`RV.221` (station cell), `RV.263` (declared currency editable), `RV.228` (units reserved) against
the code: each is as shipped. `RV.229`'s classification is exactly the switch the row describes
(`ImportConversion.swift:424-431`), pinned by `RV229ImportConsumptionLabelTests` (L1) and
`ImportRV229UITests` (L4), both present in the tree.

## Promise-to-code map

| Stage / fallback (F6b text) | Status | Evidence |
|---|---|---|
| Renders as parsed, labelled fields - date, station, litres, price, total, odometer, note | MET | `fieldGrid` renders station/litres/price/total/odometer (`ImportReviewView.swift:261-294`); date + note in the header title (`:125-132`) |
| Only the field that is actually wrong is marked | MET | `volumeMarked`/`priceMarked` only under `.crossCheckMismatch` (`:296-304`), `odometerMarked` only under `.timelineConflict` (`:308-311`); a missing odometer marks the odometer (`ImportReviewRowFields.swift:163`, `amber = missing || marked`) |
| A missing value stays blank, never `0` | MET | `ImportOdometerCell` renders `"– km"` when nil (`ImportReviewRowFields.swift:184-188`); `.noFuel` grid renders `"– km"` (`ImportReviewView.swift:226-231`) |
| Bullet 1: cross-check marks the two operands and names the residual in money | MET | volume + price marked (`:296-304`); badge `"Off by X"` (`:137-140`); detail line quotes volume × price vs file total (`:315-333`) |
| Bullet 2: raw line one tap away behind "Original row" | MET | `showingRawLine` toggle behind the "Original row" tap (`:345-348`), renders `rawLine` (`:489-519`); unmappable/unparsed rows show the raw line directly (`:177-198`) |
| Bullet 3: a non-fill-up is offered as what it is, never discarded | MET | `.noFuel` renders `nonFuelGrid` (date/total/odometer/note, `:212-236`) beside "Import as service/expense" (`:460-466`); commit writes `.serviceRecord`/`.expense` (`ImportFlowModel+Wizard.swift:164-181`) with `provenance: .import` (`ImportConversion.swift:109,128`); `commitImport` persists both (`Repository+ArchiveImport.swift:243-256`) |

## Flag-kind walk (every kind the review card can carry)

| Kind | Fields | Sentence | Next step | import as-is | leave out | Source line |
|---|---|---|---|---|---|---|
| `.missingOdometer` | fieldGrid, odometer marked | "Odometer missing" (`:136`) | "Add odometer" → editor (`:404-417`, `:452-455`) | no (`:380-385`) | yes | `stillNeedsLook` `:462` |
| `.crossCheckMismatch` | fieldGrid, volume+price marked | "Off by X" + detail line (`:137-140`,`:315-333`) | "Fix" → total editor (`:419-433`) | yes | yes | `stillNeedsLook` `:463-466` |
| `.noFuel` | `nonFuelGrid` (`:212-236`) | "Service"/"Expense" (`:150-156`) | "Import as service/expense" (`:460-466`) | no (its action IS the keep) | yes | `partition` `:348-353` |
| `.unmappable` | raw line (`:177-187`) | "Couldn't read this row" (`:144`) | none (`:441-442`) | no | yes (always skipped `:117`) | `partition` `:358-364` |
| `.unparsed` | raw line (`:177-187`) | "Couldn't read this row" (`:144`) | none (`:441-442`) | no | yes (always skipped `:117`) | `partition` `:382-388` |
| `.timelineConflict` | fieldGrid, odometer marked | "Breaks the timeline" + quote (`:141`,`ImportReviewRowFields.swift:12-59`) | "Fix" → odometer editor (`:404-417`) | yes | yes | `timelineRows` `:432-449` |
| `.consumptionOutlier` | fieldGrid, no field marked | "Unusual consumption" + engine quote (`:142`,`:86-97`,`ImportReviewRowFields.swift:66-97`) | "Check litres"/"Check odometer" chips (`F9aFixRow`) | yes (`:383`) | yes | `timelineRows` `:424-431` |

All seven kinds are reachable from `ImportReviewClassifier.partition` (`ImportConversion.swift:316-392`); none
is `#if DEBUG`-gated. The two exits exist as distinct intents (`keep` idempotent `:103-105`, `leaveOut`
`ImportFlowModel+Wizard.swift:108-110`), no shared flip-flop (RV.220).

## Sequence trace

1. Pick file → `POST /import/parse` → `performParse` (`ImportFlowModel+Wizard.swift:490-520`).
2. Preview shows figures; "Review" row appears only when `reviewCount > 0` (`ImportPreviewView.swift:50-52`, `:422-446`).
3. Review renders each row from `model.reviewRows`, carrying `sourceRow`, `fill`/`nonFuel`, `rawLine`, `stationName` (`ImportConversion.swift:196-291`).
4. Fix/keep/leave-out mutate `odometerEdits`/`totalEdits`/`skippedSourceRows`, then `rebuildClassification()` re-partitions so a fixed odometer/total promotes the row (`ImportFlowModel+Wizard.swift:128-145`, `:387-444`).
5. "Done" → `reviewReturn()` → `.preview` (`ImportFlowModel+Wizard.swift:227-230`).
6. Preview "Import" → `confirmImport` → `commitImport(importRecords)` (`:287-342`); kept `.noFuel` rows land as service/expense, skipped rows never write.

No fact is dropped between links: `sourceRow` keys every edit and skip, `rawLine` rides to the card,
`stationName` is threaded through `ConvertedFill` to the row (`ImportConversion.swift:296-299,407,431`).
The one defect the walk surfaced is at step 5's affordance, below.

## Proposed rows

- **F6b-review-done-label** – The review screen's bottom-bar button says **"Done · back to review"**
  (`ImportReviewView.swift:56`) but `onDone` = `reviewReturn()` returns to the **preview**
  (`ImportFlowModel+Wizard.swift:227-230`). The RU string already says "Готово · к просмотру"
  ("Done · to preview", `Localizable.xcstrings:5201-5205`), so EN names a destination the button
  does not reach and EN/RU disagree – the RV.98 shape (copy names a destination that does not
  exist) at the navigation chrome rather than inside a row.
  - **Deliverable:** EN string becomes "Done · back to preview" (artboard `ImportReview.dc.html:158` updated in the same change); RU unchanged.
  - **Stage it closes:** F6b's review-screen exit (the handoff back to the gate).
  - **User consequence today:** a user finishing review reads "back to review" on the very screen they are leaving; the button works, the label is wrong.
  - **Severity:** polish.
  - **Check that makes it done:** L4 `ImportUITests` EN+RU assert the review screen's bottom-bar label reads "Done · back to preview" / "Готово · к просмотру"; localization gate 0. **Mutation:** restore the EN string; the L4 label assertion goes red.
  - **Scenario id:** F6b.

Not proposed (already owned elsewhere): the unreachable `if row.kind == .noFuel, let note = fill.note`
branch in `fieldGrid` (`ImportReviewView.swift:289-291`) is dead – `.noFuel` rows always carry
`fill == nil` (`ImportConversion.swift:348-353`) – and is the mechanical dead-code tail `RV.130`
already sweeps; no separate row.

## Anything not settled

- **`RV.264`** (open, cited in the brief) – the review header composes "These \(review) are missing
  something" with no plural form (`L10n.swift:471-473`). Confirmed still unfixed. It is polish and
  does **not** touch F6b's promise (rendering fields, not counting them); left as-is, not re-filed.
- **`commitCount` excludes non-fuel records** – the preview button and post-commit toast count
  `importFills.count` (fills only, `ImportFlowModel+Wizard.swift:183`) while `confirmImport` writes
  fills plus services/expenses. Arguably correct ("fill-ups" is F6a's stated figure, and non-fuel
  rows are visible in the review list), so not proposed; an F6a walk is the place to judge it, not
  F6b.
