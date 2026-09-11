# REVIEW-SCENARIO: F6 · second walk (first full walk of F6)

- **Run:** REVIEW-SCENARIO-F6-2026-09-11b
- **Scenario:** `F6` (`docs/JOURNEYS.md:542`)
- **Prior run:** none - F6 has never been walked. Its v1 rows are closed (RV.191, RV.220 shipped in `7d4e1fc6`; PJ.10, PJ.20, PJ.33 done earlier). RV.227 is the one open row - a polish row on the source picker, cited here, not re-filed.
- **Verdict: NOT IMPLEMENTED**

## Ticked rows found to be untrue

None. RV.220, RV.191, PJ.10, PJ.20 and PJ.33 are true as walked. The gap is an **unowned promise**, not a ticked row that lies - the `PJ.23` shape.

## Promise-to-code map

F6 (`docs/JOURNEYS.md:542-549`) makes three promises. Each is walked against the tree.

| Journey promise | Status | Evidence |
|---|---|---|
| Partial parse is the goal: import what parses, show "214 of 220 – 6 rows need a look", the 6 rows listed for inline fix or skip; all-or-nothing is how switchers bounce | **MET** | Unparseable rows never fail the file - `ImportUnparsedRow` (`ImportModels.swift:243-251`), partitioned into review rows via `ImportReviewClassifier.partition(... unparsed: parse.unparsed ...)` (`ImportFlowModel+Wizard.swift:439-469`). Inline fix: odometer editor (`ImportReviewView.swift:388-402`), total editor (`:403-417`); skip: `leaveOut` (`:378-383`), `skipAll` (`:48-51`). Commit writes only kept records and drops the skipped: `importRecords` (`ImportFlowModel+Wizard.swift:223-240`), `isSkipped` (`:171-179`). Copy is the exact count pair: `rowsNeedALook` / `otherRowsReady` / `rowsReadyIntro` (`L10n.swift:457-481`). |
| RV.93: partial parse applies **across files** of one export - a failed file names itself and the rest of the export survives | **MET** | `beginBatchParse`/`performBatchParse` upload each file as its own `POST /import/parse` and append per-file failures without killing the batch (`ImportFlowModel+Wizard.swift:606-662`); `fileFailures` named per file (`ImportSourceView.swift:418-451`); "Continue with N files" bar (`ImportSourceView.swift:547-558`, `continueAfterBatchFailures` `:682-684`). |
| Nothing parses at all → name the reason plainly + offer to send us the file (explicit consent) + "here's where the CSV export lives" via `helpUrl` (PJ.33) | **MET** | Reasons named per failure: `parseErrorCard` switch (`ImportSourceView.swift:604-688`) - `doesNotMatchDeclared`, `unrecognisedFormat`, `inconsistentDates`, `oversize`, `server`, `unknown`, `couldNotRead`. Send-us-the-file with explicit consent: `notSupportedCard` (`ImportSourceView.swift:272-299`) → `ImportNotSupportedSheet` (`ImportWizardView.swift:352-475`) → `SendFileConsentSheet` (`ImportWizardView.swift:487-560`, consent copy `L10n.sendFileConsent`, "Share file" is the affirmative act). `helpUrl` guide: format row (`ImportSourceView.swift:211-217`), 422 card (`:626-629`), not-listed sheet (`ImportWizardView.swift:383-394`); wire value `ImportFormats.cs:38`. |
| Never import with guessed units/currency - the currency half | **MET** | `hasCurrencyQuestion` for a no-currency-column file (`ImportModels.swift:367-369`); `currencyCard` asked once, defaulting to the destination car's home currency (`ImportPreviewView.swift:303-356`); `answerCurrency` re-stamps every money-carrying candidate (`ImportFlowModel+Wizard.swift:54-65`); parser emits the empty-options `currency` ambiguity (`DrivvoParser.cs:141-148`), MFM's single-value `currency` ambiguity is a default the user corrects (`MfmParser.cs:248-252`). Owned by RV.113. |
| Never import with guessed units/currency - the **units** half ("MPG or L/100km?") | **MISSING** | The `units` ambiguity kind is named by the wire model (`ImportModels.swift:254`: "`kind` is `dateFormat` | `currency` | `units` | `outOfScope`") and by the API contract (`API.md:444`, `:502`), but **no parser emits it, no client reads it, and no UI asks it**. `grep 'kind == "units"'` over `ios/` and `backend/` returns nothing. `canCommit` blocks only on `dateFormat` (`ImportModels.swift:376-379`), so a `units` ambiguity that ever arrived would be silently ignored and committed under guessed units. Neither importer is ambiguous today - MFM is metric (`MfmParser.cs:437-443`) and Drivvo is metric - so the rule is satisfied vacuously, but the promise is written unconditionally and the machinery is absent. See the proposed row. |

