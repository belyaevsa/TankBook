# REVIEW-SCENARIO run: F6 - 2026-09-12 (re-walk, after RV.227 / RV.228 / RV.263)

- **Scenario:** `F6` - Import file won't parse (J2's failure) (`docs/JOURNEYS.md:602`)
- **Run id:** REVIEW-SCENARIO-F6-2026-09-12
- **Prior walk:** `diagnostics/REVIEW-SCENARIO-F6-2026-09-11b.md` (NOT IMPLEMENTED - one MISSING: the `units` ambiguity documented twice with no emitter and no reader). That finding is now closed by RV.228.

**Verdict: IMPLEMENTED** - the one MISSING the prior walk gated on is closed (RV.228 reserves `units`, guard test in place), and the two "not settled" items resolve to N/A (units hardcode) and non-blocking polish (currency sentence drift). Every F6 promise is MET or reasoned N/A.

---

## Ticked rows found to be untrue

None. RV.228 (`0ff50af0`), RV.227 (`87c7346e`) and RV.263 (`6355cf83`) are true as walked. RV.228's guard `RV228ReservedUnitsTests` asserts the commit gate passes a stray `units` kind and that all six texts agree it is reserved. The prior walk's units MISSING is gone: no parser emits `units`, `canCommit` deliberately does not gate it (`ImportModels.swift:394-402`), and the reservation is carried by `ImportModels.swift:255-257`, `API.md:455/513-515`, `JOURNEYS.md:607`, `ERRORS.md` and `SCHEMA.md`.

Not a ticked row, but a stale sentence noted for polish: F6's currency half (`docs/JOURNEYS.md:607`) reads "the wizard asks it when the file cannot declare one" - accurate about the commit gate (`needsCurrencyAnswer`, `ImportModels.swift:380-382`) but no longer describing that a *declared* currency is also offered as a correctable default (RV.263). Non-blocking; see "Could not settle".

---

## Promise-to-code map

| F6 promise | Verdict | Evidence |
|---|---|---|
| Partial parse is the goal - import what parses, "N of M - K rows need a look", the K rows listed for inline fix or skip; all-or-nothing is how switchers bounce | MET | `ImportUnparsedRow` (`ImportModels.swift:243-251`) - unparseable rows never fail the file; `ImportReviewClassifier.partition(... unparsed: parse.unparsed ...)` (`ImportFlowModel+Wizard.swift:410-417`); inline fix = odometer editor (`ImportReviewView.swift:388-402`) + total editor (`ImportReviewView.swift:267`, `ImportTotalEditorCell`); skip = `leaveOut` (`ImportFlowModel+Wizard.swift:108-110`), `skipAll` (`ImportReviewView.swift:48-51`); commit writes only kept records (`importRecords`, `ImportFlowModel+Wizard.swift:164-181`). Copy is the count pair: `rowsNeedALook` / `otherRowsReady` / `rowsReadyIntro` (`L10n.swift:449-473`). |
| RV.93: partial parse applies across files of one export - a failed file names itself and the rest survives | MET | One `POST /import/parse` per file (`performBatchParse`, `ImportFlowModel+Wizard.swift:580-610`); per-file failures named (`fileFailures`, `ImportService.swift:83-93`); cards name each file + next step (`ImportSourceView.swift:426-459`); "Continue with N files" bar (`ImportSourceView.swift:555-562`), `continueAfterBatchFailures` (`ImportFlowModel+Wizard.swift:630-632`). |
| Nothing parses at all - name the reason plainly + offer to send the file (explicit consent) | MET | Reason named per failure: `parseErrorCard` switch over `ParseFailure` (`ImportSourceView.swift:612-696`) - `doesNotMatchDeclared` / `unrecognisedFormat` / `inconsistentDates` / `oversize` / `server` / `unknown` / `couldNotRead`. Send-us-the-file with explicit consent: pinned `notSupportedCard` (`ImportSourceView.swift:280-307`) -> `ImportNotSupportedSheet` (`ImportWizardView.swift:374-497`) -> `SendFileConsentSheet` (`ImportWizardView.swift:509-584`, consent copy `L10n.sendFileConsent`, "Share file" the affirmative act). |
| "Here's where the CSV export lives" via the format's `helpUrl` (PJ.33); covers each shipping source, never implies deferred importers | MET | Format row link (`ImportSourceView.swift:219-225`), 422 card link (`ImportSourceView.swift:634-637`), not-listed sheet link (`ImportWizardView.swift:391-416`); wire value for mfm and drivvo both `https://tankbook.live/import-guide/` (`ImportFormats.cs:38`, `:56`). |
| Never import with guessed currency - the currency half (asked once per file, live in v1) | MET | `hasCurrencyQuestion` = any `currency` ambiguity (`ImportModels.swift:370-372`); card renders for it (`ImportPreviewView.swift:38`); commit gated only for a no-column file via `needsCurrencyAnswer` (`ImportModels.swift:380-382`, `:394-402`); declared currency is a correctable default (RV.263), no-column asks with the car's home as the default (RV.113). |
| Never import with guessed units - the units half | N/A for v1 | Reserved, not emitted by any v1 parser; both shipped importers are metric. `ImportAmbiguity` comment (`ImportModels.swift:255-257`), `API.md:513-515`, guard `RV228ReservedUnitsTests` (commit passes a stray `units`). The "MPG or L/100km?" question ships with the first imperial importer (P5.4b). |
| Metric: recovery rate of failed imports after guidance >=50%; importer coverage grows from submitted samples | N/A | Post-launch success metric; nothing in code can keep it. The submission seam (send-file) is the mechanism that would grow coverage, and it exists (above). |

