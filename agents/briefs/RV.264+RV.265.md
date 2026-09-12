# RV.264 + RV.265 - two small copy defects on the flag surfaces

**Scenarios: F6b · a flagged import row is fields (RV.264), F2 · the residue (RV.265).** Both
small, both about what a flagged row SAYS; one dispatch.

## RV.264 - the import review's composed count and the wrong-destination button

- `L10n.swift:472` interpolates the review count into one sentence with no plural form:
  *"2 rows are ready. These 1 are missing something"* / *"Эти 1 неполные"*. Hard rule 10's
  composed-string lesson (the P1.4 RU pass): one full localised phrase per plural category, in
  the String Catalog with `%lld` plural variants, for BOTH counts, EN and RU.
- The review screen's bottom-bar button says *Done · back to review* (`ImportReviewView.swift:56`)
  but `reviewReturn()` returns to the PREVIEW; RU already says *Готово · к просмотру*. EN becomes
  *Done · back to preview*; artboard `design/screens/ImportReview.dc.html:158` with it.

Tests: the localization gate asserts the key carries plural variants in both languages (L1);
`ImportUITests` EN + RU on a seeded one-row review read the singular phrase and the corrected
button label (L4). Mutation: drop the plural variants; the gate goes red.

## RV.265 - the account-wide "Needs a look" list does not name a consumption flag

`FlaggedEntriesView` renders a CHECK 5 consumption flag as the generic triangle + "car · date",
the same as a timeline conflict; the excluded list (`RV.218`) and the import review (`RV.229`)
already caption *Unusual consumption* with the litres / odometer next step. Render the same
caption and next step on the flagged list's row through the same `F9aFixRow` vocabulary - one
label table, not a third.

Tests: `FlaggedEntriesUITests` EN + RU (own invocation, count non-zero): a seeded
consumption-flagged entry renders its own caption with an identifier distinct from the timeline
row's. Mutation: drop the caption; red. Screenshots `RV.265-flagged-consumption` EN + RU, dark.

## Gates

`swift test` in full, lint 0, the two UI suites in their own invocations, screenshots opened by
the orchestrator. Report each mutation verbatim.