## Sequence trace

One user, one Drivvo or MFM export, walked end to end:

1. Import → source picker renders the server's format list (`ImportSourceView.formatList`, `ImportFlowModel.loadFormats` `:217-242`).
2. Pick file(s) → stage under scope (`ImportWizardView.swift:76-119`) → `POST /import/parse` per file.
3. Nothing parses → `parseFailure` set, source step shows the reason card + the pinned send-us-the-file card (`ImportSourceView.swift:47-50`, `:76-84`). The reason and the next step are both on screen.
4. Partial parse → preview gate: figures + `dateFormat` question (asked once, confirm disabled until answered, `ImportPreviewView.swift:35-37`, `:249-297`) + `currency` question when the file has no currency column (`:38-40`, `:303-356`) + "N rows need a look" row (`:421-445`).
5. Review list: each row is parsed fields with only the broken field marked; inline fix or leave out; raw line behind "Original row" (`ImportReviewView.swift:159-190`, `:322-383`).
6. Confirm → the ONE write `confirmImport` (`ImportFlowModel+Wizard.swift:346-394`), kept records only, `provenance = .import`.

Where a fact stops being carried:

- **The user's keep/drop intent** carried correctly through step 5→6 (RV.220): keep is idempotent, leave-out is the only skip.
- **Station** carried to the review row and committed (RV.221).
- **Units ambiguity** - a fact that *cannot even arise*: no parser emits a `units` ambiguity, so there is nothing to carry, and no question to carry it through. This is the one place the promise has a gap rather than a path.

## Proposed rows

**RV.### - (F6 "never import with guessed units/currency" - the units half) Either build the once-per-file units question, or strike `units` from the contract.** The `units` ambiguity is documented in two places with no emitter and no reader: `ImportAmbiguity` names it (`ImportModels.swift:254`), `API.md` documents it (`:444`, `:502`), yet no parser produces it and `canCommit` (`ImportModels.swift:376-379`) blocks only `dateFormat`, so a `units` ambiguity would commit guessed units silently. F6 (`docs/JOURNEYS.md:547`) promises the "MPG or L/100km?" question; only the currency half is owned (RV.113).

- **Deliverable:** choose one and say which - (a) implement it end to end: a format whose units are ambiguous emits a `units` ambiguity, the preview asks once per file, and `canCommit` blocks until answered (it is a date-format-shaped question - no sane default, unlike currency which defaults to the car's home); or (b) mark the units half N/A-for-v1 in the journey text (both shipped importers are metric) and delete the `units` kind from the wire doc and `API.md` so no doc names behaviour with no call site. Option (b) does not change the journey promise silently - it re-states it.
- **User-facing consequence today:** none reachable - MFM and Drivvo are both metric, so no `units` ambiguity is emitted. It is the `PJ.23` shape (a promise written with no owner), and it becomes a guessed-units bug the day the first imperial importer (Fuelly/aCar, P5.4b) ships.
- **Severity:** gap.
- **Check:** L1 on `ImportModels`/`ImportTests` - a `units` ambiguity either blocks `canCommit` (option a) or is removed from the contract with the journey text re-stated (option b); a stub parse carrying `units` renders the question once and re-derives the candidates (option a). L4 `ImportUITests` only if option (a) is taken.
- **Scenario:** F6.

## Not settled

- **The failed file is not auto-attached to the send-us-the-file flow.** The reason card for `doesNotMatchDeclared`/`unknown` says "or send us the file" as text, but the only send-file door is the pinned `notSupportedCard` (`ImportSourceView.swift:272-299`), whose sheet asks the user to pick a file again (`ImportWizardView.swift:414-445`). The failed parse's bytes are not carried into that sheet. Read as a gap only if "send us the file" is meant to mean *this* file; read as fine if it means "a sample so the importer learns". Left open rather than filed - it is a product wording call, not a broken path.
- **The new car's units are hardcoded metric** (`ImportService.swift:155-156`: `km / l / lPer100`), and RV.185's brief asked to "check the units too" without a recorded answer. Same root as the units finding above - for MFM/Drivvo the hardcode is correct, and the user can change units in the Garage afterward (rule 13), so it is not a separate finding, but it is the second place a future imperial importer would guess.
