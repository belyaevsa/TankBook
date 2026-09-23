# RV.305 completeness review - is this expense-total row actually done?

- **Row:** RV.305 - a column-laid invoice commits a line amount as its total (`docs/TASKS.md:963`,
  ticked in the tree pending this review; index row `docs/TASKS.md:105` ticked too).
- **Reviewed:** 2026-09-24, reviewing agent under `agents/briefs/REVIEW-COMPLETE-RV.305.md`.
- **Diff under review:** `ios/Sources/TankbookCore/Extraction/FuelExtractorTotalFinder.swift:192-198`
  (the guard on `grandTotalRead`'s last fallback) and the RV.305 row in `docs/TASKS.md`. PU.78's
  concurrent edits (`PumpReadingLaw.swift`, pump tests, `PumpPhotoGate.swift`, `docs/EXTRACTION.md`)
  were present in the tree and IGNORED as instructed; nothing below judges them.
- **Evidence examined:** `git diff` of both files; the fixture and its expected.csv; every caller of
  `redundantValue`/`grandTotalRead`/`receiptGrandTotal`; `/tmp/agentlogs/rv305-mutation.log` (read
  verbatim); `/tmp/agentlogs/pu78-gate.log` (the 01:24 full `swift test`, which ran WITH the guard in
  the tree). **I re-ran the orchestrator's filter myself** - `swift test --filter
  "RV277|RV56|Expense|TotalFinder|FuelExtractor|Corpus"` in `ios/`: **119 tests in 32 suites, all
  passed, exit 0** (`/tmp/agentlogs/rv305-review-filter.log`), which also proves the post-mutation
  restore is the gated state. Other research dispatches were active on the machine; a wait for a
  concurrent SwiftPM instance is possible in that log, and the machine may have been loaded. No
  pump measurement tool was needed - the row claims no pump number.

## Item-by-item

### 1. Fidelity / narrowest correct change (the run's redefined item 1) - MET

**The guard is the narrowest change that kills the defect.** It sits only on the fallback that
fired: `grandTotalRead` reaches `FuelExtractorTotalFinder.swift:197` only when `modal` returned nil
(`:166`, `:181-184`), i.e. labels tied or nothing paired. When nothing paired, `primary + payment`
is empty and `allSatisfy` is vacuous - unlabelled-fallback behaviour (the receipt-041/047 shape,
`resolveTotal`'s fuel-line rescue at `FuelExtractor.swift:363-367`) is untouched. Behaviour can
change only for a document with TIED labelled figures whose dominant repeated value sits strictly
below all of them. The `- 0.005` half-cent slack matches the file's money convention (`:80`, `:101`,
`:131`). `redundantValue` itself is unchanged, so the net-versus-gross branch (`:176-180`) and the
corroboration helpers (`isRepeatedValue :125`, `isCorroboratedTotal :238`) are untouched.

**`redundantValue`'s other callers:** there are none beyond the two in `grandTotalRead` - grep over
`ios/` finds exactly three hits: the definition (`:109`) and the two call sites (`:176`, `:197`).
The `:176` branch requires `redundant > labelled` (the net-versus-gross invariant, receipt-001) and
is not reachable for the VAG invoice (its primaries tie, so `labelled` is nil). See "found, not
fixed" below for its residual shape.

**The trace in the row's Built text re-derived independently, and it holds.** In
`Spike/ReceiptSpike/fixtures/expenses/parts-vag-invoice-page-two-screenshot-ru.txt`: `Итого:` (line
108) has no same-baseline value in the text dump (zero boxes), so `pairedValue` takes the adjacent
line BELOW (`FuelExtractorTotalFinder.swift:284`) - `4 152,00` (txt:109, the discount column).
`Сумма документа:` (txt:112) takes the adjacent line ABOVE (`:283`) - `159 373,00` (txt:111). Both
labels are primary, counts tie, `modal` abstains (`:329-343` - the deliberate nil tie-break).
`650,00` prints four times (txt:10, 11, 72, 73), strictly dominant, so `redundantValue` returns
650 - what the old fallback committed and what `expected.csv:20` (159373.00, parts) contradicts.
With the guard, 650 is below both 4 152 and 159 373, so the finder abstains: an honest miss.

**Does it alter any OTHER fixture's total? No - measured, not argued.**
- receipts class: `CorpusABTests.swift:54-56` scores the RULES arm (this parser) over the committed
  sweep snapshot with an exact pin, `receipts 46/96` - green in the filtered re-run and in the full
  gate. Any receipt total moved by the guard moves that pin. fiscal `1/3` (`:62`) and screenshots
  `7/24` (`:64-65`) pinned and green the same way.
- receipt-001 (documented redundancy case): resolves through the net-versus-gross branch, pinned at
  `RV56TotalTests.swift:91-128` (125.22) - green.
- receipt-038 (documented redundancy case): the tie case that MUST keep committing - labels tie
  [79.32, 15.35], the repeated 79.32 equals the higher tied figure, passes the guard, pinned at
  `RV56TotalTests.swift:130-149` - green. This is the test that would catch an over-tightened
  guard.
- expenses: the first Tallinn ticket, whose amount EXTRACTION.md:554 says resolves "through
  `redundantValue` (the `2.00` printed twice)", is pinned at `RV277ExpenseTotalTests.swift:63-70` -
  green; the whole expense folder's contradiction guard (`:92-116`) is green.
- fiscal QR: `composeQR` (`FuelExtractorTotalFinder.swift:24-43`) runs downstream and the QR total
  is authoritative there, so the guard cannot move a QR-composed total; "RV.56: the fiscal QR in the
  scored extraction" suite green.
- The full-package run with the guard in the tree (`pu78-gate.log:10004`, 2282 tests) failed ONLY
  the two mid-flight `PumpReaderPipelineTests` constant assertions (PU.78's, out of scope) - every
  other suite in the package green.

### 2. Wired into the app path, not only the harness - MET

The guard is inside `grandTotalRead` itself, in the `TankbookCore` package the app links; there is
no tool-only or test-only seam and no `#if DEBUG` anywhere in the chain (grep over all five files:
the only hit is `CaptureExpenseScan.swift:72`, the test-seed branch, whose `#else` at `:88-89` runs
the real path in Release). The expense door the row is about:
`CaptureExpenseScan.swift:131` (`expenseCapture` -> `CapturePipeline.process(image, source:
.receipt, ...)`) -> `CapturePipeline.swift:42,77` (`process` -> `recognize`) ->
`ExtractionAssembler.swift:63` (`FuelExtractor(bandProvider:)`) -> `FuelExtractor.swift:70`
(`extract` -> `resolveTotal`) -> `FuelExtractor.swift:347-348` (`resolveTotal` -> `grandTotalRead`)
-> the guard at `FuelExtractorTotalFinder.swift:197-198`. The fill-up receipt door runs the same
`process`, and the pump composite's rules arm does too (`CapturePipeline.swift:81`,
`composed(rules:...)`) - all Release paths. Downstream readers of the public `receiptGrandTotal`
(`CrossCheck.swift:61`, `MixedReceipt.swift:230`) get nil on a tied-labels invoice, i.e. the
mixed-receipt detector abstains there; the "Mixed receipt: grouped-save plan" suite is green and a
column-laid parts invoice is not a fuel receipt, so nothing user-facing is lost.

