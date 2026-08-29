# Task PR.6 - transport timeouts, named once per tier

Repo: **`/Users/sbelyaev/repos/fuel-counter-ios`**, branch `main`. Work in this checkout.

**Tier 1, order 7.** Every network call in the app runs on `URLSession.shared` at its **60 second**
default. A half-connected radio - the ordinary mobile case, not an edge - therefore freezes
"Sign in", "Sync now" and "Import" for a full minute with **no error and no cancel**. `docs/PRACTICES.md`
U6 is blunt about it: *timeouts are UX*, and a 60 s default is a 60 s frozen button.

## Where you may write

```
ios/Sources/TankbookCore/Auth/URLSessionTransport.swift
ios/Sources/TankbookCore/Config/**            (TankbookHTTPRequest/Client)
ios/Sources/TankbookCore/Transport/**         (new, if you want a home for the constants)
ios/App/Sources/**                            (the URLSessionTransport construction sites)
ios/Tests/TankbookCoreTests/**
ios/App/UITests/ImportUITests.swift · ios/App/UITests/SignInUITests.swift
backend/src/Tankbook.Api/Program.cs · backend/src/Tankbook.Api/Rates/** · backend/src/Tankbook.Api/Auth/**
backend/tests/Tankbook.Api.Tests/**
docs/API.md · docs/PRACTICES.md · docs/ERRORS.md
```

**Do not** touch `ios/App/Sources/Capture/**`, `ConfirmManual/` beyond its transport construction,
`TankbookCore/Extraction/**`, `TankbookCore/Sync/SyncEngine.swift`, `site/`, `deploy/`, `.github/`,
`Spike/`, `design/`, `project.yml`.
**Do not commit. Do not tick `docs/TASKS.md`.**

## Verified immediately before dispatch

```
$ grep -rn "timeoutInterval\|URLSessionConfiguration" ios/Sources ios/App/Sources   -> NOTHING
$ grep -rn "URLSession.shared" ios/Sources ios/App/Sources
ios/Sources/TankbookCore/Auth/URLSessionTransport.swift:21   URLSession.shared.data(for:)
$ grep -rn "Timeout" backend/src ... (HttpClient)                                   -> NOTHING
```

**One** transport type carries everything, constructed at **eight** sites (`AccountDevicesService`,
`AppConfigService`, `SeededLaunchTransport`, `ManualFillUpCurrencySupport`, `GatewayScanSession`,
`SignInFlow` x2, `ImportService`). Backend: `AddHttpClient("apns", ...)` and a bare
`AddHttpClient()` (`Program.cs:140,193`), neither with a `Timeout`; the ECB/CBR rate feeds and JWKS
ride the 100 s default, so a slow feed pins a job thread and a slow JWKS stalls **every** sign-in
behind it.

## What to build

1. **`TransportTimeouts` - one named definition per tier.** Suggested starting point, and say in
   your report why you kept or changed each: **connect ~8 s**, **read 30 s** for JSON. Blob PUT and
   import multipart legitimately need longer - they carry megabytes over a mobile uplink - so give
   them their own named value rather than one number pretending to fit everything.
2. **The app builds its own `URLSession`** from that configuration. `URLSession.shared` must not
   appear in production code, and a **grep gate** must enforce it (follow the source-scan pattern in
   `ConfigTransportDirectorTests.appSourcesNeverHardcodeTheBundledBaseURL`, and **say plainly what a
   text scan cannot see**).
3. **A per-request override on `TankbookHTTPRequest`**, so the long paths ask for their budget
   explicitly rather than every call inheriting the longest one.
4. **Named backend timeouts** for the rate feeds, JWKS and APNs.
5. **Cancel on the Import and Restore progress surfaces** (`RestoringView.swift` exists; the import
   parse has no cancel). A wait the user cannot escape is the thing this row exists to remove -
   hard rule 7, the next step must exist.

**A timeout must never be remote-configurable.** `docs/PRACTICES.md` §6 is explicit: a
remote-set 0 s timeout is a remote-triggered outage. Compiled constants, no `configPollInterval`-style
key.

**A timeout is not a retry.** Backoff and `Retry-After` are **PR.7** and are out of scope; do not
build them here. Make sure a timeout surfaces as the *offline/unavailable* class the UI already
knows, never as a generic failure (`docs/ERRORS.md`).

## Explicitly out of scope

Retry/backoff (**PR.7**) · trace headers (**PR.8**) · error codes on the wire (**PR.9**) · the
capture pipeline · `docs/TASKS.md` · committing.

## Tests

```
cd ios && swift build   ; echo "build: $?"
cd ios && swift test    ; echo "test: $?"     # 970 today (verified). MUST rise.
swiftlint lint          ; echo "lint: $?"     # from the REPO ROOT, must be 0
xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
  -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "app build: $?"
cd backend && dotnet build && dotnet test && dotnet format --verify-no-changes ; echo "backend: $?"
```
Backend integration tests need `bash backend/scripts/dev-up.sh` (plain `docker run`, never compose).
Backend was **266 tests** at last verification.

- **L1**: the session configuration equals the named values - assert the numbers, not that a
  configuration exists.
- **L1**: a stalled transport throws **inside** the budget. Drive it with a controlled stub, not a
  real sleep: this repo has spent today fixing four wall-clock races in `GatewayBudgetTests` where a
  real-time assertion raced the scheduler under load. Do not add a fifth.
- **L1**: the grep gate for `URLSession.shared`.
- **L2**: the named backend client timeouts are what was configured.
- **L4 `ImportUITests`**: Cancel is visible while parsing, and cancelling leaves the garage
  untouched.

Run only the UI suites you touched with `-only-testing:` and **report the observed count for each**
(`ImportUITests` is 13, `SignInUITests` 8). **A `--filter` that matches nothing prints "Test run
with 0 tests ... passed" and exits 0** - that caught the orchestrator three times today, so check
the count, and **name the suites you ran with every mutation result**. An `ios/App` guarantee pins
only at L4.

**Never `pgrep -f`** for a build - your brief is part of your command line, and that killed a
sibling agent 48 minutes in. Use `pgrep -x xcodebuild`; never `pkill -f`.

## Mutations you must run and report

1. Restore `URLSession.shared` at one site. The grep gate must fail.
2. Set the read timeout to the 60 s default. The L1 asserting the numbers must fail - if it only
   asserts "a configuration exists", that is the finding.
3. Give blob PUT the short JSON budget. A test must fail, or the long paths are unpinned and a
   large upload will start timing out in the field.
4. Remove the Cancel affordance. The `ImportUITests` case must fail.

A mutation that does not fail is a finding. One that does not **compile** proves nothing and must be
redone. Use a **heredoc** for scripted edits.

## Screenshots

EN **and** RU, dark: the import parse showing its **Cancel**, and the restore progress showing its.
Capture **outside** a test run, name them `PR.6-import-cancel{,-ru}.png` and
`PR.6-restore-cancel{,-ru}.png`, and register them in `scripts/capture-screenshots.sh`.
**Check the feature is in frame** - six captures have been deleted rather than committed here for
missing their subject. You cannot see them; the orchestrator opens every one.

## Report back

Every command with its **real exit code** and observed counts (iOS before/after, backend
before/after, each UI suite); all four mutation results **with the suites you ran**; the timeout
values you chose and **why each**; the files changed; and anything in this brief that is wrong -
eight agent pushbacks here have been correct.

En-dashes only, never em-dashes.
