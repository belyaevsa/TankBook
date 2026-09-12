# REVIEW-SCENARIO run: F6a - 2026-09-12 (second walk, after RV.228)

- **Scenario:** F6a (`docs/JOURNEYS.md:610`)
- **Run id:** REVIEW-SCENARIO-F6a-2026-09-12
- **Prior walk:** `diagnostics/REVIEW-SCENARIO-F6a-2026-09-11c.md` (NOT IMPLEMENTED, one row F6a-u)

**Verdict: NOT IMPLEMENTED** - RV.228 landed the units half clean, but the currency half of
"everything shown is adjustable here" is still unmet, and this walk settles the first walk's
"could not settle": the server treats a *declared* currency as a correctable default (tested),
and the client renders it as a fixed fact. The units finding is closed; the currency finding
was left open last time and is now proven.

---

## Ticked rows found untrue

None. RV.228 (`0ff50af0`) is true in the code: F6a bullets 1 and 4 carry the `units is N/A for
v1` marker (`docs/JOURNEYS.md:619`, `:643`), the preview hint names the date format or currency
(`ImportPreviewView.swift:99`), and the guard `RV228ReservedUnitsTests` binds all six texts.

Not a ticked row, but a stale note: **P5.5b `[~]`** still says *"the units/currency row not yet
an editable picker"* (`docs/TASKS.md:678`). The units half of that note is now closed (reserved,
N/A for v1); the currency half is the gap below.

---

## Promise-to-code map

| # | F6a promise | Verdict | Evidence |
|---|---|---|---|
| 0 | Server returns candidates; garage untouched until confirm | MET | `ImportFlowModel+Wizard.swift:346` `confirmImport`; `ImportTests.swift:249` `nothingIsWrittenBeforeConfirm` |
| 1a | Fill-up count / date range / odometer span / total spend | MET | `ImportPreviewView.swift:116-129`; `ImportConversion.swift:493` `ImportSummary.compute` |
| 1b | Detected currency shown | MET (shown) | `ImportPreviewView.swift:166-170` `unitsCurrencyText` -> `summary.currency`; `ImportConversion.swift:520` |
| 1c | Detected units | N/A | reserved, no v1 parser emits it (RV.228); F6a text `:619` |
| 1d | Derived consumption as the headline | MET | `ImportPreviewView.swift:85-112`; `ImportConsumption.compute` -> `ConsumptionEngine.recompute`+`lifetime` |
| 2 | Say where it lands; S2 duplicate count in the preview | MET | `ImportPreviewView.swift:174-229`; `ImportConversion.swift:524` |
| 2b | Per-car mapping (RV.86); own figures; Continue gated; per-destination validation | MET | `ImportCarsView.swift:125-322`; `ImportFlowModel+Cars.swift:45`; `ImportLanes.swift:37` |
| 3 | Export not file (RV.93); one parse per file; one mapping; one `commitImport` | MET | `ImportWizardView.swift:68` (`allowsMultipleSelection: true`); `ImportFlowModel+Wizard.swift:613` `beginBatchParse`; `ImportBatchMerge.swift:71` |
| 4a | Currency adjustable here | **PARTIAL** | adjustable only when `hasCurrencyQuestion` (`ImportPreviewView.swift:38`); a declared currency is shown, never correctable - see finding |
| 4b | Units adjustable | N/A | reserved (RV.228) |
| 4c | Target car adjustable | MET | `ImportPreviewView.swift:198-204` + `ImportTargetCarSheet` |
| 4d | Individual rows adjustable | MET | review-row door `ImportPreviewView.swift:50-52,421-445`; F6b (implemented) |
| 4e | New-car name editable; chosen currency becomes new car's home currency | MET | `ImportPreviewView.swift:183-189`; `ImportFlowModel+Wizard.swift:54-80` |
| 5a | date-format asked here, never guessed; gates confirm; re-dates | MET | `ImportPreviewView.swift:249-297`; `ImportFlowModel+Wizard.swift:42`; `ImportModels.swift:381` `canCommit` |
| 5b | outOfScope surfaced | MET | `ImportFlowModel+Wizard.swift:118-126`; `ImportPreviewView.swift:360` |
| 6 | Cancel leaves nothing behind | MET (Cancel); delete-on-every-exit N/A | `ImportFlowModel+Wizard.swift:296-297,306,312`; PJ.44 `[v1.1]` |
| 7 | Preview is not a receipt (same engine) | MET | `ImportTests.swift:271` `previewConsumptionEqualsPostCommitConsumption` |

---

## The finding that matters (settles the first walk's "could not settle")

The first walk left "is a declared currency a fact or a correctable default?" as a product call.
It is not: **the server has already decided, in tested code, that it is correctable - and the
client drops that fact at the response boundary.**

- Server: `MfmParser.cs:250-252` emits a `currency` ambiguity with the single declared currency
  and the comment *"a default the user must be able to correct, never a fact (hard rule 13, F6)"*.
