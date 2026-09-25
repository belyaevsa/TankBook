# REVIEW-COMPLETE-PU.82 - is the hand-box classifier report complete and honest?

Read-only except `agents/reviews/PU.82-COMPLETENESS.md`. Repo `/Users/sbelyaev/repos/fuel-counter-ios`.
Row: `docs/TASKS.md` PU.82 (its Checks cell). Report: `agents/research/PU.82-REPORT.md`. Code:
`git diff -- ml/pump-reader/src/pump_reader/realglyphs.py`, `ml/pump-reader/tests/test_hand_only.py`.
Evidence: `ml/pump-reader/.out/real-r12-{full,hand}/manifest.json`,
`ml/pump-reader/.out/pu82-{full,hand,flatten}-s{0,1,2}/{metrics.json,temperature.json}`,
`ml/pump-reader/.out/pu82-*-score.log`, `ml/pump-reader/.out/pu82-*-seg.log`,
`/tmp/agentlogs/pu82-mutation-hand-only.log`, the chain scripts in `ml/pump-reader/.out/pu82-runs.log`.
Check with file:line, each MET / PARTIAL / MISSING:
1. Every Checks-cell sentence of the row (hand-only option, step-0 re-export, pool size and dp rate,
   one control per pool plus flatten, 3 seeds, both tiers, T per candidate, the pool effect isolated).
2. Every number in the report matches the evidence exactly (tables, means, effects, WRONG lists).
3. `--hand-only` selects the right frames: verified frame windows only, stills unchanged, video
   frames included when verified - check `db_windows` against the `frames` / `labels` tables.
4. The two pools differ only by `--hand-only` (same export, same flags).
5. The verdict follows from the numbers; the claim about PU.41 is supported.
6. `cd ml/pump-reader && .venv/bin/python -m pytest -q` - count and exit code.
End with **COMPLETE** or **INCOMPLETE** and what must change.
