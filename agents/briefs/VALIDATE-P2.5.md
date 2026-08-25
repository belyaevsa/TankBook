# Validation run – P2.5 (foreign currency)

You are a **validator**, not a builder. Someone else wrote the code. Your job is to run the
project's gates against it and report **raw evidence**, not a summary of how it went.

Repo / worktree: `/Users/sbelyaev/repos/fuel-counter-ios-p2.5`. Work only inside it. **Change no source file.** If a gate
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
Another agent runs in another checkout. Use device **`iPhone 17 Pro Max`** and no other.
**NEVER `pgrep -f` / `pkill -f`** for a build or test - an agent's brief is in its command line,
so that pattern matches siblings and killing the match destroys their work. Use
`pgrep -x xcodebuild`. Do not run `scripts/capture-screenshots.sh`.

## Task-specific checks for P2.5

Baseline: swift test 437, UI 76. Claimed: UI 82, swiftlint 267 (one BELOW the 268 baseline),
gate 262 keys.

This task implements **hard rule 3**: money is a pair, `rateDate` is the ENTRY's date and never
"today", snapshots are immutable, backfill fills blanks only. Check the invariants, not the prose.

1. **`rateDate` is the entry's date.** Find the test. **If it dates the entry TODAY, it is
   vacuous** - the bug it guards against cannot show. Confirm it uses a PAST date and asserts the
   rate looked up is that date's.
2. **Pending-rate save**: assert `homeAmount` is **nil**, not zero, and that the entry still
   saves and is complete. A zero home amount is a wrong fact; nil is an honest absence.
3. **Snapshots are immutable**: a second backfill carrying a DIFFERENT rate must leave an
   existing snapshot untouched. Confirm the test actually varies the rate.
4. **No money-valued `Double`.** The agent claims the seed pack stores rates as JSON strings
   decoded via `Decimal(string:)`. Grep for `Decimal(double:)` and for `Double` on any
   money/rate-typed property. Confirm `4.3287` / `289.50` -> `66.88` is asserted exactly.
5. **Offline**: a foreign fill-up saves with no network and no cache (hard rule 1). Confirm the
   fetcher is injected and that no test performs real I/O.
6. **Mutation check (required):** change the rate lookup to use `Date()` instead of the entry's
   `rateDate`, re-run, and confirm the rule-3 test FAILS. Restore byte-for-byte, re-run green.
   If it still passes, the test is vacuous and that is the finding.
7. Report the swiftlint warning count and which warning was removed, if you can tell.
