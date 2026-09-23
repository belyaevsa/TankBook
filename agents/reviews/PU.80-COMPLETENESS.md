# PU.80 completeness review - the corpus sweep ratchets, red on every intake

Run 2026-09-23 against the working tree on HEAD `a7bec85c`. Research note: none - a
test-maintenance row, so item 1 reads as fidelity to the owner's approval (*"we don't use
PaddleOCR. It was too complicated and long to wait for it"*) and nothing more. Diff under review:
`ios/Tests/TankbookCoreTests/PostSweepCorpusAdditions.swift`, `ios/Tests/TankbookCoreTests/PaddleOCRTests.swift`,
`.claude/skills/corpus-intake/SKILL.md`, `docs/EXTRACTION.md` (the P4.13 "Retired" paragraph) and
the PU.80 row in `docs/TASKS.md`.

**What I ran**: read-only git/grep/ls inspection; a read-only Python mirror of `CorpusScorer`'s
arithmetic (numerics-only expected, 0.005 tolerance, `sweptImages` = records ∩ disk, the same
extension set incl. `.heic`/`.tiff`) recomputing every pinned score of all three arms and the full
coverage relation in both directions for all four classes; `scripts/tasks-index.py --check`
(exit 0); inspection of `/tmp/agentlogs/pu80-mutation.log`. **No builds, no test runs, no writes
except this file. I did not need `swift run PumpReadTool` - no number was missing, so machine
load affects nothing I report.** The working tree also carries uncommitted corpus-annotation
changes (`corpus.sqlite`, `pump/windows.json`, `pump-live/corrections.jsonl`) from the concurrent
workstream; per the fence I did not touch them, and neither suite reads them (they read images,
`expected.csv` and `vision-ab/*.json` only). They are outside this review's diff - see observation 2.

## The seven items

1. **Fidelity to the approved method - MET.** No paper; the approval is the retirement of
   PaddleOCR. The change does exactly that and nothing more: the forward coverage loop is gone
   from `PaddleOCRTests` and replaced by the backward-only `armARecordsNameImages`
   (PaddleOCRTests.swift:31-43) - which is the *retained half* of the old test, not new
   behaviour; the frozen scoring is untouched (`armAScores` still pins 29/96, 2/45, 1/3, 7/24 at
   PaddleOCRTests.swift:17-23 - the diff changes only section 2); the sweep files are kept as the
   record (all `paddleocr-a-*.json` and `paddleocr-a-runs-*.json` present in
   `Spike/ReceiptSpike/fixtures/vision-ab/`, unmodified in the diff); the LLM arm's frozen sweep is
   answered by declaration, not re-sweep (PostSweepCorpusAdditions.swift:134-145, 495-543). No
   production code, no app behaviour, no unlisted departure.

2. **Wired into the app path - N/A.** Per the run instructions: nothing here runs in the app. The
   diff touches two test-support files, one skill doc and two docs; no path to
   `PumpDisplayCapture.classify` or `CapturePipeline` exists in it, and none is claimed.

3. **Measured on the app path - N/A.** No pump number moves; the row claims none. Corroborated:
   the pinned arm scores are recomputed over `sweptImages` (records ∩ disk), which declaration
   cannot change - my mirror reproduces every pinned literal exactly (below, item 4).

4. **No regression elsewhere - MET.**
   - `PostSweepCorpusAdditions.forClass` has exactly ONE consumer repo-wide:
     CorpusABTests.swift:91. The only other grep hits are docs and the gitignored stale snapshot
     `ml/pump-reader/.out/review-why/tree` (`git check-ignore` confirms). So the declaration list
     cannot move any other suite.
   - **Independent recomputation of all twelve pinned scores** (my Python mirror of the scorer on
     the committed fixtures): rules 46/96, 1/45, 1/3, 7/24; LLM 84/96, 31/45, 2/3, 22/24;
     paddleocr-a 29/96, 2/45, 1/3, 7/24 - every one equal to the literals asserted at
     CorpusABTests.swift:56-77 and PaddleOCRTests.swift:19-22. The red-then-green 15/15 is
     arithmetically consistent, not just an orchestrator claim.
   - Coverage relation, both directions, all four classes: zero images neither swept nor declared;
     zero LLM records without an image; zero declarations without an image; zero ghost records in
     `paddleocr-a-*.json` (35/17/1/8 records, all on disk) - so `armARecordsNameImages` is green
     today and correctly scoped.
   - Receipt leak, annotated floor, oracle ratchet: untouched - the diff contains no pipeline,
     gate or constant change. Latency: no hot path touched.
   - Test-count arithmetic corroborates the gate evidence: 9 `@Test` in CorpusABTests + 6 in
     PaddleOCRTests = the claimed 15/15; PaddleOCRTests keeps its HEAD count (1:1 replacement), so
     no doc/CI count elsewhere goes stale.

5. **Tests that would fail - MET.** The named mutation (the `pump-328` declaration removed) is red
   in `/tmp/agentlogs/pu80-mutation.log` (2026-09-23 21:50): *"every image is either swept by the
   LLM arm or a declared post-sweep addition"* fails at CorpusABTests.swift:93 naming
   `pump/pump-328-wayne-neste-4736-2381l-board-rain-tilted-ee.jpg has no LLM record`, with the
   other 8 tests of the suite green in the same run - the failure is specific, not collateral.
   Restored: the declaration is present at PostSweepCorpusAdditions.swift:543. The replacement
   `armARecordsNameImages` had no separate mutation; it is structurally discriminating (the
   `#expect(images.contains(recorded))` at PaddleOCRTests.swift:40 fails for any record whose
   image is renamed or deleted) and is the exact shape of the LLM twin's backward check
   (CorpusABTests.swift:97-99) inside the suite the mutation log proves bites. The brief's
   row-specific instruction asked for the LLM arm's mutation log only; it is there. Recorded as a
   minor note, not a gap.