- Server test: `MfmParserTests.cs:282-295` asserts *"currency is a reported default, never a
  fact"* with `options` = the single declared currency.
- Contract: `docs/API.md:506-508` - a file-declared currency is *"a default the user corrects
  (hard rule 13), never a fact"*.
- Client comments agree: `ImportModels.swift:356-358` (*"a default the user can correct"*) and
  `ImportConversion.swift:491-492` (*"a default the user can correct, hard rule 13"*).
- Journey: F6a bullet 4 - *"Everything shown is adjustable here - currency, ..."*
  (`docs/JOURNEYS.md:643`).

Six sites promise correction; no code delivers it:

- `ImportModels.swift:370-372` - `hasCurrencyQuestion` is true only for a `currency` ambiguity
  with **empty** options (the no-column case). A declared currency (options non-empty) is false.
- `ImportPreviewView.swift:38` - the currency card renders only `if model.hasCurrencyQuestion`.
- `ImportFlowModel+Wizard.swift:55` - `answerCurrency` guards `hasCurrencyQuestion`.

So an MFM file - which declares a currency on every row - shows it in the "Units & currency"
figure and never offers to change it. The correction opportunity the server deliberately emits
(the `currency` ambiguity with the declared value) is discarded.

**A second defect introduced by RV.228:** F6's bullet now says *"the wizard asks it when the
file cannot declare one"* (`docs/JOURNEYS.md:606`). That contradicts `API.md:506-508` and
`MfmParser.cs:250-252`, which still promise a declared currency is correctable. The docs now
disagree with each other on the exact question the first walk could not settle.

---

## Sequence trace (one user, one MFM import)

1. Source step -> `GET /v1/import/formats`.
2. Pick -> one `POST /v1/import/parse` per file. Server returns candidates + ambiguities
   (dateFormat + a `currency` ambiguity whose options = the file's declared currency) +
   vehicle groups; commits nothing.
3. Single car -> preview (`ImportFlowModel+Wizard.swift:557`).
4. Preview shows the consumption headline, figures, target card, date-format question, and a
   "Units & currency" row reading the declared currency. **No currency card renders, because
   `hasCurrencyQuestion` is false for non-empty options** (`ImportPreviewView.swift:38`).
5. Date question answered -> figures rebuild.
6. Confirm -> new cars upserted with the declared currency as home currency; ONE `commitImport`.
7. Cancel -> parse deleted, flow reset.

**Where the fact stops being carried:** at step 4. The server marked the currency *"correctable"*
(step 2), and the client silently promotes it to an immutable fact. This is the
`RV.185`/`RV.189` sequence shape: every layer is individually right, and the meaning is lost
between the parse response and the preview.

User-facing consequence today: an MFM importer cannot correct a currency the file declares even
though the app has decided (in six places) they must be able to - a wrong currency imports with
no later fix (money is a pair, snapshots immutable, hard rule 3).

---

## Proposed rows

| ID | Deliverable | Journey stage | Consequence today | Severity | Check | Scenario |
|---|---|---|---|---|---|---|
| F6a-c | **Settle the declared-currency question and make code + all texts agree.** Two options, the server already picked the first: (a) render the currency card whenever the file carries a `currency` ambiguity (empty **or non-empty** options), pre-filled with the declared currency, so a declared currency is a correctable default exactly as `MfmParser.cs:250-252` and `API.md:506-508` promise; or (b) decide a declared currency is a fact and rewrite `API.md`, `MfmParser` comment + test, `ImportConversion.swift:491`, `ImportModels.swift:356`, F6a bullet 4, and RV.228's F6 line to all say so. (a) is the hard-rule-13 close and is cheap - the card already exists for the no-column case | Bullet 4 "everything shown is adjustable here - currency"; F6 bullet 3 | An MFM importer cannot correct a currency the file declares; a wrong currency imports with no fix (hard rule 3) | gap (hard-rule-13-shaped) | L1: a `currency` ambiguity with non-empty options renders the currency card pre-filled with the declared currency, and answering re-runs `effectiveCandidates`/`summary`/commit (under (a)); or a guard asserting API.md, the parser comment, and the F6/F6a texts all agree (under (b)). L4 `ImportUITests` under (a): MFM fixture shows the declared currency as an editable picker | F6a |

Not re-filed: the units half is RV.228 (closed); P5.5b `[~]` is the umbrella this row sharpens
(its "units/currency not an editable picker" note is now stale on the units half and imprecise on
the currency half). RV.227 names the source picker (F6), not F6a.

---

## Could not settle

- Whether to close F6a-c via (a) build or (b) reconcile is a product-owner call on hard rule 13
  as applied to a file-declared value. The server's own comment and test already assert "correctable,
  never a fact", which is the evidence this report leans on; a product decision the other way
  (declared = fact) is legitimate but must then edit every one of the six sites, including the
  server test that currently asserts the opposite.
