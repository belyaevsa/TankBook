# Validation run – P2.1b

You are a **validator**, not a builder. Someone else wrote the code. Your job is to run the
project's gates against it and report **raw evidence**, not a summary of how it went.

Repo / worktree: `/Users/sbelyaev/repos/fuel-counter-ios-p2.1b`. Work only inside it. **Change no source file.** If a gate
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

- **Use device `iPhone 17e` and no other.** Pass
  `-destination 'platform=iOS Simulator,name=iPhone 17e'` to every xcodebuild command.
  Another validator owns a different device.
- **NEVER `pgrep -f` or `pkill -f` for a build or test.** An agent's brief is part of its
  command line, so `pgrep -f "xcodebuild.*test"` matches **other agents** and killing that
  match destroys a sibling task mid-run. It happened on 2026-08-24 and cost 48 minutes of
  work. If you must check for a running build, use `pgrep -x xcodebuild`.
- **Do not run `scripts/capture-screenshots.sh`.** It picks the newest DerivedData directory,
  which with concurrent worktrees may be someone else's app. Screenshots are not your job.
- Work only inside `/Users/sbelyaev/repos/fuel-counter-ios-p2.1b`.

## Task-specific checks for P2.1b

Baseline: swift test 401, UI tests 68. The task wires the Capture screen into the app; before
it, `ModalRoute.capture` was set ONLY by a `#if DEBUG` launch hook, so the screen was dead code
in a Release build.

1. **The decisive test.** Find `testCenterButtonReachesCaptureWithoutLaunchArgument`. Confirm
   it launches WITHOUT `-presentScreen`, taps the centre button, and asserts the Capture screen
   is actually on screen. **If it passes a `-presentScreen` argument anywhere, that is a FAIL** -
   it would be testing the bug rather than the fix.
2. **Prove Capture is reachable without DEBUG.** Grep for every assignment to the modal state.
   Confirm at least one is OUTSIDE `#if DEBUG`. Report the file and line.
3. **The `onCapture` rename.** The old callbacks opened the manual form despite the name. Confirm
   nothing named `onCapture`/`capture*` now opens the manual form, and that BOTH doors exist:
   "Type it" reaches ConfirmManual, the centre button reaches Capture (hard rule 15).
4. **The centre button is not a tab**: confirm tapping it does not change tab selection, and
   that dismissing returns to the originating tab.
5. **Mutation check (required):** make the centre button do nothing (drop its action body),
   re-run the UI suite, and confirm `testCenterButtonReachesCaptureWithoutLaunchArgument`
   FAILS. Restore byte-for-byte, re-run green.
6. Confirm `scratch/` and any `Scratch*Tests.swift` are gone, and that the DEBUG
   `-presentScreen capture` hook still works (the screenshot script needs it).
