# RV.305 completeness review, SECOND PASS - is this expense-total row actually done?

- **Row:** RV.305 - a column-laid invoice commits a line amount as its total (`docs/TASKS.md:963`,
  ticked in the tree pending this review; index row `docs/TASKS.md:105` ticked too).
- **Reviewed:** 2026-09-24, reviewing agent under `agents/briefs/REVIEW-COMPLETE-RV.305-2.md`.
  Second pass over `agents/reviews/RV.305-COMPLETENESS.md` (review 1), which was INCOMPLETE on one
  defect only: RV.305's Built text handed the residual (reading the VAG invoice's 159 373,00) to
  "RV.301's open total half", while RV.301's row said the opposite - a circular hand-off leaving
  the residual unowned.
- **Diff under review:** the guard on `grandTotalRead`'s last fallback
  (`ios/Sources/TankbookCore/Extraction/FuelExtractorTotalFinder.swift:192-198`, one hunk, the only
  change to the file) and the RV.305 + RV.301 rows in `docs/TASKS.md`. PU.78's concurrent edits
  (`PumpReadingLaw.swift`, pump tests, `PumpPhotoGate.swift`, `docs/EXTRACTION.md`, corpus fixtures,
  the PU.78/PU.81/PJ.500 row texts) were present in the tree and IGNORED as instructed; nothing
  below judges them.

## The fix review 1 demanded - verified, all three parts

Review 1's verdict listed exactly what closes it (`RV.305-COMPLETENESS.md:192-200`). All of it is
in the working tree, in the same uncommitted diff as the RV.305 row, so it commits together:

1. **The hand-off sentence** - `docs/TASKS.md:961` (RV.301's row) now reads: "the VAG page's
   column-laid total **joins this half from RV.305** (closed 2026-09-24 with an honest-miss guard):
   reading its 159 373,00 needs the label-ranking decision (`Сумма документа` over a column-laid
   `Итого`)". Verbatim review 1's draft; the old contradicting clause ("is RV.305") is gone (git
   diff of the row, old vs new).
2. **The Checks extension** - same row: "Checks added: the VAG page resolves 159 373.00 through the
   recorded label-ranking decision (or its truth is corrected, with evidence); **the tied-labels
   abstention RV.305 pinned stays**". The second clause is the regression guard: a future RV.301
   fix cannot silently undo this row's guard. The number matches the truth on disk:
   `Spike/ReceiptSpike/fixtures/expenses/expected.csv:20` = `parts-vag-...,parts,159373.00`.
3. **The sibling seam (review 1's optional item 2)** - same row: "Sibling seam for the same fix:
   `grandTotalRead`'s net-versus-gross override (`FuelExtractorTotalFinder.swift`, the
   redundancy-over-label branch)". The branch exists at `FuelExtractorTotalFinder.swift:176-180`
   and still carries the weaker invariant review 1 described (repeated value above the MODAL
   labelled figure, not above every labelled figure) - correctly filed into RV.301 rather than
   fixed here, seam named, per the sibling fence.

**The circularity is gone.** RV.305's Built text (`docs/TASKS.md:963`) still points at "RV.301's
open total half", and `:961` now accepts it with a named decision, checks and the seam - an agent
closing RV.301 against its Checks as written can no longer drop the 159 373 silently. Nothing else
in RV.301's row changed (git diff: description, Fix shape, original L1 checks, traps and the
Category-half text are untouched). RV.301 correctly stays OPEN (`[ ]` at `:961`, index `[ ]` at
`:103`); RV.305 is ticked in both places (`:963`, `:105`). `python3 scripts/tasks-index.py
--check` exit 0; `python3 scripts/scenario-index.py --check` exit 0 (528 rows, every open one
attached to a scenario - RV.301 keeps its F4/J6 tag).

## The artefacts are unchanged since review 1

Review 1's closing condition for a COMPLETE-without-re-run was "the RV.301 edit is the only
change" (`RV.305-COMPLETENESS.md:202-203`). I verified that condition at file level rather than
taking it on trust:

- **The code diff is the one review 1 judged.** `git diff` of `FuelExtractorTotalFinder.swift` is a
  single hunk (@@ -189,8 +189,13 @@): the comment extension at `:192-196` and the guard
  `(primary + payment).allSatisfy({ redundant >= $0 - 0.005 })` at `:197-198`. Every interior line
  reference review 1 cited still lands exactly: `redundantValue` definition `:109`, its only two
  callers `:176` and `:197` (grep: three hits, unchanged), `isRepeatedValue` `:125`, the
  net-versus-gross branch `:176-180`, the half-cent money convention `:101`, `:131`.
