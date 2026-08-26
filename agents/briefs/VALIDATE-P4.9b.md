# Validation run – P4.9b

You are a **validator**, not a builder. Someone else wrote the code. Your job is to run the
project's gates against it and report **raw evidence**, not a summary of how it went.

Repo / worktree: `/Users/sbelyaev/repos/fuel-counter-ios-p4.9b`. Work only inside it. **Change no source file.** If a gate
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

## Task-specific context for P4.9b

The task built the **Settings screen** (replacing a near-empty `SettingsContent()` placeholder)
plus the **sync surface** specified in `docs/SYNC.md` -> "The Settings sync surface".

Counts claimed by the builder, to confirm or refute: `swift test` **593 -> 597**,
`xcodebuild test` **115 -> 123**, `swiftlint` 0, localization gate 0 at 441 keys / 100% RU.

**Mutation-check these two specifically** - they are the invariants the task exists for, and each
is the kind a green suite hides:

1. **The flagged-entry count is DERIVED, never stored.** `Repository+FlaggedEntries.swift`
   recomputes it from records carrying a `ConflictState`. Break it (return a constant, or read a
   cached value) and confirm `SyncCoordinatorTests` goes red.
2. **"Sync now" is idempotent, asserted on the TRANSPORT'S PUSH COUNT, not the button's
   `isEnabled`.** Neuter the in-flight guard in `AppSync.swift` / the sync coordinator and confirm
   the test fails with a push/pull count of 2 rather than 1. A disabled button that still queues a
   push would pass a UI-state assertion and violate the rule.

Restore each file **byte-for-byte** afterwards and re-run to confirm green.

**Also confirm, by reading the diff, that the previously-failing
`testSettingsChainHasBackPaths` was NOT made to pass by cheating**: no `sleep`, no `XCTSkip`, no
deleted test, no loosened assertion. The builder says it fixed it by updating identifiers onto the
new screen and adding `.contentShape(Rectangle())` to the rows (a real hit-area defect). Verify
that claim against the diff and say plainly whether it holds.

**Do not open or judge the screenshots** - you have no image input. The orchestrator opens all
twelve personally. Just confirm the twelve files exist and report their sizes.
