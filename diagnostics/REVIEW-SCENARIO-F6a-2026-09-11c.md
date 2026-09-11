# REVIEW-SCENARIO run: F6a – 2026-09-11c

- **Scenario:** F6a (`docs/JOURNEYS.md:552`)
- **Run id:** REVIEW-SCENARIO-F6a-2026-09-11c
- **Verdict:** NOT IMPLEMENTED

---

## Ticked rows found untrue

None. Every `[x]` row this scenario rides on is true in the code: PJ.9 (non-fill
rows commit), PJ.10 (date-format question), RV.86 (multi-car mapping), RV.93
(export-not-file), RV.185 (new-car name + home currency), RV.116 (NOT IMPORTED
notice), RV.189/RV.221 (station name in review row). P5.5b, the row that owns the
preview, is honestly `[~]` – it already names the units/currency picker as
half-met. The gap below is not a ticked row lying; it is a sentence in F6a with
no row and no code, and a `[~]` note that was not updated when the currency half
landed.

---

## Promise-to-code map

| # | F6a promise | Verdict | Evidence |
|---|---|---|---|
| 0 | Server returns candidates; garage untouched until confirm (intro) | MET | `ImportFlowModel.swift:8-12` (one write named); `ImportFlowModel+Wizard.swift:346` `confirmImport`; `ImportTests.swift:249` `nothingIsWrittenBeforeConfirm` |
| 1a | Fill-up count / date range / odometer span / total spend | MET | `ImportPreviewView.swift:116-129`; `ImportConversion.swift:492` `ImportSummary.compute` |
| 1b | Detected currency | PARTIAL | Shown (`ImportFormatting.swift:76-80`) but only adjustable in the no-column case – see finding 2 |
| 1c | Detected units | MISSING | Units are the destination car's, hardcoded metric; the file's `units` payload is emitted (`MfmParser.cs:437`) and never read by the client (`ImportService.swift:155-156`) |
| 1d | Derived consumption as the headline | MET | `ImportPreviewView.swift:85-107`; `ImportConsumption.compute` calls `ConsumptionEngine.recompute`+`lifetime` (`ImportConversion.swift:18-23`) |
| 2 | Say where it lands; S2 duplicate count in the preview when merging | MET | `ImportPreviewView.swift:174-229` (target card + `importDuplicateWarning`); `ImportConversion.swift:497-523` |
| 2b (RV.86) | Per-car mapping with own figures; Continue disabled until all decided; each car validated against ITS OWN destination | MET | `ImportCarsView.swift:125-322`; `ImportFlowModel+Cars.swift:45` `carsGateIsReady`; `ImportLanes.swift:37` `partitionByLanes` |
| 3 (RV.93) | Export not file; `allowsMultipleSelection`; one parse per file; one mapping; one merged timeline; one `commitImport` | MET | `ImportWizardView.swift:62`; `ImportFlowModel+Wizard.swift:606` `beginBatchParse`; `ImportBatchMerge.swift:71`; `ImportFlowModel+Wizard.swift:346` |
| 4a | Currency adjustable | PARTIAL | `ImportPreviewView.swift:38-40,303` (card only when `hasCurrencyQuestion`); a declared currency is shown, not adjustable – see finding 2 |
| 4b | Units adjustable | MISSING | No units question exists; `ImportAmbiguity` names `units` (`ImportModels.swift:254`) and nothing emits or reads it – RV.228 (open) |
| 4c | Target car adjustable | MET | `ImportPreviewView.swift:198-204` + `ImportTargetCarSheet` |
| 4d | Individual rows adjustable | MET | Review list (F6b, implemented); `ImportFlowModel+Wizard.swift:187,200` |
| 4e (RV.185) | New-car name editable; chosen currency becomes the new car's home currency | MET | `ImportPreviewView.swift:184-189`; `ImportFlowModel+Wizard.swift:54-80` `answerCurrency`/`applyHomeCurrencyToNewCars` |
| 5a | date-format asked here, never guessed; gates confirm; re-dates | MET | `ImportPreviewView.swift:249-297`; `ImportFlowModel+Wizard.swift:33` `canConfirm`; `:42` `answerDateFormat` |
| 5b | outOfScope surfaced ("read-but-not-imported") | MET | `ImportFlowModel+Wizard.swift:118-126`; `ImportPreviewView.swift:360` |
| 6 | Cancel leaves nothing behind (no entries; stored parse deleted) | MET (Cancel only) | `ImportFlowModel+Wizard.swift:296,306`; delete-on-every-exit is PJ.44 `[v1.1]` → N/A |
| 7 | Preview is not a receipt (same engine) | MET | `ImportTests.swift:271` `previewConsumptionEqualsPostCommitConsumption` |

