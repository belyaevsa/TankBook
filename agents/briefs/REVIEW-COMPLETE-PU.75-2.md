# REVIEW-COMPLETE-PU.75-2 - re-check review 1's two items

Read-only except `agents/reviews/PU.75-COMPLETENESS-2.md`. Repo `/Users/sbelyaev/repos/fuel-counter-ios`.
Review 1 (`agents/reviews/PU.75-COMPLETENESS.md`) found every item MET except two, now changed -
verify each with file:line and do not re-review what review 1 passed:
1. `docs/EXTRACTION.md` gains "Decision 10, amended 2026-09-24 (PU.75)" after the PU.63 amendment,
   recording that the fast path no longer counts text lines and that `textLines` is `-1` there. Check
   it against `PumpDisplayCapture.decideAt` and the note's A1.
2. `tools/pump-annotate/index.html` (the compare view, ~line 2150) no longer renders `-1 <= 30` as a
   passing check on a fast-decided frame. Also grep the rest of `tools/` and `ios/Sources/PumpReadTool`
   for any other consumer of `textLines` that would mis-render or mis-compute `-1`.
End with **COMPLETE** or **INCOMPLETE** and what must change.
