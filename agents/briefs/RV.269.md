# RV.269 - the review intro's arithmetic

**Scenario: F6b · a flagged import row is fields (the review header).** Polish, small.

`ImportSummary.readyCount` counts every fill the commit will write - ready rows AND kept review
rows - so the intro on a three-row file with three review rows reads *"3 rows are ready. These 3
are missing something"*. The plural forms are right since `RV.264`; the numbers contradict.

## Build

One way, say which: count *ready* as the rows NOT in review (`ImportFlowModel.importFills` minus
the review set - `ImportFlowModel+Wizard.swift:152,187-199` - the number the first sentence
means), or reword so one number is the total and the other the review count. Prefer the first:
the sentence's meaning is "these are fine, those need you". Keep RV.264's two plural keys.

## Tests

- **L1, FAILS TODAY**: a three-row file with one review row renders *2 rows are ready. This 1 is
  missing something* (EN) and the RU equivalent through the same keys.
- `ImportUITests` in its own invocation (the RV.264 tests assert the singular phrase - keep them
  green), count reported. Re-shoot `P5.5b-import-review` EN + RU (the header changes).

## Mutation - named

Count all rows again; the L1 goes red. Verbatim.
