# REVIEW-COMPLETE-PU.77-2 - re-check review 1's items

Read-only except `agents/reviews/PU.77-COMPLETENESS-2.md`. Review 1: `agents/reviews/PU.77-COMPLETENESS.md`
(INCOMPLETE). The report: `/Users/sbelyaev/repos/fuel-counter-ios-wt-pu77/agents/research/PU.77-SPIKE.md`.
Verify each with file:line and do not re-review what review 1 passed:
1. The un-re-derived law windows (§4.4 step 3) are now named as a departure needing the owner's OK,
   and the B2 numbers are labelled as the shipped windows' numbers.
2. The seed-2 photo counts (raw 55/68, scaled 54/68) and the "without pump-041" sentence match
   `/tmp/agentlogs/pu77-s2-law-{raw,scaled}.log`.
3. heldout2 was scored once per seed: `<worktree>/ml/pump-reader/.out/pu77-s{0,1,2}/heldout2-b1.json`,
   `/tmp/agentlogs/pu77-s{0,1,2}-heldout2-law.log`; the report's heldout2 table matches them; the
   scored-candidate configuration list is present.
4. The verdict is an unambiguous measured no-go for this run (B3), with the law row proposed
   separately as the owner's decision.
End with **COMPLETE** or **INCOMPLETE**.
