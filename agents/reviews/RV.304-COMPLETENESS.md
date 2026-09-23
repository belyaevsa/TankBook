# RV.304 completeness review - an expense fixture commits a category its expected.csv contradicts

Run 2026-09-23 against the working tree on HEAD `2f7fd5dd` (the uncommitted RV.304 diff). Research
note: none - per the run instructions, item 1 reads as: is the fix the narrowest one that corrects
both declared misses without changing any other fixture's category? Diff under review:
`ios/Sources/TankbookCore/Extraction/ExpenseCategoryInference.swift`,
`ios/Tests/TankbookCoreTests/RV200ExpenseCategoryInferenceTests.swift`, the RV.304 and RV.305 rows
in `docs/TASKS.md`. Nothing else is modified in the tree (the untracked `agents/briefs/RESEARCH-PU.*.md`,
`agents/briefs/REVIEW-COMPLETE-*.md` and `ml/pump-reader/runs/2026-09-23/` are concurrent
workstream artefacts; I did not touch them).

**What I ran**: read-only git/grep/sed inspection; `swiftlint lint --no-cache` on the two touched
Swift files (exit 0, no violations); `scripts/tasks-index.py --check` (exit 0) and
`scripts/scenario-index.py --check` (exit 0, 527 rows); inspection of
`/tmp/agentlogs/rv304-mutation.log` and `/tmp/agentlogs/rv304-app.log`; and a read-only Python
mirror of `ExpenseCategoryInference` (same `latinTwin` map as `FuelKindNormalizer.canonicalKey`,
same rule order, same `notWhen` blanking, same first-match-wins) run over **all 19 fixtures** in
`Spike/ReceiptSpike/fixtures/expenses/` and over the six inline expectations of the new/adjacent
tests. **No builds, no test runs, no writes except this file. I did not need
`swift run PumpReadTool` - no pump number was missing (this is an expense row), so machine load
affects nothing I report.** The mirror is the load-bearing evidence below: it proves the sweep and
both direction tests green and proves exactly which fixtures moved.

## The seven items

