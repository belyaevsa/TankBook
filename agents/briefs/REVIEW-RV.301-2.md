# REVIEW-RV.301-2 - re-check the three items review 1 required

Read-only. Worktree `/Users/sbelyaev/repos/fuel-counter-ios-wt-rv301` (branch `wt/rv301`). Review 1's
verdict: `/tmp/agentlogs/REVIEW-RV.301.last.md` and `/tmp/rv301-review/REPORT.md`. The orchestrator
changed three things since; verify each with file:line, and do not re-review what review 1 passed:
1. `grandTotalRead` abstains when document labels disagree (`FuelExtractorTotalFinder.swift`), with
   the new test `disagreeingDocumentLabelsAbstain` in `RV301InvoiceTotalTests.swift`. The mutation
   (return a primary figure instead of nil) went red: `/tmp/agentlogs/rv301-mutation-abstain.log`.
   Check that nothing downstream (`FuelExtractor.swift:348` and the fallbacks after it) turns the
   abstention back into a figure on the three invoice fixtures or the conflict case.
2. `docs/EXTRACTION.md`'s RV.301 paragraph now matches the behaviour.
3. `TotalLabel.swift` carries no history or file-length commentary.
Run `cd ios && swift test --filter "RV301|RV277|Expense|TotalFinder|FuelExtractor|Corpus"` and
`swiftlint lint --quiet` from the worktree root; report counts and exit codes.
End with **COMPLETE** or **INCOMPLETE** and what must change.
