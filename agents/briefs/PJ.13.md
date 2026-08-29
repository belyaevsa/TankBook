# Task PJ.13 - the first push after sign-in

Repo: **`/Users/sbelyaev/repos/fuel-counter-ios`**, branch `main`. Work in this checkout.

**Tier 1, order 5** - the last piece of that entry; PR.1 and PR.2 landed in `682f3d4`. Today
**signing in pushes nothing**, so the user's whole local log stays on one device until some later
opportunistic cycle. `docs/TASKS.md`: "the second device restores an empty account, which then
presents as the wrong-provider trap" - the user is asked whether they signed in with the wrong
provider when in fact the first device simply never pushed.

## Where you may write

```
ios/App/Sources/SignIn/**
ios/App/Sources/Settings/**
ios/App/Sources/Localization/L10n.swift
ios/App/Sources/Localizable.xcstrings
ios/Sources/TankbookCore/Sync/**
ios/Tests/TankbookCoreTests/**
ios/App/UITests/SignInUITests.swift
ios/App/UITests/SettingsUITests.swift
docs/JOURNEYS.md · docs/LOCALIZATION.md
```

**Do not** touch `ios/App/Sources/Capture/**`, `ios/App/Sources/ConfirmManual/**`,
`ios/Sources/TankbookCore/Extraction/**`, `ios/Sources/TankbookCore/Config/**`, `backend/`,
`site/`, `deploy/`, `.github/`, `Spike/`, `design/`, `project.yml`.
**Do not commit. Do not tick `docs/TASKS.md`** - a concurrent session edits it.

## The defect, verified immediately before dispatch

```swift
// ios/App/Sources/SignIn/SignInFlow.swift, in signIn(provider:)
// J11a: a local log uploads, never overwritten - it is never pulled over.
if localHasData() {
    onFinished()      // <- says "uploads". Pushes NOTHING.
    return
}
await runRestore(accountId: session.accountId)
```

The comment states the J11a guarantee and the code does not implement it. `acceptEmpty()` is the
same shape - `onFinished()` alone.

```swift
// ios/App/Sources/Settings/SettingsView.swift
.task { ...; await sync.refresh() }
.sheet(isPresented: $showsSignIn) { SignInFlowHost() }   // <- no onDismiss
```

**A `.sheet` does not re-trigger the presenter's `.task` on iOS 26.** That is not a guess - it is
the documented cause of P6.18b, where `ManualFillUpView.save()` left Home showing stale data, and
it was found by a UI test and by nothing else. So after signing in, the Settings card can still be
showing its signed-out state.

## What to build

1. **A user-initiated sync before `onFinished()`** on the sign-in completion paths - the
   `localHasData()` branch and `acceptEmpty()`. It must be `.userInitiated`, not `.background`:
   `LowPowerPolicy` defers a background cycle whenever Low Power Mode is on, and a first push the
   user just asked for by signing in must never be one of the things that waits.
2. **`wrongProvider` must NOT push.** The user has not accepted this account; pushing their log
   into it is the one irreversible mistake on this screen.
3. **Settings refreshes when the sheet closes** (`onDismiss`), so the card reflects the new state
   without the user leaving and re-entering Settings.
4. **The card gains the device count** ("Synced just now · 1 device") and a one-line confirmation,
   "Your garage now follows your account."

## Russian - the trap this task walks straight into

"N devices" is a **plural**, and Russian has one/few/many. `docs/LOCALIZATION.md` records that the
edges are **11 and 21**: a naive rule gets 1, 2 and 5 right and still renders 11 and 21 wrong.
Use the String Catalog's plural variations, and **assert 1, 2, 5, 11 and 21** - swapping RU `many`
and `few` is invisible at every other number, which is exactly how it shipped once before.

Two more rules from `docs/LOCALIZATION.md`, each of which has shipped a bug:

- **If a `%@`/`%d` receives runtime data, the surrounding phrase must not govern its case.**
  «с вашего %1$@» rendered "с вашего телефон Android".
- **Never compose a sentence by concatenation** - a full localised phrase per language.
  `"%@ spend"` composed as «%@ расходы» rendered "АВГУСТ РАСХОДЫ".

## Explicitly out of scope

APNs registration and push-token upload (**PR.20**) · debounced sync after writes (**PR.20**) ·
the restore flow itself (P4.7, built) · any capture or extraction change · `docs/TASKS.md` ·
committing.

## Tests

```
cd ios && swift build   ; echo "build: $?"
cd ios && swift test    ; echo "test: $?"     # 938 today (verified). MUST rise.
swiftlint lint          ; echo "lint: $?"     # from the REPO ROOT, must be 0
xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
  -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "app build: $?"
```

- **L1**: a stub coordinator sees **exactly one** `.userInitiated` cycle after the local-log
  branch, and **zero** after `wrongProvider`. Both halves, or the guarantee is pinned in one
  direction only.
- **L1**: the device-count plural renders correctly at **1, 2, 5, 11, 21** in EN and RU.
- **L4** `SignInUITests` and `SettingsUITests`: a seeded local log, sign in, and the card reads the
  synced line **without leaving Settings**.

Run only those two suites with `-only-testing:` and **report the observed count for each**
(`SettingsUITests` is 9 today); a selector matching nothing prints "Executed 0 tests" and reads
exactly like success. **Do not run the full UI suite.** **Never `pgrep -f`** for a build - your
brief is part of your command line, and that killed a sibling agent 48 minutes in. Use
`pgrep -x xcodebuild`; never `pkill -f`.

## Mutations you must run and report

1. Change the push from `.userInitiated` to `.background`. A test must fail - if none does, the
   distinction that keeps a first push out of the Low Power queue is unasserted.
2. Fire the sync on the `wrongProvider` path too. The "zero after wrongProvider" test must fail.
3. Remove the `onDismiss` refresh. The `SettingsUITests` case must fail - if it passes, the test is
   asserting the state machine rather than what the user sees, which is the P6.18b failure exactly.
4. Swap the RU `many` and `few` plural forms. The test must fail **at 11 and 21**, and pass at
   1, 2 and 5. Report the numbers you observed.

A mutation that does not fail is a finding - report it, and say **which suites you ran**: it can
also "pass" because the guarantee lives in a tier you did not run. One that does not **compile**
proves nothing and must be redone. Use a **heredoc** for scripted edits.

## Screenshots

EN **and** RU, dark: the Settings account card immediately after sign-in, showing the synced line
and the device count. Capture **outside** a test run - `simctl` and `xcodebuild test` fight over the
device. Name them `PJ.13-settings-signed-in.png` and `-ru.png`. You cannot see them; the
orchestrator opens every one and reads the Russian for grammar, not only for overflow.

## Report back

Every command with its **real exit code** and observed counts; all four mutation results including
the plural numbers; the files changed; and anything in this brief that is wrong - seven agent
pushbacks in this project have been correct, including one on this very file yesterday.

En-dashes only, never em-dashes.