1. **Fidelity to the published method (here: narrowness) - MET.** The Python mirror over every
   fixture in the folder (the ten hand-authored ones included - they live in the same folder,
   `expected.csv:2-20`, 19 rows, matching the sweep's pinned count at
   `RV200ExpenseCategoryInferenceTests.swift:87`) shows **exactly two** fixtures change category:
   `parts-akhmadullin-kumho-tires-invoice-ru.txt` (`other:wash` -> `parts`, the "Технологическая
   мойка колеса" line at fixture line 40) and `parts-avtostart-vologda-28-lines-tovarny-chek-ru.txt`
   (`toll` -> `parts`, the "БЕСПЛАТНЫЙ" warranty line at fixture line 164). Both land on their
   `expected.csv` oracle (`expected.csv:17,19`); all 17 others are bit-identical in outcome, and
   all 19 now match (sweep green). By construction the change *cannot* touch anything else:
   blanking only ever removes text, only the wash and toll rules gained `notWhen`
   (`ExpenseCategoryInference.swift:77-79,89`), and grep over the whole folder shows the `notWhen`
   phrases occur only in those two fixtures (`toll-ru.txt`'s "ПЛАТНЫЙ УЧАСТОК" carries no
   "БЕСПЛАТН"; `wash-ru.txt`'s "МОЙКА КУЗОВА" carries no "КОЛЕС"). The phrases are generic
   vocabulary - the grammatical closure of "wheel wash" (nominative/genitive, Е/Ё, English) and the
   "free-of-charge" stem - not filename exclusions, so RV.302's fence ("a fixture-specific
   exclusion is not a fix", `docs/TASKS.md:958`) is respected; and the rule order is untouched, so
   RV.301's trap ("Do not move wash below parts blindly - `receipt-025` and the mixed-receipt
   detector depend on wash-first") is not tripped. Observations, none changing a fixture: the
   accusative "мойку колёс" is not in `notWhen` (a future invoice printing it misreads again - the
   sweep catches it at intake; RV.301's costed-lines weighing owns the general fix); blanking needs
   the phrase contiguous, so an OCR line break inside "мойка / колеса" defeats it; and a standalone
   "Мойка колес" (a genuine wheel-wash service) now abstains instead of reading `wash` - the
   deliberate conservative trade the file header already claims ("the `nil` answer is the point",
   `ExpenseCategoryInference.swift:27-30`), pinned in the compound form at
   `RV200ExpenseCategoryInferenceTests.swift:134`.

2. **Wired into the app path, not only the harness - MET.** The changed function is the shipped
   inference itself: `CaptureExpenseScan.swift:91` calls `ExpenseCategoryInference.infer(from:
   capture.ocrLines)` on the lines `CapturePipeline.process` produced (`CaptureExpenseScan.swift:129-137`),
   outside the `#if DEBUG` block - the DEBUG branch (`:72-90`) substitutes only the pipeline's
   *output* for UI-test seeds, and the `#else` (`:88-90`) reaches the same line 91, so the fix runs
   in Release exactly as in Debug. No `#if DEBUG` seam is touched anywhere in the diff, so the
   RELEASE-gate clause does not apply. The same call feeds the late-read inbox path
   (`ExpenseRecognition`, `CaptureExpenseScan.swift:101`). Not a harness-only method.

3. **Measured on the named population - MET, with one evidence-hygiene note.** The row names
   `RV277ExpenseTotalTests` and the mutation; the gate evidence reports 15 tests over the two
   suites with one remaining red. The counts corroborate: the RV.200 suite has 11 `@Test`s (the
   mutation log itself prints "Test run with 11 tests in 1 suite", `rv304-mutation.log:68`) and
   RV.277 has 4 (`RV277ExpenseTotalTests.swift:51,63,75,92`) = 15. My mirror independently proves
   the green half: the sweep over all 19 fixtures matches every oracle, and all six inline
   expectations of `wheelWashIsNotACarWash`, `freeIsNotAToll` and `paidParkingReadsAsParking`
   hold. RV.277's other three tests touch only `FuelExtractor` and the parking fixtures, none of
   which the diff changes. The claimed *remaining red* (vag total 650 vs 159373.00, RV.305) comes
   from the orchestrator's reading of the failure output; I cannot replicate `FuelExtractor`
   read-only, so I cannot independently confirm the red lists **only** that contradiction - see
   "found, not fixed" #3. Note: no captured log of the 15-test run exists in `/tmp/agentlogs/`
   (only the mutation and app logs); capture the filtered `swift test` output at commit time so the
   green counts rest on an exit code, not prose.

4. **No regression elsewhere - MET.** (a) The other 17 fixtures: unchanged, mirror-proven. (b) The
   mixed-receipt detector keeps its own independent wash stem (`MixedReceipt.swift:242`) - it does
   not call `ExpenseCategoryInference` (call-site grep: `CaptureExpenseScan.swift:91`, the two test
   suites, `CorpusExpenseScorer.swift:117`, the spike's `Parser.swift`) - so `receipt-025` and the
   forecourt wash-first behaviour RV.301 warns about are untouched. (c) The expense ratchet cannot
   fire: violations are hits-fall/corpus-shrink only (`AccuracyRatchetTests.swift:22-34`), the
   recorded mark is expenses 33/54 (`Spike/ReceiptSpike/fixtures/high-water.json`), and the kind
   cell is scored through the same `infer` (`CorpusExpenseScorer.swift:117`), so this change can
   only raise hits (33 -> 35 on a `.txt`-scored run). (d) The app-target unit bundle ran to
   completion: **301 tests, 0 failures, TEST SUCCEEDED** (`rv304-app.log:2112-2115`), covering the
   ExpenseEntry seed paths. (e) Latency: not a hot path - six substring replacements once per
   expense scan; no Release number needed. Notes: the full package `swift test` is not in the gate
   evidence (only the two filtered suites) - run it at commit time and expect **exactly one**
   failure, RV.277's `noExpenseFixtureCommitsAContradictedValue`, red on main since 2026-09-21;
   and the high-water expenses hits were not re-recorded, so the +2 gain is not ratchet-locked
   (the deterministic L1 sweep pins both categories regardless - corpus-workflow follow-up, not
   this row's).

5. **Tests that would fail - MET.** The mutation (ignore `notWhen`) turned **three** tests red, and
   the verbatim output is captured (`rv304-mutation.log:31-66`): `freeIsNotAToll` red at
   `RV200ExpenseCategoryInferenceTests.swift:140` (`.toll` where `.parts` is expected),
   `wheelWashIsNotACarWash` red at `:132` (`.other("wash")` where `.parts`), and the sweep red with
   2 issues at `:97` naming both fixtures and both old misreads. Every promise has a discriminating
   test: the tyre invoice -> parts (sweep + `:132`), the warranty text -> parts (sweep + `:140`),
   and both directions pinned - a car wash still reads wash (`:133-134`, plus `wash-ru.txt` in the
   sweep and `:121-124`) and a toll still reads toll (`:141`, plus `toll-ru.txt` and `:157`). The
   working tree carries the unmutated code (`ExpenseCategoryInference.swift:45-48`), so the
   mutation was reverted.

6. **Docs reconciled - PARTIAL.** Three gaps, two needing a fix before commit:
   - **(a) Stale comment in a touched file.** `RV200ExpenseCategoryInferenceTests.swift:11-15`
     still says "Nine fixtures are hand-authored text ... `parking-tallinn-airport-et.txt` is the
     Vision dump of **the one photograph the folder now holds**". The folder holds ten hand-authored
     fixtures and **nine** photographs (`CorpusExpenseScorer.swift:5-6` itself says ten). The
     sentence has been false since the 2026-09-21 intake, but this diff changes the file's
     behaviour, and the CLAUDE.md comment policy audits every comment in each touched file in the
     same change. Needed: rewrite the header sentence (or delete the count and name the oracle rule
     only).
   - **(b) Sibling rows in `docs/TASKS.md` not reconciled.** RV.302 (`docs/TASKS.md:958`) remains
     open describing both category misreads as live defects - its whole body is subsumed by this
     diff (both fixed; "the two texts as cases" now exist via the sweep plus the two inline tests),
     and only its "RV277ExpenseTotalTests green" check survives, which is RV.305's. RV.301
     (`docs/TASKS.md:960`) remains open with its first L1 check ("the tyre fixture leaves
     `declaredMisses` and infers `parts`") already satisfied here, and its remainder (costed-lines
     weighing, invoice total words for gorunov/kumho, which abstain rather than contradict) now
     overlaps RV.305. RV.304's Built text names neither sibling. Needed at commit: close or
     re-scope RV.302, trim/cross-reference RV.301, and say in the RV.304 commit or Built text what
     happened to them - "keeping the docs reconciled is part of every task's definition of done"
     (CLAUDE.md conflict rule).
   - **(c) Minor, no fix required now.** `Spike/ReceiptSpike/fixtures/expenses/recognised.csv`
     still records kumho -> `other:wash` and avtostart -> `toll`: a generated spike artefact
     ("never the oracle", `docs/EXTRACTION.md:577-581`), consumed by no test; regenerate at the
     next `swift run ReceiptSpike fixtures/expenses`. `docs/EXTRACTION.md` needs no edit: nothing
     it states becomes false (the vocabulary paragraph at `:523-545` describes behaviour that still
     holds; the score table at `:112` is a dated 2026-09-18 snapshot that defers to
     `high-water.json`). `docs/ERRORS.md` and `docs/JOURNEYS.md` J7b need none: no error surface
     changed, and the J7b promise (the scan suggests a category, editable, hard rule 13) is
     unchanged - it is merely right more often, which is not a story change. New comments in both
     touched Swift files are clean: present tense, no task ids, no dates
     (`ExpenseCategoryInference.swift:63-65,73-74,84-85`; test doc comments `:126-127,137`). The
     TASKS.md index is in sync (`tasks-index.py --check` exit 0) and RV.305 is scenario-attached
     (`scenario-index.py --check` exit 0).

7. **Everything the row promised - PARTIAL (one sentence, discharged by a filed row).** The Checks
   cell of RV.304 (`docs/TASKS.md:961`), sentence by sentence:
   - "The rule that picks `wash` on a tyre invoice traced and fixed (or the fixture's truth
     corrected, with evidence)" - **MET**: traced (the wash rule runs first and "мойка колеса" hits
     the `МОЙК` stem), fixed via `notWhen`; the sibling toll misread in the same function was fixed
     in the same change, per the sibling rule; `expected.csv` untouched, the correct branch - the
     paper is a parts invoice, so the inference was wrong, not the truth.
   - "`RV277ExpenseTotalTests` green" - **PARTIAL**: the category contradictions are gone
     (mirror-proven), but the suite is still red on the vag total, so the suite is not green at
     this commit. This is not a quietly dropped promise: the Built text names it ("The remaining
     `RV277ExpenseTotalTests` contradiction is a TOTAL, a different function - RV.305") and RV.305
     is drafted in this very diff (`docs/TASKS.md:962`, index row `:105`) with its own repro and
     checks - the template's remedy for a gap this row does not close. The total finder is a
     different function and a different decision (label-to-value pairing across a column layout),
     which the standing fence says to file rather than fold in. Consequence to state plainly:
     `swift test`, and therefore `scripts/gate.sh`, cannot exit 0 until RV.305 lands - a
     pre-existing state of main since 2026-09-21, not one this row introduces.
   - "Mutation of the fix red" - **MET**: captured verbatim, three tests (item 5).

## Found and did not fix

1. **RV.302 and RV.301 need reconciling against this row** (item 6b) - owned by the orchestrator's
   commit; no row owns the reconciliation itself.
2. **The stale test-file header** (item 6a) - one sentence, fix at commit.
3. **Verify the remaining red's content at commit time.** RV.305's premise ("the LAST
   contradiction after RV.304") rests on the failure message listing only the vag total. I could
   not check `FuelExtractor` read-only, and `recognised.csv` (the *spike* parser, a different code
   path) shows mobiletron committing 294.34 against an expected 1766.00 - if `FuelExtractor`
   commits that too, RV.305's text needs a second fixture. The orchestrator's captured failure
   output settles it in one look.
4. **`recognised.csv` is stale** (item 6c) - regenerated by the spike run, no consumer; corpus
   workflow owns it.
5. **High-water expenses hits (33) not re-recorded** after a +2 gain - ratchet-safe either way;
   re-record on the next measured-runtime session so the gain locks in.

## Verdict

**INCOMPLETE** - one item PARTIAL:

- **Item 6 (docs reconciled).** Needed: (a) rewrite the stale header sentence at
  `RV200ExpenseCategoryInferenceTests.swift:11-15` (ten hand-authored fixtures, nine photographs,
  not "the one photograph the folder now holds"); (b) reconcile the sibling rows - close or
  re-scope RV.302 (fully subsumed by RV.304 + RV.305) and trim RV.301's satisfied first check with
  a cross-reference to RV.304/RV.305 - in the same commit.
- Item 7's PARTIAL sentence ("RV277ExpenseTotalTests green") is **discharged** by RV.305, drafted
  in this diff and named in the Built text, per the template's new-row remedy; it does not by
  itself block, but the commit message should say the suite stays red until RV.305 lands.
- Recommended with the fixes (not blocking): capture the filtered 15-test `swift test` log beside
  the mutation log, and confirm from the failure output that the vag total is the only remaining
  contradiction (found-not-fixed #3).

Everything else - narrowness (mirror-proven: exactly the two declared misses moved, all 19 oracles
met), app-path wiring in Debug and Release, the mutation's three red tests, the 301/0 app bundle,
and the ratchet - is MET. After (a) and (b), re-dispatch a fresh copy of this review.
