# REVIEW-COMPLETE-PU.77 - is the row-reader spike report complete and honest?

Read-only except `agents/reviews/PU.77-COMPLETENESS.md`. The spike lives in the worktree
`/Users/sbelyaev/repos/fuel-counter-ios-wt-pu77` (untracked files there: `git -C <worktree> status`).
Read the row (`docs/TASKS.md` PU.77), the note `agents/research/PU.77.md` (§4 recipe, §5 adaptations
A1-A12, §6.2 bars B1-B3, §6.4 falsifiers F1-F6) and the report `<worktree>/agents/research/PU.77-SPIKE.md`.
Code: `<worktree>/ml/pump-reader/src/pump_reader/{rowreader,rowtrain,roweval}.py`,
`<worktree>/ml/pump-reader/tests/test_rowreader.py`,
`<worktree>/ios/Tests/TankbookCoreTests/PumpRowReaderSpikeTests.swift`.
Evidence: `<worktree>/ml/pump-reader/.out/pu77-s{0,1,2}/{metrics.json,heldout-b1.json}`,
`<worktree>/ml/pump-reader/.out/pu77-s{0,1,2}.log`, `/tmp/agentlogs/pu77-s{0,1,2}-law-{raw,scaled}.log`,
`/tmp/agentlogs/pu77-mutation-skip.log`, the heldout index
`<worktree>/ios/.build/pump-reader-out/rowreader/heldout/index.json`.
Check with file:line, each MET / PARTIAL / MISSING:
1. Fidelity: the code does what the note's §4 recipe says; every departure is one the note lists or
   the report names. An unlisted departure is MISSING.
2. Every number in the report matches the evidence files exactly (B1 table, B2 table, the WRONG list).
3. Selection never touched heldout (F3): thresholds, checkpoint choice and T are train-side only.
4. The B1 comparison is fair: both arms on the same strips; the current arm's string is the
   shipped reader's own read of that window.
5. The pump-041 diagnosis (a partial glare total; the law's repair tier overriding a confident read)
   is right - check the annotation, the posteriors in `pu77-s0/posteriors-raw.json`, and
   `PumpReadingLaw`'s repair tier.
6. The verdict follows the row's own rule (B3) and the owner's choices are stated, not decided.
7. `cd <worktree>/ml/pump-reader && PYTHONPATH=$PWD/src /Users/sbelyaev/repos/fuel-counter-ios/ml/pump-reader/.venv/bin/python -m pytest -q` - count and exit code.
End with **COMPLETE** or **INCOMPLETE** and what must change.