- **No test file moved.** `git status`: no expense/total/corpus test file is modified; the pins
  review 1 relied on are in the committed tree at the cited places -
  `RV277ExpenseTotalTests.swift:63-70` (first Tallinn ticket 2.00 EUR, green in the mutation log
  itself), `:34-39` + `:92-116` (the fixture-lines contradiction guard), `RV56TotalTests.swift:91-128`
  (receipt-001, 125.22) and `:130-149` (receipt-038, 79.32 - the tie case that MUST keep
  committing), `CorpusABTests.swift:56` (receipts 46/96), `:62` (fiscal 1/3), `:64-66`
  (screenshots 7/24).
- **Both logs are intact.** `/tmp/agentlogs/rv305-mutation.log` (2026-09-24 01:24) re-read this
  pass; `:19-24` match review 1's quotation verbatim. `/tmp/agentlogs/rv305-review-filter.log`
  (review 1's own 119/119 re-run, exit 0) still on disk (01:58).
- **The RV.305 row text** matches review 1's quotation of it verbatim, including the Built trace.

## Item-by-item re-confirmation (brief)

1. **Narrowest correct change / no other fixture's total moves - MET**, unchanged from review 1's
   finding, which stands on the identical artefacts. One addition this pass, closing a thread
   review 1 opened: `docs/EXTRACTION.md:554`'s claim that the first Tallinn ticket "resolved its
   amount through `redundantValue` (the `2.00` printed twice)" remains TRUE under the guard - the
   ticket has no total label, so `primary + payment` is empty, `allSatisfy` is vacuous, and the
   2.00 still commits; the behaviour is pinned by `firstTallinnTicketStillResolves`
   (`RV277ExpenseTotalTests.swift:63-70`), green even inside the mutation run (log `:18`).
2. **Wired into the app path - MET**, unchanged: the guard is inside `grandTotalRead` in the
   `TankbookCore` package the app links; no file in the
   `CaptureExpenseScan -> CapturePipeline -> ExtractionAssembler -> FuelExtractor -> resolveTotal`
   chain review 1 walked is modified in this diff (`git diff --stat`), and the guard file has no
   `#if DEBUG`. Release as well as Debug.
3. **Measured on the named population - MET**, on review 1's evidence, which is current because
   the artefacts are: the row's population is the expense and receipt corpus suites; the
   orchestrator's filter (`RV277|RV56|Expense|TotalFinder|FuelExtractor|Corpus`) is 119/119 and
   review 1 reproduced it independently (log on disk). The claimed movement (650 committed ->
   abstain; RV277 red -> green) is over exactly that population. Zero new wrong readings is
   structural: the guard converts commits into abstentions and can never invent a value. The pump
   template items (livePath floor, `PumpPhotoGate` reader constants) are not this row's artefacts;
   PU.78's in-tree edits move those constants and are judged by PU.78's own review, not here.
4. **No regression elsewhere - MET**, unchanged: this row's half of the diff is 9 lines in one core
   file plus the TASKS.md rows; receipt leak, annotated floor and oracle ratchet are pump
   artefacts it does not touch; the shared-rules-arm risk review 1 analysed (guard fires only on
   tied labels with a strictly-lower repeated value) still holds on the identical code. Latency:
   one `allSatisfy` over a handful of Doubles on the cold no-labelled-total path - no Release
   number owed.
5. **Tests that would fail - MET**, re-read verbatim this pass: with the guard dropped,
   `no expense fixture commits a value its expected.csv contradicts` goes red naming exactly this
   defect (`parts-vag-invoice-page-two-screenshot-ru.txt: committed total 650, expected 159373`,
   mutation log `:19-24`) while the other three RV277 tests stay green - a specific mutation. Both
   directions of the guard remain pinned (negative: the contradiction guard over the fixture's own
   lines; positive: receipt-038 and the first Tallinn ticket, cited above).
6. **Docs reconciled - MET now** (was MISSING, the sole defect). The TASKS.md circular hand-off is
   closed by the RV.301 amendment, verified above. `docs/EXTRACTION.md`: re-checked in the CURRENT
   tree - no stale statement about the expense total finder (`:554` true, see item 1; `:412`'s
   corroboration sentence describes `isCorroboratedTotal`, untouched); grep finds no `159 373` /
   tied-labels text in EXTRACTION.md, JOURNEYS.md or ERRORS.md, so there is nothing else to
   reconcile, and no numbered decision changes (the guard enforces the documented
   refuse-rather-guess stance). The working-tree EXTRACTION.md diff is PU.78's (its one
   "redundant" hit, `:1096`, is the pump close check) - ignored. `docs/ERRORS.md` /
   `docs/JOURNEYS.md`: no update needed, per review 1 (the new outcome lands inside J7b's shipped
   empty-form contract, `JOURNEYS.md:471`). Comments in the touched file: the ADDED comment
   (`:192-196`) is present tense, invariant-plus-example, no task ids or dates - compliant. The
   file's PRE-EXISTING task-id references (`:3` RV.56, `:90` RV.270, `:210`/`:237` RV.153) are
   documented legacy debt with its own tracked position (`docs/CODE-COMMENT-REVIEW.md:83`, `:221`,
   `:233` - the hygiene check rejects NEW task ids), not introduced by this row.
