# RV.304 completeness review - second pass

Run 2026-09-23 against the working tree on HEAD `2f7fd5dd` (the uncommitted RV.304 diff, as
review 1). Scope per the run instructions: verify the four item-6 closures review 1 required, and
re-open items 1-5 only if something changed - **nothing did** (evidence below). The concurrent
PU.78 edits (`PumpReadingLaw.swift`, `PumpReadingLawTests.swift` - pump-law operand-close text,
inspected only to confirm they are pump work) are ignored as instructed.

**What I ran**: read-only git/grep/sed/awk/python inspection; `swiftlint lint --no-cache` on the
two touched Swift files (exit 0, 0 violations); `scripts/tasks-index.py --check` (exit 0);
`scripts/scenario-index.py --check` (exit 0, 527 rows); inspection of
`/tmp/agentlogs/rv304-mutation.log` and `/tmp/agentlogs/rv304-app.log`; the receipt-025 OCR dump
in `diagnostics/receipt-ocr-lines.txt`; the vag/mobiletron fixture dumps, `expected.csv`,
`recognised.csv`, `fixtures/expenses/README.md` and `high-water.json`. **No builds, no test runs,
no writes except this file. I did not need `swift run PumpReadTool` - no pump number was missing
(this is an expense row), so machine load affects nothing I report.**

## The item-6 closures review 1 required

