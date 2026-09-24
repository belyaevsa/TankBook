# REVIEW-COMPLETE-PU.76 - is the spike report complete and honest?

Read-only except `agents/reviews/PU.76-COMPLETENESS.md`. Repo `/Users/sbelyaev/repos/fuel-counter-ios`.
The row (`docs/TASKS.md` PU.76, marked `[~]`) asked for "a spike first, report only". Read the note
`agents/research/PU.76.md` (option B, §5.6 gate, §5.7 falsifiers F1-F6), the report
`agents/research/PU.76-SPIKE.md`, and the uncommitted code (`git status`: `ml/pump-reader/src/pump_reader/
{segdata,segnet,segtrain,segeval,segexport,rotgate}.py`, `ml/pump-reader/tests/test_segnet.py`,
`ml/pump-reader/detector/dump.swift`, `ios/Tests/TankbookCoreTests/PumpRowSegmenterSpike.swift`,
`PumpReaderTestSupport.swift`, `PumpApportionmentTests.swift`, `PumpRowDetector.swift`).
Evidence logs: `ml/pump-reader/.out/seg-r1-eval.log`, `seg-r1-eval-quad.log`, `seg-r1.log`,
`/tmp/agentlogs/pu76-apportion-{shipped,seg}.log`, `/tmp/agentlogs/pu76-live-seg.log`.
Check, with file:line, each MET / PARTIAL / MISSING:
1. Fidelity: the code does what the report says PixelLink does (targets §4.1, loss eqs. 1-4 with
   OHEM r=3 and lambda 2, decode §3.3); every departure is one the note names (B1-B8) or the report
   names (B9). An unlisted departure is MISSING.
2. The gate numbers in the report match the logs exactly; the thresholds were chosen on val, never on
   heldout (`segeval.py`); the shipped baseline is in the same metric.
3. Every falsifier F1-F6 is either reported with its number or named as not measured.
4. The production-code change is only the internal seam and nothing in the app calls it.
5. The report's verdict follows from the row's own rule, and the owner's choices are stated, not decided.
6. `cd ml/pump-reader && .venv/bin/python -m pytest -q` - count, exit code.
End with **COMPLETE** or **INCOMPLETE** and what must change.
