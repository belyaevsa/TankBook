# PJ.7g – a RELEASE build seeds vehicles and plants a Keychain session

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`:

- the seed harness under `ios/App/Sources/` (`*TestSeed.swift`, `SeededLaunchTransport.swift`,
  `WelcomeGate.swift`, and the call sites that invoke them)
- `ios/App/Tests/` (the app-target bundle PR.16 created) and `ios/App/UITests/`
- `docs/SECURITY.md` – the authority for this row
- `project.yml` if a build setting is needed (run `xcodegen generate` after)

Do **NOT** touch `backend/` – a sibling lane (PJ.20a) owns it. Do **NOT** touch `docs/TASKS.md`.

Write code first, explore second.

## Use this simulator

`iPhone 17`. **Never** `pgrep -f`/`pkill -f` for a build - a brief is part of the process command
line and that pattern once killed a sibling agent 48 minutes in. Use `pgrep -x xcodebuild`.

## The defect

The UI-test seed harness is **not `#if DEBUG`-gated**. In a RELEASE build, a launch argument still:

- seeds vehicles and fill-ups (`HomeTestSeed`, `ManualFillUpTestSeed`, `RecentlyDeletedTestSeed`,
  `TankLevelView`'s seed, `CarSwitcherTestSeed`, `EditEntryTestSeed`, `ReminderTestSeed`, …), and
- **plants a Keychain auth session** (`SettingsTestSeed.stubSession()`, and since PJ.7e also
  `WelcomeGate`), and
- swaps the network transport (`SeededLaunchTransport`) and the config (`AppConfigTestSeed`).

Hard rule 11 and `docs/SECURITY.md` are the authority: the Keychain is where the session lives, and
nothing outside the real sign-in flow should write one. **Pre-existing** - PJ.7e did not introduce
it, it only added one more writer.

Some files already carry `#if DEBUG` (`AppConfigTestSeed`, `SignInFlow`, `FeedbackService` …), so
the pattern exists in the codebase - this row makes it uniform. **Enumerate the harness yourself**;
the list above is a starting point and this project's briefs have carried wrong file lists six
times. Report what you actually found.

## What to build

1. Gate the **whole** seed harness behind `#if DEBUG` - seeds, the stub session, the seeded
   transport, the config seed, and every launch-argument branch that reaches them.
2. **Prove a RELEASE build ignores every seed flag.** This is the deliverable, and a test that only
   proves the DEBUG behaviour proves nothing. Ways that would count: a release-configuration build
   that fails to compile if a seed symbol is referenced outside `#if DEBUG`; a source-scanning
   guard that fails when a seed entry point is reachable without the guard; or an
   `xcodebuild -configuration Release build` in the check list plus a test asserting the flags are
   inert. Choose one, say why, and make it **fail** when the gate is removed.
3. Keep every existing UI test working - they depend on these seeds in DEBUG, and `swift test` /
   `xcodebuild test` build DEBUG, so a correct fix changes nothing about them.

## Named vacuous traps

- **A test that runs in DEBUG and asserts seeding works.** That is the current behaviour and proves
  nothing about RELEASE. The guarantee is about the configuration your tests do NOT run in.
- Gating the seed *call sites* while leaving the seed types and `stubSession()` compiled in and
  reachable. Ask what a RELEASE binary still **contains**, not only what it calls.
- Missing `WelcomeGate`'s session write, which is the newest and least obvious writer.
- Asserting `#if DEBUG` appears in a file by grepping for the string - a guard in the wrong place
  passes that.

## Checks

- `swift build --package-path ios` exit 0; `swiftlint lint` exit **0 from the repo root**.
  **`swift build` does not compile `ios/App`** - also `xcodebuild ... build` → `BUILD SUCCEEDED`,
  and additionally **`xcodebuild ... -configuration Release build`**, which is the configuration
  this row is about. Report both.
- `swift test --package-path ios` – whole suite, never subsetted; it stood at **1120**.
- `xcodebuild ... -only-testing:TankbookUITests/SettingsUITests
  -only-testing:TankbookUITests/HomeUITests -only-testing:TankbookUITests/RecentlyDeletedUITests
  -only-testing:TankbookUITests/ConfirmManualUITests test` on `iPhone 17` – whole suites, since they
  are the heaviest seed consumers. Then `scripts/check-ui-test-count.sh` on the log.
  Note `AddVehicleUITests` is known order-dependent; if you run it and it fails, say whether it
  fails the same way without your change.
- **Mutation**: remove the gate from one seed (e.g. `SettingsTestSeed.stubSession`) and confirm your
  RELEASE guarantee **fails**; restore by copying a backup back and verifying `md5` – **never**
  `git checkout`.

## Report back

The real inventory of the harness and where my list was wrong; how you proved the RELEASE
guarantee and why that shape; observed counts and exit codes for every command including the
Release build; the mutation result; the `md5` match. Say whether you **ran** the tests or only
wrote them. Do not commit.
