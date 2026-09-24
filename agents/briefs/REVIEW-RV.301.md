# REVIEW-RV.301 - is the invoice-total change complete and does it move nothing else

Read-only review. Work in `/Users/sbelyaev/repos/fuel-counter-ios-wt-rv301` (worktree, branch
`wt/rv301`); the change is `git diff HEAD` there plus the untracked `TotalLabel.swift` and
`RV301InvoiceTotalTests.swift`. The brief the builder worked from: `agents/briefs/RV.301.md` there.
Do not edit any tracked file; write only your report and scratch under `/tmp`.

## What to check (cite file:line for each verdict)
1. **The three fixtures** (brief's list) resolve `expected.csv`'s totals, and the VAG page reads
   159 373.00 from `Сумма документа`, not by picking the largest number.
2. **The reorder in `pairedValue`** (label-line value now read BEFORE the adjacent rows) is the risky
   part: find every label shape in the corpus that carries a number that is NOT its total (`СУММА НДС
   20%`, `ИТОГО 2 позиции`, a label with a count, a percent, a time, a card tail) and say whether the
   new order reads it. Run the receipt and expense ratchets on HEAD and on the change:
   `cd ios && swift test --filter "Corpus|RV277|RV56|Expense|TotalFinder|FuelExtractor|RV301"` and
   compare every per-fixture total, not just the pass count. A fuel total that moves is a defect.
3. **The mutations**: remove the `.document` ranking in `grandTotalRead` - the RV301 test must go red;
   undo the label-line-first reorder - say which fixture goes red. Paste the red output, restore.
4. **Docs**: the `docs/EXTRACTION.md` paragraph matches the code; comments follow `CLAUDE.md` ->
   "Code comments: current truth only" (no task ids, no history).
5. `swiftlint lint --quiet` from the worktree root: 0 errors.

## Verdict
End with **COMPLETE** or **INCOMPLETE** and a numbered list of what must change before merge.