---

## Sequence trace (one user, whole thing)

1. Import → source step loads `GET /v1/import/formats` (`ImportFlowModel.swift:217`).
2. Picker (multi-selection) → each staged file is one `POST /v1/import/parse` (`ImportWizardView.swift:62`, `ImportFlowModel+Wizard.swift:606`). Server returns candidates + ambiguities + vehicle groups; commits nothing.
3. Single car → preview; multi car → `.cars` mapping (`ImportFlowModel+Wizard.swift:557`, `:676`).
4. Preview shows consumption headline, figures, target card + duplicates, date-format question, currency question (no-column only), outOfScope + unsupported notices, review-row door.
5. Questions answered → `syncMergedParse` + `rebuildClassification` re-derive figures and review rows from the same candidates.
6. Confirm → new cars upserted, ONE `commitImport` transaction (`Repository+ArchiveImport.swift:198`) re-stamps conflicts per vehicle (`:283-310`), deletes stored parses, drains rates.
7. Cancel → `deleteStoredParses` + `resetFlow`.

**Where a fact stops being carried:** the server emits each vehicle's `units`
object (`MfmParser.cs:437`), and the client never reads it. The new car is
synthesised with hardcoded metric units (`ImportService.swift:155-156`), so the
preview's "Units & currency" row (`ImportFormatting.swift:76-80`) states the
*destination car's* units as if they were read from the file. Nothing detects a
miles/gallons file, and nothing offers to change units. The sequence carries
currency end-to-end (question → home currency → rows), but drops units at the
server response boundary.

---

## Proposed rows

| ID | Deliverable | Journey stage | User-facing consequence today | Severity | Check | Scenario |
|---|---|---|---|---|---|---|
| F6a-u | Amend F6a's "detected … units" (bullet 1) and "units … adjustable here" (bullet 4) to mark units **N/A for v1** – both shipped importers are metric – resolved in the same change as RV.228 (its option (b) scopes only to F6's text, so F6a's units sentence is currently the `PJ.23` shape: a promise with no owner). Also fix the preview hint "check the units below" (`ImportPreviewView.swift:99`), which points at a units row that is not adjustable | Bullets 1 and 4 | None today (MFM/Drivvo metric); the text overpromises | gap | Doc reconciliation: F6a text, RV.228, `ImportModels.swift:254` comment, and `API.md` all agree `units` is reserved/not-emitted; grep shows no `units` ambiguity emitted or read | F6a |

Not re-filed: RV.228 already carries the units ambiguity. This row is only the
F6a-text amendment RV.228's (b) does not currently reach.

---

## Could not settle

- **Is a file-declared currency a fact or a correctable default?** `ImportModels.swift:353-355`
  comments `declaredCurrency` as "a default the user can correct (hard rule 13),
  never a fact", but `answerCurrency` guards `hasCurrencyQuestion`
  (`ImportFlowModel+Wizard.swift:54`) and the currency card renders only in that
  case (`ImportPreviewView.swift:38-40`). A file that declares a currency (MFM
  does) is shown but cannot be changed. The comment overclaims the code – the
  doc-comment-naming-behaviour-with-no-call-site shape. Whether this is a defect
  or intended (a declared currency is a fact, not a guess) is a product call; it
  would be settled by a decision on whether F6a's "currency adjustable" applies
  to declared currencies or only to the F6 ambiguity.