### 3. Measured on the app path, on the named population - MET

The row names no pump population; the run's population is the expense and receipt corpus suites.
The orchestrator's claimed movement (650 committed -> abstain on the VAG fixture; RV277 red ->
green) is reported over exactly that population, and I reproduced it: the filtered run above is
**119/119, 32 suites, exit 0**, including the RV277 suite over every expense fixture's lines
(1.902 s) and the rules-arm snapshot pins over receipts/fiscal/screenshots. `PumpPhotoGate`'s
reader constants are not this row's and are untouched by its diff. Zero new wrong readings is
structural: the guard can only convert a commit into an abstention, never invent a value - the
only fixture whose outcome changes is the one the row names, and it changes from confident-wrong
to honest miss. Image-level Vision suites (`RV56TotalPropertyTests`, `CorpusAccuracyGateTests`,
`CorpusCompressionTests`) skipped on this macOS 27.0 machine by the documented runtime rule
(`VisionMeasuredRuntime.swift:14`, measured on 26; `docs/TESTING.md`) - a pre-existing condition of
every row since the machine moved, not a gap this row opened; the committed-snapshot scoring in
`CorpusABTests` covers the same fixtures' text offline, and the re-baseline remains owned by
PU.61's open half.

### 4. No regression elsewhere - MET

