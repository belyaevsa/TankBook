# REVIEW-SCENARIO run: F6a - 2026-09-12b (third walk, after RV.263)

- **Scenario:** F6a (`docs/JOURNEYS.md:611`)
- **Run id:** REVIEW-SCENARIO-F6a-2026-09-12b
- **Prior walk:** `diagnostics/REVIEW-SCENARIO-F6a-2026-09-12.md` (NOT IMPLEMENTED, one row F6a-c)
- **Scope:** re-check ONLY the one row the second walk gated on (F6a-c), now shipped as RV.263 (`6355cf83`).

**Verdict: IMPLEMENTED** - RV.263 lands option (a) of F6a-c whole and tested: the currency card
renders for ANY `currency` ambiguity, pre-filled with the declared code; only a no-column file still
gates the commit. F6a bullet 4 ("everything shown is adjustable here - currency") is now MET, and
the sequence carries the fact end to end.

---

## Ticked rows found untrue

None in code. RV.263's `[x]` is true: `hasCurrencyQuestion` gates the card, `needsCurrencyAnswer`
gates the commit, `effectiveCurrency = answer ?? declared ?? car's home` (all cited below).

One stale-doc claim, not a code lie: RV.263's TASKS note says *"P5.5b's `[~]` note on 'currency not
an editable picker' closes with it"*, but `docs/TASKS.md:679` was not edited and still reads *"the
units/currency row not yet an editable picker - F6a's 'everything shown is adjustable here' is
half-met"*. The note is now false on the currency half; it is a backlog umbrella (`P5.5b`), not an
F6a promise, so it does not block - see "Could not settle".

---

## Promise-to-code map (only the currency path; everything else the second walk mapped is untouched by RV.263)

| # | F6a promise (second walk's gated item) | Verdict | Evidence |
|---|---|---|---|
| 4a | Currency adjustable in the preview for ANY `currency` ambiguity | **MET** (was PARTIAL) | `ImportModels.swift:370-372` `hasCurrencyQuestion` = any `currency` ambiguity (empty or non-empty); `ImportPreviewView.swift:38` renders `if model.hasCurrencyQuestion` |
| 4a-pre | Declared currency pre-filled, not a forced tap | **MET** | `ImportModels.swift:359-364` `declaredCurrency` = first option; `ImportFlowModel+Currency.swift:65-67` `effectiveCurrency = answer ?? declared ?? default`; `ImportPreviewView.swift:334` picker label = `effectiveCurrency ?? defaultCurrency` |
| 4a-gate | Commit gated only for a no-column file | **MET** | `ImportModels.swift:380-382` `needsCurrencyAnswer` = currency ambiguity with EMPTY options; `ImportModels.swift:394-402` `canCommit` blocks only on `needsCurrencyAnswer, currencyAnswer == nil` |
| 4a-answer | Answering re-runs candidates/summary/commit | **MET** | `ImportFlowModel+Currency.swift:15-26` `answerCurrency` -> `rebuildClassification`; `ImportFlowModel+Currency.swift:52-58` `effectiveCandidates`; `ImportFlowModel+Wizard.swift:391` rebuild reads `effectiveCandidates`; `ImportFlowModel+Wizard.swift:200` summary reads `effectiveCurrency` |
| 4a-home | Declared currency becomes the new car's home currency | **MET** | `ImportFlowModel.swift:343-345` `newCarHomeCurrency = effectiveCurrency ?? defaultCurrency`; `ImportFlowModel+Currency.swift:31-41` `applyHomeCurrencyToNewCars` re-homes in place on answer |
| 4a-server | Server still emits the ambiguity with the declared code | **MET** | `MfmParser.cs:252` `new ImportAmbiguity("currency", [currency], rowsWithCurrency)`; `docs/API.md:506-508` "a default the user corrects, never a fact" |
| 4a-L1 | Declared currency is a correctable default, tested | **MET** | `ImportCurrencyTests.swift:39` `aFileThatDeclaresACurrencyStillHasACurrencyQuestion`; `:53` `answeringADeclaredCurrencyReHomesTheCandidates`; `:75` `aDeclaredCurrencyCommitsWithoutATapAndANoColumnFileDoesNot` |
| 4a-L4 | MFM fixture shows the declared currency as an editable picker, EN + RU | **MET** | `ImportCurrencyUITests.swift:83` `testDeclaredCurrencyRendersAsAnEditablePicker`; `:112` `...InRussian` |

The prior walk's bullet 1b ("detected currency shown") stays MET; 1c/4b (units) stay N/A (reserved,
RV.228); 4c/4d/4e/5a/5b/6/7 are unchanged by RV.263 and remain as the second walk mapped them.

---

## Sequence trace (one user, one MFM import that declares USD)

1. Source step -> `GET /v1/import/formats`.
2. Pick -> `POST /v1/import/parse`; server returns candidates + a `currency` ambiguity with
   `options = ["USD"]` (`MfmParser.cs:252`), commits nothing.
3. Single car -> preview.
4. `hasCurrencyQuestion` is now TRUE for the non-empty options (`ImportModels.swift:370-372`), so
   the currency card renders (`ImportPreviewView.swift:38`) pre-filled with USD via
   `effectiveCurrency = declaredCurrency` (`ImportFlowModel+Currency.swift:65-67`,
   `ImportPreviewView.swift:334`). `needsCurrencyAnswer` is false, so confirm is NOT gated
   (`ImportModels.swift:398`).
5. User changes to RUB (or leaves USD): `answerCurrency` -> `applyHomeCurrencyToNewCars` +
   `rebuildClassification` (`ImportFlowModel+Currency.swift:15-26`), so the figures, the review rows
   and the commit all read the answered currency.
6. Confirm -> new car upserted with `newCarHomeCurrency = effectiveCurrency`
   (`ImportFlowModel.swift:343-345`); ONE `commitImport`.
7. Cancel -> parses deleted, flow reset.

**Where the fact used to stop being carried (second walk, step 4) is now carried:** the server's
"correctable default" survives the response boundary into a pre-filled, editable picker, and into
the new car's home currency. No step drops the currency any more.

---

## Proposed rows

None. F6a-c (the one gated row) is closed; the code, the server, `API.md`, `MfmParser` and F6a's own
text now agree.

---

## Could not settle

Non-blocking doc drift, all polish, none an F6a promise:

- **F6's bullet (`docs/JOURNEYS.md:607`)** still reads *"the wizard asks it when the file cannot
  declare one"*. It is accurate about the gate (`needsCurrencyAnswer`) but no longer describes the
  declared-currency offer the code now makes. A sentence in a sibling journey; reconcile when F6 is
  next touched (RV.227 is open under F6, the source picker - it does not touch this sentence).
- **`P5.5b` `[~]` (`docs/TASKS.md:679`)** still says *"the units/currency row not yet an editable
  picker - ... half-met"*, contradicting RV.263's own note that it closes. Backlog umbrella; the
  currency half is closed, the units half is RV.228 (N/A for v1). Edit the note when P5.5b is next
  groomed.
- **`ERRORS.md:531`** ("Ambiguous currency ... Which currency are these amounts in?") describes only
  the no-column ask; the declared case's subtitle ("The file says USD...") is not reflected. This is
  F6's error surface, deferred per the brief.

Settled by: a doc-only pass over the three sites above; no code or test change is implied.