6. **Docs reconciled - MET.**
   - `docs/EXTRACTION.md:1278-1282`: the "Retired" paragraph sits inside the P4.13 section
     (heading "## P4.13 measured: PaddleOCR as a third arm" at :1195), carries the owner quote
     verbatim, states the new test behaviour accurately (matches PaddleOCRTests.swift:31-43) and
     points to the intake skill step 5. The earlier sentence "scored offline by `PaddleOCRTests`"
     (:1201) remains true. No numbered decision (9/10/11 - corpus split, locator, price optionality)
     established PaddleOCR, so none needed amending; a grep of docs/ finds no stale reference to
     the removed forward check anywhere.
   - `docs/TASKS.md`: row ticked at index (:168) and full row (:1067) with a Done summary whose
     every number I verified (57 = receipts 088-097 + pump 282-328; 15/15; the mutation log path).
     `scripts/tasks-index.py --check` exits 0.
   - `.claude/skills/corpus-intake/SKILL.md:112-116`: the rule lands in step 5, names the file, the
     dated-comment convention, the frozen-sweep reason and the PaddleOCR retirement - exactly what
     the Checks cell asked ("the rule for the next intake written into .claude/skills/corpus-intake").
   - `docs/ERRORS.md` / `docs/JOURNEYS.md`: N/A, nothing user-visible changes.
   - CLAUDE.md comment rules in both touched code files: present tense, no task ids, no completion
     evidence, no agent activity; the dated intake comments follow the file-wide convention present
     at HEAD and now mandated by the skill; the new doc comment links the authority
     (`docs/EXTRACTION.md -> "P4.13 measured"`, the literal heading) instead of restating history;
     the MARK header was renamed to describe the new behaviour ("The frozen sweep still names real
     images"). No stale claim survives in either file.

7. **Everything the row promised - every Checks-cell sentence MET.**
   - *"PaddleOCR's coverage check retired with the arm"* - MET: the forward loop is gone
     (PaddleOCRTests.swift:31-43); `armACoversEveryImage` has zero references outside the gitignored
     snapshot; PaddleOCRTests no longer mentions `PostSweepCorpusAdditions` at all.
   - *"(its P4.13 scoring and sweep files kept as the record)"* - MET: `armAScores`, the variance
     and latency tests unchanged; all 13 `paddleocr-a-*` files on disk and unmodified; the dump
     generator (`PaddleOCRDumpTests`) kept and inert (gated on raw-file existence, :31-33).
   - *"the LLM arm's coverage either re-swept or the new images declared"* - MET, declared: exactly
     57 new entries (10 receipts + 47 pump; no duplicates - the sets fold none), and the HEAD
     neither-swept-nor-declared set recomputes to EXACTLY those 57 (my mirror on
     `git show HEAD:` of the declaration file), which also confirms the Problem cell's "57 images
     are neither". Batch arithmetic checks out: batch 8 (`98657867`) pump-282..302 + receipts
     088/089 = 23, batch 9 (`12dea25d`) receipts 090..097 + pump-303..318 = 24, batch 10
     (`c86755d6`) pump-319..328 = 10; all images committed before this diff.
   - *"the rule for the next intake written into .claude/skills/corpus-intake"* - MET (SKILL.md:112-116).
   - *"swift test no longer red for this"* - MET per the gate evidence (15/15), independently
     corroborated by the recomputation above: every pin holds and coverage is total in both
     directions, so both formerly-red tests are green by arithmetic on the committed fixtures.

## Row-specific checks (the brief's three)

- **Every one of the 57 declared images really is absent from `vision-ab/llm-<class>.json`** -
  verified: declared-AND-swept = [] for all 10 receipts in `llm-receipts.json` (35 records) and all
  47 pump images in `llm-pump.json` (17 records). All 57 exist on disk in their class folder
  (no dead declarations). A declared image that WAS swept would have been named; none is.
- **Nothing still depends on the removed PaddleOCR forward check** - verified by repo-wide grep:
  the only hits for `armACoversEveryImage` / the old test name are the gitignored
  `ml/pump-reader/.out/review-why/tree` snapshot; no script, doc or CI file references it.
- **The LLM arm's coverage test still bites** - verified from the mutation log (item 5): red at
  CorpusABTests.swift:93, naming pump-328, restored green.

## Findings I did not fix (nothing blocking)

1. **A one-sentence comment drift in an UNTOUCHED file, owned by PU.80**: `CorpusScorer.sweptImages`'
   doc comment (CorpusABScorer.swift:356-358) says *"What the callers add on top is the other
   direction - every live image must be either swept or listed as a known post-sweep addition"*.
   After this row only the LLM caller (CorpusABTests) adds that direction; the PaddleOCR caller now
   relies on the pinned totals alone. The file is not in the touched set, so item 6 does not fail on
   it, but PU.80's change made the sentence stale - fix it in the same commit or file it as a
   one-line follow-up. Seam: `CorpusScorer.sweptImages`' contract paragraph.
2. **The working tree carries unrelated uncommitted fixture changes** (`corpus.sqlite`,
   `pump/windows.json` - rain-still window annotations, `pump-live/corrections.jsonl`) from the
   concurrent annotation workstream. They are outside this review's diff and unread by either suite,
   but the PU.80 commit must stage ONLY the brief's five paths.

## Verdict

**COMPLETE** - every item MET (items 2 and 3 N/A per the run instructions). The orchestrator may
commit, staging only the five reviewed paths, and should carry finding 1 (one comment sentence in
CorpusABScorer.swift:356-358) into that commit or a filed follow-up.