Receipt leak, annotated floor, oracle ratchet: pump artefacts this diff does not touch
(`git diff --stat`: the RV.305 half is 9 lines in one core file plus the row). The pump rules arm
shares `grandTotalRead`, so the guard is in principle pump-visible - but it fires only on tied
labels with a lower repeated value, the rules arm commits 7/7 cells on heldout (PU.62's
measurement), and the full 2282-test run with the guard showed no non-PU.78 failure. The fresh
full gate covering both rows is the orchestrator's stated obligation before commit, and the two
pump failures in the 01:24 log are PU.78's constants in flight, not this row's. Latency: the guard
adds one `allSatisfy` over the labelled-reads array (a handful of Doubles) on the cold
no-labelled-total path - not a hot path, no Release number owed. The 55 skips in the full gate are
the runtime-gated suites above, unchanged in count and reason.

### 5. Tests that would fail - MET

Mutation evidence read verbatim: `/tmp/agentlogs/rv305-mutation.log:19-24` - with the guard
dropped, `no expense fixture commits a value its expected.csv contradicts` fails with exactly the
row's defect back: `parts-vag-invoice-page-two-screenshot-ru.txt: committed total 650, expected
159373`; the other three RV277 tests stay green, so the mutation is specific. The restored tree is
green in my hands (filtered re-run, exit 0). Both directions of the guard are pinned: the negative
side (repeated value below every labelled figure -> abstain) by RV277's contradiction guard over
the fixture's own lines (`RV277ExpenseTotalTests.swift:92-116`, which reads the fixture .txt at
`:34-39`); the positive side (repeated value at/above the tied figures still commits) by
receipt-038 (`RV56TotalTests.swift:130-149`) and the first Tallinn ticket
(`RV277ExpenseTotalTests.swift:63-70`). A guard mutated in either direction has a red test.

### 6. Docs reconciled - MISSING (one defect, one-line fix)

- `docs/EXTRACTION.md`: no stale statement. The doc never described the unlabelled/tie fallback
  beyond :554 (still true, test-pinned) and :412's corroboration mention (untouched branch). No
  numbered decision changes: the guard *enforces* the documented stances - §4 "Each returns `nil`
  rather than guessing" (:272-283) and the deliberate nil tie-break (:1261-1266, P2.14). The
  working-tree EXTRACTION.md diff is all PU.78's; correctly not this row's.
- `docs/ERRORS.md`, `docs/JOURNEYS.md`: no update needed. The new outcome (category `parts`
  pre-selected, amount blank) lands inside J7b's shipped contract: "A scan that reads nothing opens
  the EMPTY expense form with no error (hard rule 7)" (`JOURNEYS.md:471`), amount pre-fill offered
  never promised (`:464-466`), suggestion-not-fact (hard rule 13). No error surface changes.
- Comments in the touched file: current truth, present tense, no task ids, invariant-plus-example
  in the file's existing house style (cf. `:167-175`). Compliant with the CLAUDE.md comment rules.
- **The defect - a circular hand-off in `docs/TASKS.md`.** RV.305's Built text leaves the residual
  work ("Reading 159 373 itself needs a label-ranking decision (`Сумма документа` over a column
  `Итого`)") with "**RV.301's open total half**" (`docs/TASKS.md:963`). But RV.301's row
  (`docs/TASKS.md:961`, NOT edited by this diff) says the opposite: "What stays open here is the
  TOTAL half - the two delivery notes' `Всего :` / `На сумму :` totals; **the VAG page's
  column-laid total is RV.305**" - and RV.301's Checks cell names only the two delivery notes
  (11 850.00, 87 600.00). With RV.305 closed, no open row owns reading the VAG invoice's
  159 373,00; an agent closing RV.301 against its Checks as written would drop it silently - the
  exact shape item 7 exists to catch, and a CLAUDE.md conflict-rule violation ("fix the stale doc
  in the same change"; keeping docs reconciled is part of the definition of done).

### 7. Everything the row promised (Checks cell, sentence by sentence)

1. "The total rule that picked 650 traced" - **MET.** Re-derived independently in item 1: the
   adjacent-line pairings, the primary tie, the modal-value fallback, the four 650,00 prints.
2. "the label-to-value pairing across a column layout fixed with a test on this fixture's lines" -
   **PARTIAL.** The pairing is NOT fixed - `Итого:` still pairs with the discount column's
   `4 152,00`; that mispairing is why the primaries tie. What shipped is the narrower, defensible
   substitute recorded in the Built text: the redundancy fallback refuses a repeated value below
   every labelled figure, turning a confident-wrong 650 into an honest miss (hard rule 13, and the
   same refuse-rather-guess stance `modal`'s documented tie-break already takes). The rescope is
   stated, not silent, and the fixture's lines ARE under test (RV277's contradiction guard runs
   exactly those lines). But the promised pairing fix / the 159 373 reading is deferred work whose
   named owner does not accept it - item 6's defect. This sentence closes the moment RV.301's row
   absorbs it.
3. "`RV277ExpenseTotalTests` green" - **MET.** Green in the full gate with the guard
   (`pu78-gate.log:9519,9806`) and in my filtered re-run.
4. "mutation red" - **MET.** Verbatim log, specific failure, restored state green.

## Found, not fixed

- **The sibling call site (`FuelExtractorTotalFinder.swift:176-180`) keeps a weaker invariant.**
  The net-versus-gross override commits a repeated value that is greater than the MODAL labelled
  figure but could in principle sit below some OTHER labelled figure (e.g. a twice-printed line
  item above a mispaired small modal). No corpus fixture triggers it - the rules-arm snapshot pins
  (receipts 46/96) and the full 2282-test run are green - and it is a different invariant from the
  guarded fallback (there, redundancy ABOVE the label is the point), so per the sibling fence this
  is file-it territory, not fix-it-here. Natural owner: RV.301's rework of `grandTotalRead`'s
  label ranking; suggest one clause in its Fix shape naming the seam.
- The image-level Vision suites remain unrunnable on macOS 27 (pre-existing, `PU.61`'s open
  re-baseline half owns it). Nothing for this row to do; noted so the COMPLETE verdict is not
  misread as "receipts class re-scored on images".

## Verdict

**INCOMPLETE** - items 1-5 and 7.1/7.3/7.4 are MET; item 6 is MISSING and 7.2 PARTIAL for the same
single reason. The code needs no change. What is needed:

1. **Edit RV.301's row (`docs/TASKS.md:961`) in the same commit** so the residual work has an
   owner. Draft: replace "the VAG page's column-laid total is RV.305" with - "the VAG page's
   column-laid total joins this half from RV.305 (closed 2026-09-24 with an honest-miss guard):
   reading its 159 373,00 needs the label-ranking decision (`Сумма документа` over a column-laid
   `Итого`)" - and extend the Checks cell: "the VAG page resolves 159 373.00 through the recorded
   label-ranking decision (or its truth is corrected, with evidence); the tied-labels abstention
   RV.305 pinned stays".
2. Optionally add to RV.301's Fix shape the sibling seam above (`grandTotalRead`'s net-versus-gross
   override, `FuelExtractorTotalFinder.swift:176-180`).
3. Re-dispatch this review (a fresh copy, same row) against the amended row; on that pass, if the
   RV.301 edit is the only change, items 6 and 7.2 close and the verdict can be COMPLETE without
   re-running the code evidence in this file.

Reminder for the commit itself (the orchestrator's own plan, restated for the record): the fresh
full gate covering RV.305 and PU.78 together still owes a green run - the last full log
(`pu78-gate.log`) predates PU.78's final edits and carried its two in-flight pump failures.