---

## Sequence trace (one user, one export that partially fails to parse)

1. Import -> source picker renders the server's format list (`ImportFlowModel.loadFormats`).
2. Pick file(s) -> staged under scope (`ImportWizardView.swift:66-126`) -> `POST /import/parse` per file.
3. A file fails -> `fileFailures` recorded, `finishBatch` stops at the source step (`ImportFlowModel+Wizard.swift:617-625`); each failure card names its file + next step; "Continue with N files" advances the survivors.
4. Nothing parses at all -> `parseFailure` set; source step shows the reason card (`parseErrorCard`) plus the pinned send-us-the-file card; reason and next step both on screen (`ImportSourceView.swift:47-50`, `:84-92`).
5. Partial parse -> preview gate (figures, date-format question asked once + confirm gated until answered, currency question, "N rows need a look").
6. Review list -> each row parsed fields, only the broken field marked, inline fix or leave out, raw line behind "Original row".
7. Confirm -> the ONE write `confirmImport` (`ImportFlowModel+Wizard.swift:287-342`), kept records only, `provenance = .import`.

Where a fact stops being carried:

- **Units ambiguity** - a fact that now *cannot arise*: no v1 parser emits it (`MfmParser` emits only `dateFormat`/`currency`/`outOfScope`, `MfmParser.cs:233-264`; `DrivvoParser` only `currency`, `DrivvoParser.cs:141-149`), and `canCommit` deliberately passes a stray one. Closed by RV.228; nothing to carry.
- **Declared currency** - carried end to end (RV.263): server emits the `currency` ambiguity with the declared code (`MfmParser.cs:248-252`), the preview renders it pre-filled and editable, and it becomes the new car's home currency. No step drops it.
- **The user's keep/drop intent and the station field** - carried (RV.220, RV.221, F6b implemented); unchanged by this diff.

---

## Proposed rows

None. The one MISSING the prior walk filed is RV.228 (closed). No new missing promise found; the two remaining items are product-wording / doc-reconciliation polish, not broken paths (below).

Deferred / already-owned (not re-filed):

- **RV.229** (open, F6b/F2) - the import review labels a consumption outlier "Breaks the timeline". It is an F6b row (the review list's rendering), not an F6 promise; it does not block F6.
- **PJ.44** (`[v1.1]`) - delete the stored parse on every wizard exit, not only Cancel. F6's "cancel leaves nothing behind" is an F6a promise (implemented); PJ.44 widens the delete to back/swipe paths.

---

## Could not settle

- **The failed file is not auto-attached to the send-us-the-file flow** (prior walk's item #1, still open). The reason cards for `doesNotMatchDeclared` / `unknown` / `unrecognisedFormat` say "send us the file" as text (`ImportSourceView.swift:478`, `:680`), but the only send-file door is the pinned `notSupportedCard`, whose sheet asks the user to pick a file again (`ImportWizardView.swift:451-467`); the failed parse's bytes are not carried into it. Read as a gap only if "send us the file" means *this* failed file; read as fine if it means "a sample so the importer learns". Still a product wording call, not a broken promise - the offer and the consent both exist.
- **F6's currency sentence (`docs/JOURNEYS.md:607`)** still says "the wizard asks it when the file cannot declare one". Accurate about the gate (`needsCurrencyAnswer`) but silent on RV.263's declared-currency offer. Settled by a one-sentence doc edit in the same change that next touches F6's text; no code or test change implied. (Also flagged by `REVIEW-SCENARIO-F6a-2026-09-12b`.)
- **The new car's units are hardcoded metric** (`ImportService.swift:155-156`: `km / l / lPer100`). Prior walk's item #2 - now N/A for v1 via RV.228: both importers are metric, and the user can change units in the Garage afterward (hard rule 13). Correct until the first imperial importer (P5.4b) ships.
