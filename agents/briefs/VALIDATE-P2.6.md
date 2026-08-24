# Validation run – P2.6 (fiscal QR anchor)

You are a **validator**, not a builder. Someone else wrote the code. Your job is to run the
project's gates against it and report **raw evidence**, not a summary of how it went.

Repo / worktree: `/Users/sbelyaev/repos/fuel-counter-ios-p2.6`. Work only inside it. **Change no source file.** If a gate
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

## Task-specific checks for P2.6

Baseline before this task: `swift test` was **349**. The agent claims **372**.

1. Confirm all **11** committed QR fixtures are actually read from disk by the tests, not
   pasted as literals. Grep the test file for the payload strings; if they appear inline
   rather than being loaded from `*.qr.txt`, that is a finding.
2. `receipt-009` is the mixed-receipt case: QR `s=6264.00`, `expected.csv` total `6135.24`.
   Confirm the suite classifies it `suggestsMixedReceipt` and **not** `disagrees`, and that
   exactly one fixture lands in that bucket.
3. Confirm `liters`, `unitPrice` and `fuelKind` on the anchor are asserted **nil**, not zero.
4. Confirm money is `Decimal` end to end - grep for `Double` in the Fiscal sources; any
   money-valued `Double` is a finding.
5. **Mutation check (required):** in a scratch copy, change the cross-check's tolerance so a
   1 ₽ difference no longer counts as agreement, re-run the fiscal tests, and confirm a test
   FAILS. Restore the file byte-for-byte afterwards and re-run to confirm green.
6. Confirm hard rule 12: grep the Fiscal sources and LogEvents for anything that could log a
   total, timestamp, `fn`, `i` or `fp`. Field names and outcome codes are fine; values are not.