- **(a) Stale test header - CLOSED.** `RV200ExpenseCategoryInferenceTests.swift:11-15` no longer
  names fixture counts or "the one photograph the folder now holds". The replacement is accurate
  against the folder: ten hand-authored fixtures and nine photographed ones with the Vision dump
  as `.txt` beside the image (`fixtures/expenses/README.md:8-9,15-22`; `expected.csv:2-20` = 19
  rows, matching the sweep's pinned count at `RV200ExpenseCategoryInferenceTests.swift:87`). The
  counts are gone, so the sentence cannot go stale again on the next intake - review 1's preferred
  option. Present tense, no task ids, no dates; the referenced README path exists.
- **(b) RV.302 closed - CLOSED.** `docs/TASKS.md:958` is `[x]` with a close note: both categories
  fixed by `notWhen` phrases, tests pin both directions, `declaredMisses` empty, the remaining red
  is one TOTAL - RV.305. Every claim checks: `ExpenseCategoryInference.swift:77-79,89`;
  `RV200ExpenseCategoryInferenceTests.swift:79` (empty), `:133-134` (wash still wash), `:141`
  (toll still toll). The parenthetical "(filed as a duplicate before this row was found)" is
  git-verified: RV.302 was filed first (`dc28cb2c`, 2026-09-21) and RV.304 was filed over it
  without noticing (`a7bec85c`, 2026-09-23); the duplication was found during this row's work.
- **(c) RV.301 annotated - CLOSED.** `docs/TASKS.md:960` stays open with a dated annotation
  splitting the row: category half done by RV.304, TOTAL half open (the two delivery notes'
  `Всего :` / `На сумму :` totals - gorunov 11 850.00, kumho 87 600.00, untouched by this diff),
  VAG's column-laid total is RV.305. Each claim verified: the tyre fixture infers `parts` and left
  `declaredMisses` (diff); wash still runs first (`ExpenseCategoryInference.swift:72-79`, rule
  order unchanged) and `wash-ru.txt` keeps reading wash (`RV200...Tests.swift:123` plus the sweep);
  and the parenthetical "receipt-025 carries no wash text" is true - its OCR dump's only service
  line is `Услуга по регистрации покупки` at 69.28, no wash stem anywhere
  (`diagnostics/receipt-ocr-lines.txt:1098-1160`). Review 1 asked for trim/cross-reference; the
  annotation is the cross-reference branch and states the remaining scope exactly.
- **(d) RV.304 ticked with a duplicate note - CLOSED.** `docs/TASKS.md:961` is `[x]`; the Built
  text names the duplication ("Duplicate of RV.302 and RV.301's category half, both reconciled in
  the same commit") and review 1's closure, as review 1 required. Its technical claims re-checked
  against the code and logs: `notWhen` blanking (`ExpenseCategoryInference.swift:46`), the phrase
  lists (`:77-79,89`), the mutation red on three tests (`rv304-mutation.log:31-68`). The
  `/tmp/agentlogs/` citation follows the established row convention (PU.68, PU.79, PU.80 rows cite
  the same paths).

## The seven items

1. **Fidelity (narrowness) - MET, unchanged.** No code change since review 1 (below); its
   Python-mirror proof stands: exactly the two declared misses moved, all 19 oracles met, the
   `notWhen` phrases occur in no other fixture, rule order untouched.
2. **Wired into the app path - MET, unchanged.** `CaptureExpenseScan.swift:91` calls the changed
   function outside the `#if DEBUG` seam; no `#if DEBUG` file is in the diff.
3. **Measured on the named population - MET, unchanged.** The row named the expense corpus suites:
   gate evidence reports 15 tests (11 RV.200 + 4 RV.277 - both counts independently corroborated:
   `rv304-mutation.log:68` prints "11 tests in 1 suite"; RV.277 has 4 `@Test`s at
   `RV277ExpenseTotalTests.swift:51,63,75,92`), one remaining red = RV.305's total. Review 1's
   found-not-fixed #3 (could mobiletron be a second, unnoticed contradiction?) is now settled by
   structure: the contradiction test joins **every** contradiction into one `#expect` message
   (`RV277ExpenseTotalTests.swift:94-115`), so the orchestrator's reading of the single red
   failure covers the whole class - a mobiletron contradiction would have printed in the same
   message. `recognised.csv:20`'s 294.34 is the *spike* parser's artefact, a different code path
   (`fixtures/expenses/README.md:70-73`). The hygiene note stands: attach the filtered 15-test log
   at commit time (none is captured; only the mutation and app logs exist).
4. **No regression elsewhere - MET, unchanged.** Review 1's mirror proof plus: the app bundle log
   now shows completion - **301 tests, 0 failures, TEST SUCCEEDED** (`rv304-app.log:2112-2115,2123`);
   the ratchet cannot fire (violations are hits-fall/corpus-shrink only,
   `AccuracyRatchetTests.violation`; the recorded mark is expenses 33/54 in `high-water.json`, and
   the two flipped fixtures can only raise hits). Latency: not a hot path.
5. **Tests that would fail - MET, unchanged.** The mutation log is intact and verbatim: three red
   tests (`rv304-mutation.log:31,36,48-63` - `:140` toll→parts, `:132` wash→parts, the sweep with
   2 issues at `:97` naming both fixtures), 4 issues in the suite, and the working tree carries the
   unmutated code (`ExpenseCategoryInference.swift:45-48`).

**Why items 1-5 did not re-open**: every file:line citation in review 1 still lands exactly on the
current files (`ExpenseCategoryInference.swift:27-30,45-48,63-65,73-74,77-79,84-85,89`;
`RV200...Tests.swift:79,87,97,121-124,126-135,137-142,157`); the inference file's mtime (23:30)
predates review 1 (written 23:53), so it was not touched after being reviewed; the test file's
post-review edit (23:56) is confined to header lines 11-13, replaced 3-for-3 with no line shift -
which the landing citations confirm independently.

6. **Docs reconciled - MET (was PARTIAL).** All four closures above verified. Re-checked
   independently this pass: `docs/EXTRACTION.md` needs no edit - the vocabulary paragraph
   (`:523-550`) states nothing the `notWhen` mechanism falsifies (no rule-order or first-match
   mechanism text exists in the doc to go stale); no other doc repeats the old header's "one
   photograph" claim; `declaredMisses` is referenced in docs only inside the three RV rows, each
   now carrying its correct state; `docs/ERRORS.md` and J7b need nothing (no error surface changed;
   the suggestion stays an editable default, hard rule 13 - right more often is not a story
   change). Both index scripts exit 0; RV.305 is indexed and scenario-attached (J7b). CLAUDE.md
   comment rules hold in both touched files: current truth only, no task ids, no dates in the new
   comments (the pre-existing `MARK: - RV.200` section labels match the suite's file naming and
   predate this diff). Review 1's 6c minors stand as recorded: `recognised.csv` is stale (generated
   spike artefact, never the oracle, no test consumer - regenerated at the next
   `swift run ReceiptSpike fixtures/expenses`).
7. **Everything the row promised - unchanged from review 1.** "Traced and fixed" MET; "mutation
   red" MET; "`RV277ExpenseTotalTests` green" PARTIAL, **discharged** by RV.305 - drafted in this
   diff, indexed, scenario-attached, with a plausible repro I fixture-verified: the vag dump
   carries `650,00` line items (`parts-vag-invoice-page-two-screenshot-ru.txt:10-11,72-73`)
   against expected 159373.00 (`expected.csv:20`). Per review 1 this does not block, but the commit
   message must say the suite (and therefore `scripts/gate.sh`'s `swift test` step) stays red until
   RV.305 lands - a state of main since 2026-09-21, not one this row introduces.

## Found and did not fix

1. **`MixedReceipt.suggestCategory` shares the defect shape, in a different seam** -
   `MixedReceipt.swift:239-249` (called at `:164`): the same word-boundary-less stems (`ПЛАТН`
   inside `БЕСПЛАТНЫЙ` → `.toll`; `МОЙК` → wash) with no `notWhen` blanking. Not a live defect for
   the RV.304 shapes: `findExtraItems` requires a costed line (`amount > 0`, `:161`), so a
   zero-priced wheel-wash step or warranty boilerplate with no operand pair never reaches the
   suggester, and its output is an editable suggestion (hard rule 13). It is a different decision
   (per-title suggestion on a mixed-receipt split), so per the standing fence it is filed, not
   folded: the natural home is RV.301's remaining word-boundary/costed-lines scope, or a small row
   of its own. **No row owns it today.** Non-blocking for this commit.
2. **RV.301's pre-existing L1 sentence rests on a false premise** - "receipt-025's service line
   ... still infer wash" (`docs/TASKS.md:960`): receipt-025 carries no wash text, as the new
   annotation itself records. Correct or drop that clause when the TOTAL half is worked; RV.301
   owns it. Non-blocking.
3. **Carried from review 1**: attach the filtered 15-test `swift test` log at commit time (item 3);
   regenerate `recognised.csv` at the next spike run; re-record the high-water expenses mark (33)
   on the next measured-runtime session so the +2 gain locks in (ratchet-safe either way).
4. **Commit hygiene**: the tree also holds the concurrent PU.78 edits
   (`PumpReadingLaw.swift`, `PumpReadingLawTests.swift`) - stage only the three RV.304 files.

## Verdict

**COMPLETE** - every item MET (item 7's one open sentence discharged by RV.305, drafted and
indexed in this diff, per the template's new-row remedy). The orchestrator may commit, with:
the commit message stating that `RV277ExpenseTotalTests` stays red until RV.305 lands; only the
three RV.304 files staged; and, recommended, the filtered 15-test log captured beside the
mutation log.
