# Validation run – main after merging P2.2 + P2.6

You are a **validator**, not a builder. Someone else wrote the code. Your job is to run the
project's gates against it and report **raw evidence**, not a summary of how it went.

Repo / worktree: `/Users/sbelyaev/repos/fuel-counter-ios`. Work only inside it. **Change no source file.** If a gate
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

## Task-specific checks

This is a **post-merge integration check** on `main` after merging two branches that were
developed in parallel worktrees. Neither branch's validator ran the app build or the UI suite.

Baseline on main before the merges: swift test 356, UI tests 68.

1. **Gate 5 is REQUIRED here** even though the merged work touched only `ios/Sources/`: the app
   target depends on `TankbookCore`, and both branches changed it (a new `Fiscal/` module, a new
   `Extraction/` module, `LogEvents.swift` edited by BOTH branches, and `FuelKind` gained two
   enum cases). Run `xcodegen generate`, then the simulator `build`, then `test`. Report the
   `** TEST SUCCEEDED **` / `** TEST FAILED **` line and the passed/failed counts.
2. **`LogEvents.swift` was edited on both branches.** Confirm the merged file compiles and that
   both branches' events survive: `FiscalQRParse` (P2.6) and whatever P2.2 added. A silent
   merge that dropped one side's events would still compile.
3. **`FuelKind` gained `petrol92`/`petrol100`.** Confirm nothing switching over `FuelKind`
   became non-exhaustive, and that the 11 payload schemas on `main` still match
   `scripts/generate-payload-schemas.swift` output exactly (re-run it, `git diff` must be empty).
4. Run the accuracy ratchet test and report the per-class numbers it prints on `main`.

Do not fix anything. Report findings.
