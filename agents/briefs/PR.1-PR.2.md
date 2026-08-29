# Task PR.1 + PR.2 - the client half of the auth lifecycle

Repo: **`/Users/sbelyaev/repos/fuel-counter-ios`**, branch `main`. Work in this checkout.

**Tier 1, order 5** (`docs/TASKS.md`). **Every signed-in install stops syncing about 60 minutes
after sign-in and is told to update the app** - a next step that cannot possibly fix it, which is a
hard rule 7 violation on top of a dead sync. **PJ.13** (first push after sign-in) is the third row
in this Tier-1 entry and is **out of scope here**: it touches the same `SignInFlow` file and would
collide. It follows this one.

## Where you may write

```
ios/Sources/TankbookCore/Auth/**
ios/Sources/TankbookCore/Config/TankbookHTTPClient.swift
ios/Sources/TankbookCore/Sync/RemoteSyncTransport.swift
ios/App/Sources/SignIn/**
ios/App/Sources/Settings/**
ios/Tests/TankbookCoreTests/**
ios/App/UITests/SettingsUITests.swift
docs/API.md · docs/SECURITY.md · docs/ERRORS.md
```

**Do not** touch `ios/App/Sources/Capture/**`, `ios/App/Sources/ConfirmManual/**` or
`ios/Sources/TankbookCore/Extraction/**` - another agent holds the capture lane. Nor `backend/`,
`site/`, `deploy/`, `.github/`, `Spike/`, `design/`, `project.yml`.
**Do not commit. Do not tick `docs/TASKS.md`.**

## The defect, verified end to end by the orchestrator

```
backend/src/Tankbook.Api/Auth/AuthOptions.cs:25   AccessTokenLifetimeMinutes = 60
ios/Sources/TankbookCore/Auth/AuthService.swift:88   public func refresh(_:) -> AuthSession
ios/Sources/TankbookCore/Auth/AuthService.swift:98   public func signOut(_:) async throws
```

Both are **fully implemented and have ZERO production callers** - the only references are in
`ios/App/Sources/SignIn/SignInTestSeed.swift`. There is **no 401 interception anywhere**, and there
are **nine** `TankbookHTTPClient` construction sites (`docs/PRACTICES.md` says four - it is wrong,
which makes the race worse, not better).

So an hour after sign-in the access token expires and:

```
RemoteSyncTransport.swift:68   case 400...499:  throw SyncServerError.refused(status:)   // 401 lands HERE
  -> SyncServerNotice.refused -> L10n.syncNoticeRefused
  -> "Tankbook needs an update – the server has moved ahead"   (amber, isAttention == true)
```

The user is told to update an app that is already current, while their log silently stops syncing.

**PR.2**: `DELETE /v1/auth/session` **exists** on the server (`Program.cs:381`,
`AuthEndpoints.SignOut`) and is never called. Both client sign-out paths -
`SignInFlow.signOutLocally()` (`SignInFlow.swift:175`) and `AccountDevicesModel.swift:109` - only
`try? sessionStore.clear()`, leaving a **90-day refresh chain valid server-side** on a phone that
has been handed on or sold.

## What to build

### PR.1 - refresh, once, shared

1. **One shared `SessionRefresher` actor** behind every `TankbookHTTPClient` owner. On a 401:
   refresh **once**, persist the rotated pair, replay the original request.
2. **Concurrent 401s must await the one in-flight refresh**, never start a second. The server
   rotates refresh tokens and **revokes the chain on reuse** (that behaviour is already built and
   tested server-side), so two racing refreshes sign the user out - the "randomly signed out"
   bug nobody can reproduce. With nine client owners this is not hypothetical.
3. **On refresh failure**: surface `authExpired` and a Settings card saying **"Sign in again"** -
   never "update the app". Add the string to the catalogue in **EN and RU**.
4. **Remove `.refused(status: 401)` as a reachable outcome** from the sync, gateway, account and
   blob transports: a 401 is an auth event, not an unknown gate from a newer server.

### PR.2 - sign-out revokes

Every sign-out path calls `DELETE /auth/session` **best-effort** with the stored bearer, then
clears the Keychain **even when the call fails** (offline sign-out must still sign out locally -
hard rule 1). Wire both existing paths.

## Russian copy - read this before writing the string

`docs/LOCALIZATION.md` is the authority. Two rules that have each shipped a bug here:

- **If a `%@` receives runtime data, the surrounding phrase must not govern its case.**
  `from your %1$@, %2$@` became «с вашего телефон Android» - the genitive cannot be applied to a
  server-supplied device name.
- **Never compose a sentence by concatenation**; write a full localised phrase per language.
  `"%@ spend"` composed as «%@ расходы» rendered "АВГУСТ РАСХОДЫ", word-order nonsense.

## Tests

```
cd ios && swift build   ; echo "build: $?"
cd ios && swift test    ; echo "test: $?"     # 923 today (verified). MUST rise.
swiftlint lint          ; echo "lint: $?"     # from the REPO ROOT, must be 0
xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
  -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "app build: $?"
```

- **L1**: a recording transport answering `401` then `200` produces **exactly one**
  `POST /auth/refresh`, the request replayed with the new bearer, and **dirty rows untouched**.
- **L1**: **two concurrent 401s produce ONE refresh.** This is the load-bearing test - write it so
  it genuinely races (two tasks awaiting the same actor), not two sequential calls.
- **L1**: a refresh that itself 401s clears the session and yields `authExpired`.
- **L1**: sign-out issues the DELETE and clears the Keychain on **204 and on transport failure**.
- **L4 `SettingsUITests`**: a seeded expired session shows the **re-sign-in card, not the update
  notice**; EN **and** RU.

Run only `-only-testing:TankbookUITests/SettingsUITests` and **report the observed count** - a
selector matching nothing prints "Executed 0 tests" and reads like success. **Do not run the full UI
suite.** **Never `pgrep -f`** for a build; use `pgrep -x xcodebuild`, never `pkill -f`.

## Mutations you must run and report

1. Let two concurrent 401s each start their own refresh. The concurrency test must fail. **If it
   still passes, your test is sequential and proves nothing** - that is the finding, report it.
2. Replay the request with the **old** bearer. A test must fail.
3. Clear the Keychain **without** calling DELETE. The PR.2 test must fail.
4. Map a 401 back to `.refused(status:)`. The `SettingsUITests` case must fail - if it passes, the
   card is asserted by nothing and the original bug could ship again.

A mutation that does not fail is a finding. One that does not **compile** proves nothing. Use a
**heredoc** for scripted edits.

## Screenshots

EN **and** RU, dark: the Settings sync card in its **authExpired** state. Capture outside a test run
(`simctl` and `xcodebuild test` fight over the device). Name them `PR.1-settings-auth-expired.png`
and `-ru.png`. You cannot see them; the orchestrator opens every one, and reads the Russian for
grammar rather than only for overflow.

## Report back

Every command with its **real exit code** and observed counts; all four mutation results; how you
proved the concurrency test actually races; the files changed; and anything in this brief that is
wrong.

En-dashes only, never em-dashes.
