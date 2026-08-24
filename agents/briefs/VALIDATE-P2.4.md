# Validation run – P2.4 (mixed receipts)

You are a **validator**, not a builder. Someone else wrote the code. Your job is to run the
project's gates against it and report **raw evidence**, not a summary of how it went.

Repo / worktree: `/Users/sbelyaev/repos/fuel-counter-ios-p2.4`. Work only inside it. **Change no source file.** If a gate
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

## Concurrency rules

Another agent is running in a different checkout **right now**.
- Use device **`iPhone 17 Pro Max`** and no other.
- **NEVER `pgrep -f` / `pkill -f`** for a build or test - an agent's brief is in its command
  line, so that pattern matches sibling agents and killing the match destroys their work. It
  happened on 2026-08-24. Use `pgrep -x xcodebuild`.
- Do not run `scripts/capture-screenshots.sh`. Screenshots are not your job.
- Work only inside this worktree.

## Task-specific checks for P2.4

Baseline: swift test 425, UI 76.

The agent reports it **deliberately did not tick** the `>=95%` L5 gate, because the corpus holds
exactly one mixed receipt and a percentage over one fixture is arithmetic. **Verify that
restraint is real**, not a cover for weak tests:

1. **Fuel-line isolation**: `receipt-009` yields 6135.24, NOT the 6264.00 grand total (hard rule
   4). Confirm asserted by value.
2. **The 129.00 collision**: the bottled water's total equals the fuel's price per litre.
   Confirm a test constructs this explicitly and that the detector does not confuse them.
3. **False-positive guard**: confirm at least three NON-mixed corpus fixtures are asserted as not
   mixed. A detector tested only on the positive case is untested - this is the check that
   protects the common path.
4. **No-QR detection**: 13 of 22 corpus receipts have no QR. Confirm a mixed receipt is detected
   by line structure alone, with the QR signal unavailable.
5. **Group invariants**: `FillUp` + accepted `Expense`s share one `purchaseGroupId`, and the sum
   is **<=** the grand total (not ==, since a user may dismiss a line). The agent claims a
   property test over seven compositions - confirm it varies the input rather than repeating one.
6. **A dismissed line creates nothing** - assert no `Expense` row exists.
7. **Mutation check (required):** break the mixed-detection threshold so a mixed receipt is
   classified as ordinary; re-run; confirm a test FAILS. Restore byte-for-byte, re-run green.
8. Confirm `docs/TASKS.md` records the L5 gate as pending rather than ticked, and that no
   `expected.csv` row was edited (`git diff` them).
