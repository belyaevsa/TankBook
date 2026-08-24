# Validation run – P2.3

You are a **validator**, not a builder. Someone else wrote the code. Your job is to run the
project's gates against it and report **raw evidence**, not a summary of how it went.

Repo / worktree: `/Users/sbelyaev/repos/fuel-counter-ios-p2.3`. Work only inside it. **Change no source file.** If a gate
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

## Concurrency rules for this run - read before any command

Other agents and builds are running **right now** in other checkouts.

- **Use device `iPhone 17 Pro Max` and no other.** Pass
  `-destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'` to every xcodebuild command.
  Another validator owns a different device.
- **NEVER `pgrep -f` or `pkill -f` for a build or test.** An agent's brief is part of its
  command line, so `pgrep -f "xcodebuild.*test"` matches **other agents** and killing that
  match destroys a sibling task mid-run. It happened on 2026-08-24 and cost 48 minutes of
  work. If you must check for a running build, use `pgrep -x xcodebuild`.
- **Do not run `scripts/capture-screenshots.sh`.** It picks the newest DerivedData directory,
  which with concurrent worktrees may be someone else's app. Screenshots are not your job.
- Work only inside `/Users/sbelyaev/repos/fuel-counter-ios-p2.3`.

## Task-specific checks for P2.3

Baseline: swift test 401, UI tests 68. Claimed: 425 and 76.

1. **Hard rule 15 - the empty case.** An all-nil extraction must render the ORDINARY empty
   form: no error text, no warning styling, still savable once typed. Find that test and
   confirm it asserts the ABSENCE of error styling, not merely that something rendered.
2. **nil renders blank, never `0`.** Confirm asserted by value.
3. **Dimmed is not disabled.** Confirm a test focuses a dimmed field, types, asserts the value
   changed, and asserts no accessibility trait marks it disabled/read-only. Reading back a flag
   the test itself set does not count.
4. **Money precision.** The task converts `Double`→`Decimal` at the boundary. Confirm
   `Decimal(double:)` appears NOWHERE, that the path is `String(format:)`→`Decimal(string:)`,
   and that `4201.68` is asserted exactly.
5. **The swap case.** Confirm a test proves a swapped litres/price pair still reports the
   cross-check as verified AND that the lock does not gate saving - the lock proves consistency,
   never correct assignment (`a x b == b x a`).
6. **Mutation check (required):** break the dimming threshold (invert its comparison), re-run
   the P2.3 tests, confirm a test FAILS, restore byte-for-byte, re-run green.
7. Confirm no new swiftlint warnings against the 268 baseline, and report the localization gate
   exit code and key count.
