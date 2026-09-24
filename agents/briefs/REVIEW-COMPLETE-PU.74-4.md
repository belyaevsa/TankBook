# REVIEW-COMPLETE-PU.74-4 - re-check review 3's one open item

Read-only except `agents/reviews/PU.74-COMPLETENESS-4.md`. Review 3
(`agents/reviews/PU.74-COMPLETENESS-3.md`) found every item MET except fidelity (item 1) and the
Checks-cell sentence it drives (items 6-7): the cell-count audit runs once per window in
`PumpReadingLaw.resolve` while the note placed it in `candidates`, and no note amendment recorded it.
Since then: `agents/research/PU.74.md` gains adaptation **A10** (after A9) naming and justifying the
placement, and the PU.74 Checks cell in `docs/TASKS.md` now states the placement with A10. Verify,
with file:line: (1) A10 is a named, justified departure in the note's adaptation list; (2) its claim
that the refused set is identical to the in-`candidates` placement holds - read
`PumpReadingLaw.resolve`, `resolveWithoutPrice` and `candidates`, and say whether any path builds a
triple or pair from a window the audit would refuse; (3) the Checks cell, `docs/EXTRACTION.md`'s
PU.74 paragraph and the code agree. Do not re-review items review 3 marked MET.
End with **COMPLETE** or **INCOMPLETE** and what must change.
