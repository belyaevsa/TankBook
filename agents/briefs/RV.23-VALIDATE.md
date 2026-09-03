# Validation run – RV.23 (Welcome screen: why an account is worth having)

You are a **validator**, not a builder. The code is already in the tree and shipping. Your job is
to run the gates against it and report **raw evidence**, not a summary of how it went.

Repo: `/Users/sbelyaev/repos/fuel-counter-ios`. Work only inside it. **Change no source file.**
If a gate fails, report the failure - do not fix it, do not tick anything, do not commit.

**Use the `iPhone 17 Pro` simulator for every xcodebuild/xcrun step.** Another agent may be using
`iPhone 17` concurrently and `simctl`/`xcodebuild` fight over a shared device.

## Why this row is open even though the code landed

RV.23 shipped on 2026-09-03: the "No account needed" line is gone, sign-in is a peer door naming
what an account buys, the restore path keeps `arrivedViaRestore` through a `SignInRequest` enum so
J11a's wrong-provider question cannot fire for a genuinely new user, and the concatenated RU string
was replaced by whole phrases.

**What is missing is independent verification.** `WelcomeUITests` and `SignInUITests` were run by
the agent that wrote the change and never re-run since, and that agent's own before/after check was
invalidated when a `git add -A` moved its baseline mid-run. An agent report is not the gate.

## What to run, in this order, capturing exit codes

Run each and capture its **exit code** with `echo $?` immediately after, plus the last ~20 lines.
The exit code is the verdict; prose is not.

1. `cd ios && swift build ; echo "BUILD=$?"`
2. `cd ios && swift test ; echo "TEST=$?"` - capture the final "Test run with N tests" line
3. **`swiftlint lint` from the REPO ROOT** ; `echo "LINT=$?"` - not from `ios/`, whose root-relative
   `excluded:` paths would report thousands of phantom errors. Zero **errors** is the standard;
   pre-existing warnings do not block.
4. `swift run --package-path ios localization-gate --sources ios/App/Sources --catalogue ios/App/Sources/Localizable.xcstrings ; echo "L10N=$?"`
5. `xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build ; echo "APPBUILD=$?"`
6. **The two suites this row turns on**, in one invocation:
   `xcodebuild -project Tankbook.xcodeproj -scheme Tankbook -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:TankbookUITests/WelcomeUITests -only-testing:TankbookUITests/SignInUITests ; echo "UITEST=$?"`
   Capture the `Executed N tests` lines and any `Test Case ... failed` line **verbatim**.
   **Check the counts are non-zero** - a filter that matches nothing prints a green "0 tests passed".

## What to check beyond the gates

- **Read the two suites and say whether they actually test RV.23's claims.** The row's own L4
  requirements were: the benefits and the skip are **both hittable and of comparable prominence**
  (frames, not existence - *"a subordinate skip is the failure this task is most likely to ship"*);
  skip reaches Add car with no session; sign-in reaches `SignInFlowHost`; and the **J11a
  wrong-provider notice still appears at the decision moment**. State, per claim, whether a test
  covers it, and quote the assertion. **A claim with no test is a finding** - report it, do not
  write the test.
- **Are any assertions vacuous?** `.exists` on a button whose prominence is the whole point,
  asserting a label is non-empty, asserting a screen appeared without asserting what it says - all
  count as not having done the work. **Quote any you find.**
- **Mutation-check the one invariant that matters most here**: the `SignInRequest` enum gating
  J11a's wrong-provider question. Break it deliberately in a scratch copy (make the new-user path
  report `arrivedViaRestore`), re-run the relevant test, and confirm it **fails**. Then restore the
  file byte-for-byte and confirm the suite is green again. Report what you broke, whether a test
  caught it, and the md5 before/after the restore.
- **Copy check, EN and RU**: read the Welcome strings in `Localizable.xcstrings`. Hard rule 10 says
  full localised phrases per language, never concatenation. Confirm the RU benefit copy is a whole
  phrase and quote it. Report any string built by joining fragments.
- **Did anything get written outside the repo?** Report it.

## What you must NOT do

- **Do not fix anything.** A validator that edits code cannot validate it.
- Do not tick `docs/TASKS.md`.
- Do not commit, stage or stash.
- **Do not judge screenshots.** You have no image input - you cannot see them and guessing is worse
  than abstaining. Say "not checked - no image input"; the orchestrator opens them personally.

Match the process NAME (`pgrep -x xcodebuild`). **Never `pgrep -f` or `pkill -f`** on a build/test
pattern - an agent's brief is part of its command line, and that pattern killed a sibling agent on
2026-08-24.

## Report back

- Every command, its **captured exit code**, and the counts. Raw, not summarised.
- The per-claim coverage table (claim → test → quoted assertion → covered / NOT covered).
- Any vacuous assertion, quoted.
- The mutation result: what you broke, whether a test caught it, restore confirmed.
- The RU copy, quoted, and whether any string is concatenated.
- **Your verdict: does RV.23 deserve to be ticked, and if not, exactly what is missing.**
