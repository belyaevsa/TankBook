# RV.263 - a currency the file declares cannot be corrected in the preview

**Scenarios: F6a · the import preview ("everything shown is adjustable here: currency"), F6 ·
never import with a guessed currency.** The one gap holding F6a's review. Hard rules 13 and 3.

The server treats the declared currency as a default: `MfmParser.cs:250-252` emits a `currency`
ambiguity whose one option IS the declared code, and `API.md`, `ImportConversion.swift:491`,
`ImportModels.swift:356` all say "a default the user can correct, never a fact". The app disagrees:
`ImportParse.hasCurrencyQuestion` (`ImportModels.swift:370-372`) is true only when the ambiguity's
`options.isEmpty` - the no-column case - so a declared currency imports as a fact with no fix.

## Build - option (a), the rule-13 close

Render the currency card whenever the parse carries a `currency` ambiguity, empty or non-empty
options, **pre-filled with the declared currency** (non-empty) or the destination car's home
currency (empty, as today). Answering re-runs `effectiveCandidates` / `summary` / commit exactly as
today (`ImportFlowModel+Wizard.swift:50-110`). Keep `canCommit`'s meaning: a declared currency is
already answered (the pre-fill), so the file commits without a tap; a no-column file still needs
the pick. Say in one sentence how `hasCurrencyQuestion` and "needs an answer" now differ.

`P5.5b`'s `[~]` note ("units/currency not an editable picker") closes with this on the currency
half - update it in `docs/TASKS-DONE.md` if that is where it lives; the units half is `RV.228`.
`docs/JOURNEYS.md` F6a bullet 4 and F6 bullet 3 already promise this; leave them.

## Tests

- **L1, FAILS TODAY**: a `currency` ambiguity with a non-empty option set renders the card
  (`hasCurrencyQuestion` or its successor is true) pre-filled with the declared currency, and a
  different answer re-homes the candidates.
- **L1**: a declared currency needs no tap to commit; a no-column file still does.
- **L4 `ImportUITests` EN + RU**: the MFM fixture (which declares a currency) shows the declared
  currency as an editable picker and a different pick changes the summary's currency. Screenshots
  `RV.263-import-preview-declared-currency` EN + RU, dark.

## Mutation - named

Gate the card on `options.isEmpty` again; the non-empty L1 goes red. Verbatim.

## Vacuous trap

A fixture with no currency column, where the card already showed.
