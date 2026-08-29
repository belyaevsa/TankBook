# Task PR.5 - app logging through the redactor

Repo: **`/Users/sbelyaev/repos/fuel-counter-ios`**, branch `main`. Work in this checkout.

**Tier 1, order 8 - the last agent-doable blocker.** Hard rule 12 ("never log domain values, at
any level, in any build") is upheld today by a **third-party default**, not by our code.

## Where you may write

```
ios/App/Sources/**                       (the logging call sites)
ios/Sources/TankbookCore/Logging/**
ios/Tests/TankbookCoreTests/**
.swiftlint.yml
backend/src/Tankbook.Api/Logging/**
backend/tests/Tankbook.Api.Tests/**
docs/LOGGING.md · docs/PRACTICES.md
```

**Do not** touch `Capture/**`, `ConfirmManual/**`, `TankbookCore/Extraction/**`,
`TankbookCore/Config/**`, `TankbookCore/Transport/**`, `site/`, `deploy/`, `.github/`, `Spike/`,
`design/`, `project.yml`. **Do not commit. Do not tick `docs/TASKS.md`.**

## Verified immediately before dispatch - and the row's numbers are wrong

```
$ grep -rn "Logger(subsystem:"  ios/App/Sources | wc -l        ->  19
$ grep -rn "privacy: .public"   ios/App/Sources | wc -l        ->  41   (ALL carry an error description)
$ grep -rn "TankbookLog"        ios/App/Sources | wc -l        ->   0
```

The row says "forty `os.Logger` sites"; **41 is the `.public` count and 19 is the `Logger` count**.
The facade exists and is simply never used by the app: `TankbookLog.makeDefault`
(`ios/Sources/TankbookCore/Logging/TankbookLog.swift:46`).

Every one of the 41 has this shape:

```swift
Self.log.error("Anomaly act failed: \(error.localizedDescription, privacy: .public)")
```

**Why that is a rule-12 exposure and not a style question.** `localizedDescription` on a GRDB error
can carry the statement's arguments - station names, notes, amounts. It does not today **only
because GRDB's `publicStatementArguments` defaults to false**. Our code marks the string
`.public` regardless, so the guarantee belongs to a dependency's default rather than to us
(`docs/PRACTICES.md` S4). A different error type carrying a domain value ships it to the log now.

Server side: `LogRenderer.cs:109` writes `exceptionMessage = exception?.Message` **raw**, never
through `TankbookRedactor`.

## What to build

1. **One app-wide `TankbookLog`**, built from `makeDefault`, and the 19 raw `Logger(subsystem:)`
   sites replaced with typed events. The diagnostics export reads the facade's subsystem; a raw
   `os.Logger` is invisible to it (`docs/LOGGING.md` §5).
2. **`error.localizedDescription` is Sensitive**, never `.public`. What stays loggable is what hard
   rule 12 already permits: **ids, counts, codes, durations and field names**. An error's *type* or
   a stable code is loggable; its rendered message is not.
3. **Backend `exceptionMessage` through `TankbookRedactor`.**
4. **A SwiftLint custom rule** forbidding `Logger(subsystem:` outside `Logging/`, so site 20 cannot
   appear. `swiftlint lint` must still exit **0** on the tree - **from the repo root**, where the
   `excluded:` paths resolve.

## The trap this area has already sprung once

`RedactionTests` sweeps rendered output for values that must never appear. **Two Safe-class machine
fields are free-running numbers that can spell the needle**: `timestamp` renders seconds as
`SS.mmm`, so `...:42.317Z` contains `"42.3"`; `DurationMs` is `TimeSpan.TotalMilliseconds`, so a
9.87 s request renders `9876.5432` and contains `"9876.54"`. On the clock alone that fires roughly
**one run in 600**. `LoggingTestHelpers.WithoutMachineFields()` exists for exactly this.

**Use it at every log-output sweep. Never loosen the assertion and never change the needle** - the
next needle has the same problem. Identifiers (`traceId`, `deviceId`, `accountHash`) stay in the
sweep deliberately, so a domain value wrongly routed into one is still caught.

## Explicitly out of scope

Emitting the defined-but-unwired log events and async edges (**PR.10**) · the diagnostics export UI
(**PR.11**) · trace headers (**PR.8**) · error codes on the wire (**PR.9**) · `docs/TASKS.md` ·
committing.

## Tests

```
cd ios && swift build   ; echo "build: $?"
cd ios && swift test    ; echo "test: $?"     # 978 today (verified). MUST rise.
swiftlint lint          ; echo "lint: $?"     # from the REPO ROOT, must be 0
xcodegen generate && xcodebuild ... build     ; echo "app build: $?"
cd backend && dotnet build && dotnet test && dotnet format --verify-no-changes ; echo "backend: $?"
```
Backend was **267 tests**; integration tests need `bash backend/scripts/dev-up.sh` (plain
`docker run`, never compose).

- **L1**: an app error path through `InMemorySink` renders **no value from the injected error** -
  construct an error whose description contains a station name and assert it is absent.
- **L1**: the SwiftLint rule fires on a fixture containing `Logger(subsystem:` outside `Logging/`.
- **L2 backend**: a `RedactionTests` case with a Sensitive value **inside an exception message**.

Name the UI suites if you touch any; **a selector matching nothing prints "0 tests ... passed" and
exits 0** - that caught the orchestrator three times today, so read the count. An `ios/App`
guarantee pins only at L4; say which suites you ran with each mutation.

**Never `pgrep -f`** for a build - your brief is part of your command line, and that killed a
sibling agent 48 minutes in. Use `pgrep -x xcodebuild`; never `pkill -f`.

## Mutations you must run and report

1. Mark one `error.localizedDescription` `.public` again. The `InMemorySink` test must fail.
2. Write `exceptionMessage` raw again. The backend redaction test must fail.
3. Add a `Logger(subsystem:` outside `Logging/`. `swiftlint lint` must exit **non-zero**.
4. Apply `WithoutMachineFields()` **nowhere** and run the sweep against a hand-written line
   containing `9876.5432`. Report what happens - this is the flake above, and I want to know
   whether the helper is actually load-bearing or merely present.

A mutation that does not fail is a finding. One that does not **compile** proves nothing and must be
redone. Use a **heredoc** for scripted edits.

## Screenshots

None - this row changes no pixels.

## Report back

Every command with its **real exit code** and observed counts (iOS and backend, before and after);
all four mutation results **with the suites you ran**; how many call sites you converted and
whether any resisted; the files changed; and anything in this brief that is wrong - nine agent
pushbacks here have been correct, two of them on numbers in these rows.

En-dashes only, never em-dashes.
