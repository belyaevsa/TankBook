# Task PR.3b - the config layer GOVERNS: transports obey it, and report to it

Repo: **`/Users/sbelyaev/repos/fuel-counter-ios`**, branch `main`. Work in this checkout.

**Tier 1, order 4** - the second slice of PR.3, and the one that actually **closes P0.12**
(`docs/TASKS.md`: "tick P0.12 when PR.3 lands"). PR.3a made the layer *fetch*; today it fetches a
document that **nothing reads**. **PR.3c** (a `configPollInterval` remote key) is a separate row
and is out of scope.

## Where you may write

```
ios/App/Sources/**            (except Capture/** and ConfirmManual/ConfirmPrefill.swift)
ios/Sources/TankbookCore/Config/**
ios/Sources/TankbookCore/Sync/RemoteSyncTransport.swift
ios/Sources/TankbookCore/Sync/RemoteBlobTransport.swift
ios/Sources/TankbookCore/Account/AccountClient.swift
ios/Sources/TankbookCore/Rates/RemoteRateFetcher.swift
ios/Sources/TankbookCore/Catalog/RemoteVehicleCatalogFetcher.swift
ios/Sources/TankbookCore/Extraction/Gateway/GatewayExtractClient.swift
ios/Sources/TankbookCore/Auth/**
ios/Tests/TankbookCoreTests/**
ios/App/UITests/SettingsUITests.swift
docs/CONFIG.md
```

**Do not** touch `ios/App/Sources/Capture/**` or the extraction parsers, `backend/`, `site/`,
`deploy/`, `.github/`, `Spike/`, `design/`, `project.yml`.
**Do not commit. Do not tick `docs/TASKS.md`** - a concurrent session edits that file.

## Write code first, explore second

Everything below was verified by the orchestrator immediately before dispatch.

## The defect, verified

```
$ grep -rn 'URL(string: "https://api.tankbook.live")' ios/App/Sources ios/Sources
ios/App/Sources/Settings/AppSessionRefresher.swift:18
ios/App/Sources/Settings/AppSync.swift:14,50
ios/App/Sources/Settings/AccountDevicesService.swift:24
ios/App/Sources/Config/AppConfigService.swift:217
ios/App/Sources/ConfirmManual/ManualFillUpCurrencySupport.swift:108
ios/App/Sources/ConfirmManual/GatewayScanSession.swift:130
ios/App/Sources/SignIn/SignInFlow.swift:287,322
ios/App/Sources/Import/ImportService.swift:94
                                                       ---> TEN sites

$ grep -rn "recordRequestOutcome" ios/App/Sources | wc -l
0
```

Two consequences, and the second is the sharper one:

1. **Every transport builds its base URL from the BUNDLED document**, captured **once at
   construction** (`let baseURL = (try? ConfigDefaults.bundledAppConfig().apiBaseURL) ?? ...`).
   A health-gated promotion of `apiBaseUrl` therefore changes nothing: the app keeps talking to the
   bundled host for the life of the process. P0.12c's guardrails are real code that cannot fire.
2. **`ConfigStore.recordRequestOutcome` has no caller**, so `consecutiveFailures` never increments
   and **auto-revert can never trigger**. The brick-proof property P0.12c is named for is,
   in the shipping app, unreachable.

**The count was nine yesterday and is ten today** - PR.1/PR.2 added one while this was queued. That
is the argument for deleting the pattern rather than counting it: each new transport copies the
line, and every copy is another bypass of the `apiBaseUrl` guardrails.

## What to build

1. **Base URL per operation, not per construction.** Every transport asks the config layer at the
   moment it makes a request. A long-lived transport built at launch must observe a promotion that
   happened afterwards. Inject a provider (`@Sendable () -> URL`) or the store - your call, but say
   in the report which and why, and make it **impossible to capture the URL once by accident**.
2. **Report every outcome** to `recordRequestOutcome`: `.transportFailure` when the host could not
   be reached at all, `.response(status:)` whenever it answered - **any** status. The distinction is
   already documented on `ConfigTransportOutcome` and is what separates a broken base URL from a
   broken server. Getting it backwards makes a 500-ing server look like a bad URL and reverts a
   perfectly good promotion.
3. **Delete all ten fallbacks and `AppConfigService.fallbackBundled()`.** The config layer already
   guarantees a base URL - bundled defaults are its job, not each call site's. The fallback branch
   should not exist.
4. **A grep gate as a test**: zero `api.tankbook.live` literals under `ios/App/Sources`. Follow the
   source-scan pattern in `LowPowerModeTests.productionCallSitesMatchTheWiredAndUnwiredSplit`
   (`#filePath`-relative enumeration), and **say plainly in the test what a text scan cannot see**.
   Exclude the bundled `Config.default.json` - that is the legitimate home of the value.

## Explicitly out of scope

A `configPollInterval` remote key (**PR.3c**) · the capture pipeline · any parser · new UI or
strings · `docs/TASKS.md` · committing.

**Do not touch the `parity.*` fixtures.** They deliberately carry the old `tankbook.app` domain:
the signature is over those exact bytes (`docs/TASKS.md` -> W0). Not a defect, and re-signing to
chase a rename weakens a fixture that exists to catch canonicalization drift.

## Tests

```
cd ios && swift build   ; echo "build: $?"
cd ios && swift test    ; echo "test: $?"     # 933 today (verified). MUST rise.
swiftlint lint          ; echo "lint: $?"     # from the REPO ROOT, must be 0
xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
  -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "app build: $?"
```

- **L1**: a transport built **before** a promotion issues its next request against the **promoted**
  host. This is the test the whole slice exists for - write it so a construction-time capture fails it.
- **L1**: five consecutive `.transportFailure` outcomes on a promoted URL **auto-revert to bundled**
  and recovery works. `ConfigStoreTests`' brick-proof case already covers the store's half; this
  pins that the transports actually feed it.
- **L1**: a `500` response reports `.response(status: 500)` and **resets** the failure counter -
  a server error is not evidence the base URL is wrong.
- **L1**: the grep gate.

Run only `-only-testing:TankbookUITests/SettingsUITests` and **report the observed count** (it is 9
today); a selector matching nothing prints "Executed 0 tests" and reads like success. **Do not run
the full UI suite.** **Never `pgrep -f`** for a build - your brief is your command line, and that
killed a sibling agent once. Use `pgrep -x xcodebuild`; never `pkill -f`.

## Mutations you must run and report

1. Capture the base URL once at construction again. The promotion test **must** fail.
2. Report `.transportFailure` where the server actually answered. The counter-reset test must fail.
   Then the mirror: report `.response` for a genuine transport failure - auto-revert must stop
   working and a test must fail. **Both directions**, or the reporting is pinned in only one.
3. Re-add one `?? URL(string: "https://api.tankbook.live")!`. The grep gate must fail.

A mutation that does not fail is a finding - report it as one, and say **which suites you ran**: a
mutation can also "pass" because the guarantee lives in a tier you did not run. One that does not
**compile** proves nothing and must be redone. Use a **heredoc** for scripted edits.

## Screenshots

None expected - this slice changes no pixels. If a Settings string changes, capture EN **and** RU.

## Report back

Every command with its **real exit code** and observed counts; all four mutation results (2 counts
as two); which injection shape you chose for the per-operation URL and why; the files changed; and
anything in this brief that is wrong - six agent pushbacks in this project have been correct.

En-dashes only, never em-dashes.
