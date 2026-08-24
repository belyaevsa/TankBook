# Validation run – P2.2 (parser port + ratchet)

You are a **validator**, not a builder. Someone else wrote the code. Your job is to run the
project's gates against it and report **raw evidence**, not a summary of how it went.

Repo / worktree: `/Users/sbelyaev/repos/fuel-counter-ios-p2.2`. Work only inside it. **Change no source file.** If a gate
fails, report the failure - do not fix it, do not tick anything, do not commit.

Model: deepseek-v4-pro. Standing rule (2026-08-24): validation runs on pro.

## What to run, in this order, and what to capture

Run each command and capture its **exit code** with `echo $?` immediately after, plus the last
~20 lines of output. The exit code is the verdict; prose is not.

1. `cd ios && swift build`
2. `cd ios && swift test` - capture the final "Test run with N tests" line
3. **`swiftlint lint` from the REPO ROOT** - not from `ios/`. The `excluded:` paths are
   root-relative, so running it from `ios/` reports thousands of phantom errors. Zero **errors**
   is the standard; ~268 pre-existing **warnings** do not block.
4. `swift run --package-path ios localization-gate --sources ios/App/Sources --catalogue ios/App/Sources/Localizable.xcstrings`
5. If the task touched `ios/App/`: `xcodegen generate` then
   `xcodebuild -project Tankbook.xcodeproj -scheme Tankbook -destination 'platform=iOS Simulator,name=iPhone 17' build`
   then the same with `test`. Capture the `** TEST SUCCEEDED **` / `** TEST FAILED **` line and
   the passed/failed counts.
6. If the task touched the parser or fixtures: `cd Spike/ReceiptSpike && swift run ReceiptSpike fixtures/receipts`
   and the same for `fixtures/pump`, and report the accuracy lines verbatim.

## What to check beyond the gates

- **Do the counts actually rise?** Report the before/after test counts. A task that adds code
  and no tests is a finding.
- **Are any new tests vacuous?** Read them. `#expect(true)`, asserting only that a call did not
  throw, asserting a view exists without asserting its text, or a "tamper" test that mutates a
  field the code never reads - all count as not having done the work. **Quote any you find.**
- **Mutation-check the load-bearing logic.** Pick the single most important invariant the task
  claims, break it deliberately in a scratch copy of the file, re-run the relevant test, and
  confirm the test **fails**. Then restore the file exactly. A suite that passes when the code
  is wrong is not evidence. Report what you broke and whether the test caught it.
- **Did anything get written outside the repo?** Report it.

## What you must NOT do

- **Do not fix anything.** A validator that edits code cannot validate it.
- Do not tick `docs/TASKS.md`.
- Do not commit, stage, or stash.
- Do not judge screenshots. **You have no image input** - you cannot see them, and guessing is
  worse than abstaining. Say "not checked - no image input" and move on.

## Report back

For each gate: the command, the **exit code**, and the key output line. Then the test counts
before/after, any vacuous assertions quoted, the mutation-check result, and a final verdict of
**PASS** or **FAIL with the specific failing gate**.

Report exit codes you actually observed. If you did not run a command, say so - do not infer
its result.

## Task-specific checks for P2.2

Baseline before this task: `swift test` **349**; receipts **18/47 (38.3%)**, pump **0/12**,
fiscal **0/3**, screenshots **3/3 (100%)**. The agent claims 368 tests and receipts
**29/47 (61.7%)**.

**The claim that matters most is a REGRESSION, and it is the reason you are here.** The agent
reports `screenshots` dropping from **3/3 (100%) to 1/3 (33.3%)**, arguing it is correct: the
old code guessed a commutative product for the unmarked `25,52 X 70.92`, and the new ladder
returns nil instead. Establish, with evidence:

1. **Re-measure every class yourself** with `swift run ReceiptSpike fixtures/<class>` for
   receipts, pump, fiscal and screenshots. Report the four accuracy lines verbatim. Do not
   trust the reported numbers.
2. **Was the old screenshots result correct or lucky?** `screenshot-001` is the same purchase
   as `fiscal-001` - ground truth 25.52 L at 70.92. Determine whether the previous 3/3 came
   from actually resolving the assignment or from `bestTriple` picking a product that happens
   to be commutative. Quote the old and new code paths.
3. **Check the ratchet is not seeded to hide the drop.** Find the high-water file. If
   `screenshots` is recorded at the NEW lower number, that locks in a regression and the
   ratchet can never fire on it again. Report exactly what value is recorded per class and
   whether it is above, at, or below what the code currently scores.
4. **Prove the ratchet fires.** Lower a measured score artificially (or raise a high-water
   value) in a scratch copy, run the ratchet, confirm it FAILS, restore byte-for-byte, re-run
   green. A ratchet nobody has seen fail is not known to work.
5. **Did the corpus shrink?** Count files per class and compare to `expected.csv` rows. A class
   average that rose because fixtures were dropped is a finding. No `expected.csv` row may have
   been edited - `git diff` them and report any change.
6. **The FuelKind schema change**: `petrol92`/`petrol100` were added and 11 payload schemas
   regenerated. Confirm the schemas were produced by `scripts/generate-payload-schemas.swift`
   and match its output exactly (re-run it and `git diff` - there must be no delta), not
   hand-edited.
7. **`scratch/` must be gone** and `.swiftlint.yml` must be unmodified (`git diff` it).
