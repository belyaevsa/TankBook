# REVIEW-SCENARIO: F6b · A flagged import row is fields, not a line of CSV

- **Run:** REVIEW-SCENARIO-F6b-2026-09-11
- **Scenario:** `F6b` (`docs/JOURNEYS.md:605`)
- **Row that named it:** `PJ.9` (closed, `docs/TASKS-DONE.md:341`)
- **Verdict: NOT IMPLEMENTED**

## Ticked rows found to be untrue

None. `PJ.9` and `P6.15` are both true as walked: the non-fill commit path writes a
`ServiceRecord`/`Expense` with `provenance = .import` (`ImportFlowModel+Wizard.swift:222-239`,
`ImportConversion.swift:96-130`), and an unreadable row shows the original delimited line, never
the wire envelope (`ImportReviewView.swift:164-185`). The defects below are **new**, not a ticked
row.

## Promise-to-code map

| Journey promise | Status | Evidence |
|---|---|---|
| Row renders parsed, labelled fields (date, **station**, litres, price, total, odometer, note), never raw CSV | **PARTIAL** | `fieldGrid` renders Litres/Price/Total/Odometer (`ImportReviewView.swift:248-276`), date+note in the header title (`:114-121`); **station is rendered nowhere** (not in `fieldGrid`, not in `nonFuelGrid`, not in `ImportReview.dc.html`). Station is carried end-to-end (`ImportCandidate.station` → `stationId` → commit, `ImportConversion.swift:53-66`) but never displayed at review. |
| Only the broken field carries the marker | **MET** | missing odometer → amber odometer cell (`ImportOdometerCell`, blank `– km`, `ImportReviewRowFields.swift:105-132`); cross-check → `volumeMarked`/`priceMarked` amber + "Off by X €" badge and `crossCheckDetail` (`ImportReviewView.swift:278-315`, `L10n.swift:486-508`); timeline → `odometerMarked` (`:290-293`) with the neighbour quoted (`ImportReviewRowFields.swift:43-55`). |
| A missing value stays blank, never `0` | **MET** | `ImportOdometerCell` renders `– km` when `odometer == nil` (`ImportReviewRowFields.swift:127-131`); `nonFuelGrid` renders `– km` (`ImportReviewView.swift:214-218`); absent volume/price/total drop the cell rather than printing `0` (`:250-266`). |
| The raw line stays one tap away behind "Original row" | **MET** | "Original row" `onTapGesture` toggles `rawLineView` (`ImportReviewView.swift:325-333`, `:469-499`); unmappable/unparsed rows show the line inline (`:164-185`) - the "mapping is wrong" case F6b names. |
| A non-fill row is offered as what it is, commits as service/expense with `provenance = .import`, never silently dropped | **PARTIAL** | The row renders date/total/odometer/note (`nonFuelGrid`, `:199-223`) beside "Import as service"/"Import as expense" (`:440-446`, `L10n.swift:528-533`), and `importRecords` writes the right kind (`ImportFlowModel+Wizard.swift:222-239`). **But the action is a toggle that drops the row** - see defect R1 below. |

## Defects found (the point of this run)

**R1 – "Import as service" / "Import as expense" / "Import as-is" are each the same toggle as
"Leave out".** Every one of the four "keep" affordances calls `model.toggleSkipped` (`importAsIs`
`:375`, `leaveOut` `:382`, the `.noFuel` primary action `:423`), and `toggleSkipped` flips
membership in one `skippedSourceRows` set (`ImportFlowModel+Wizard.swift:161-167`). A flagged row
defaults to **kept** (`isSkipped` returns `false` for a fresh parse, `:169-178`; the PJ.9 test
commits a service by tapping Done→Import with no "Import as service" tap,
`ImportUITests.swift:245-259`). So tapping the keep button in the default state **skips** the row:
the user reads "Import as service", taps it to keep the row, and it is silently left out. The two
opposite buttons flip one bit; "keep" cannot be expressed distinctly from "drop".

**R2 – the review row never renders the station field the journey lists.** `fieldGrid` has no
station cell and neither does `nonFuelGrid` or the artboard `ImportReview.dc.html` (Litres/Price/L/
Total/Odometer/Note only). A user approves a fill without seeing which station it was mapped to;
the station only surfaces in the Log title after commit (RV.189).

## Sequence trace

1. Pick export → parse → server returns candidates + unparsed rows (F6/F6a).
2. Preview shows figures; "N rows need a look" → Review (`ImportPreviewView.swift:421-445`).
3. `rebuildClassification` → `ImportReviewClassifier.partition` mints `ImportReviewRow`s
   (`ImportFlowModel+Wizard.swift:438-495`, `ImportConversion.swift:291-366`).
4. Row renders parsed fields; the one broken field is amber; a blank is `– km`, never `0`.
5. noFuel row shows date/total/odometer/note + "Import as service" + "Leave out".
6. Done → preview → Import → `commitImport` writes kept fills + service/expense records.

Where a fact stops being carried:
- **Station** is carried parse→candidate→`stationId`→commit (RV.189 fixed the merge drop in
  `ImportBatchMerge.remappingSourceRow`) but is **not displayed** at steps 3-5 - display gap, no
  data loss.
- **The user's keep/drop intent is inverted at step 5** (R1): a "keep" tap toggles the row to
  "left out", so the fact "the user wants this row" is lost before step 6.

## Proposed rows (all attach to F6b)

**R1 – distinct keep vs leave-out actions.** Deliverable: `Import as service`, `Import as expense`
and `Import as-is` become "keep" actions that *un-skip* the row; `Leave out` is the only action
that skips it; the two no longer share one `toggleSkipped`. Stage closed: F6b "offered as what it
is … shown, never silently dropped at commit". Consequence today: a user who taps a keep button
silently loses the row (hard rule 8). Severity: **bug**. Check: L4 `ImportUITests` - seed a noFuel
row, tap "Import as service", Done→Import, assert the service lands in the Log; seed again, tap
"Leave out", assert it does not; EN+RU. Mutation: restore the shared toggle and the keep-button
case fails.

**R2 – render the station field on the review row.** Deliverable: `fieldGrid` gains a station cell
so a fill row renders the file's station name beside litres/price/total/odometer; reconcile the
journey's field list with `ImportReview.dc.html` (or draw the cell). Stage closed: F6b "renders as
parsed, labelled fields - date, station, …". Consequence today: the user approves a fill without
seeing which station it maps to; a wrong station surfaces only in the Log after commit. Severity:
**gap**. Check: L4 `ImportUITests` - a seeded fill whose candidate carries a station renders the
station name in the review row, EN+RU (the RU case is where a long free-text station name will
truncate).

## Not settled

- **Volume/price are the marked operands of a cross-check mismatch but only the total is editable**
  ("Fix" opens `ImportTotalEditorCell`, `ImportReviewView.swift:403-417`). If the file's volume or
  price is the wrong value, the user must import-as-is or leave the row out. Whether the review
  list should also edit volume/price, or total-only is the intended design, is a product call.
- **Whether a flagged row should default to "kept"** (import as-is unless the user leaves it out)
  or to "left out" (the user must actively keep it). This determines whether R1's fix is
  "make keep un-skip" or "make the default explicit"; both are reachable once the two buttons stop
  sharing a toggle.