7. **Everything the row promised, sentence by sentence:**
   1. "The total rule that picked 650 traced" - **MET** (review 1 re-derived the trace
      independently; fixture, truth row and code references all re-verified intact this pass).
   2. "the label-to-value pairing across a column layout fixed with a test on this fixture's
      lines" - **MET now**, on review 1's own closure condition ("This sentence closes the moment
      RV.301's row absorbs it", `RV.305-COMPLETENESS.md:167-168`). The rescope (honest-miss guard
      instead of the pairing fix) is stated in the Built text, not silent; the fixture's lines ARE
      under test (`RV277ExpenseTotalTests.swift:92-116` reads the .txt at `:34-39`); and the
      deferred pairing fix / 159 373 reading now has an owner whose Checks name it
      (`docs/TASKS.md:961`).
   3. "`RV277ExpenseTotalTests` green" - **MET** (gate evidence + review 1's independent re-run;
      artefacts unchanged since).
   4. "mutation red" - **MET** (log intact, re-read verbatim this pass).

## Disclosure - what I ran and what I did not

I ran read-only checks only: git diff/status/log, greps, file reads, the two index scripts
(`--check`, exit 0 both), and re-reads of the two `/tmp/agentlogs` logs. **I did not re-run any
test suite and did not run PumpReadTool**: no number was missing, the brief's fence says no builds
that write, and review 1's sanctioned closure path is COMPLETE without re-running the code
evidence when the RV.301 edit is the only change - a condition I verified at file level above
rather than assuming. The test record for this row therefore remains the orchestrator's gate
evidence (119/119, mutation red, swiftlint 0) plus review 1's independent filter re-run. The
machine may be loaded by concurrent research dispatches; that does not affect file-level checks.

## Found, not fixed

- **The full-gate obligation is still open and now bigger.** Review 1's reminder stands and PU.78
  has since finished: its Shipped text (`docs/TASKS.md`) moves the `PumpPhotoGate` reader constants
  to 47/47/183 and `committedFloor` to 118, and `PumpReadingLawTests` / `PumpReaderPipelineTests`
  are modified in-tree - all postdating `pu78-gate.log`. The fresh full gate covering RV.305 and
  PU.78 together, on the CURRENT tree, remains the orchestrator's step before commit (the brief
  says as much: "The full gate runs with PU.78's"). This is process, not a defect in this row.
- **The sibling seam** (`FuelExtractorTotalFinder.swift:176-180`, weaker net-versus-gross
  invariant) is now OWNED - named in RV.301's row by the amendment - so review 1's "found, not
  fixed" entry is closed as filed. Nothing further owed here.
- Image-level Vision suites remain unrunnable on macOS 27 (pre-existing; PU.61's open re-baseline
  half owns it), so COMPLETE still does not mean "receipts class re-scored on images" - the
  committed-snapshot pins in `CorpusABTests` are the receipts-class evidence, as in review 1.

## Verdict

**COMPLETE** - every item MET. Review 1's single defect is closed exactly as its verdict drafted,
the artefacts it judged are byte-identical, and both index checks pass. The orchestrator may
commit - with the fresh full gate over RV.305 + PU.78 on the current tree run first, per the
brief's own plan.
