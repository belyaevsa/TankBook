# PR.8 – trace and client version on the wire

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`:

- `ios/Sources/TankbookCore/Config/TankbookHTTPClient.swift` and its owners (see below)
- a new `AppVersion` type in `ios/Sources/TankbookCore/`
- `backend/src/` (scope enrichment, field rename, fallback id)
- `docs/LOGGING.md` §2, `docs/API.md` if the contract text needs it
- tests: `ios/Tests/`, `backend/tests/`

Do **NOT** touch `docs/TASKS.md`, `ios/App/Sources/ConfirmManual/`, or
`ios/App/UITests/ConfirmManualUITests.swift` – a sibling lane (P1.13) owns those.

Write code first, explore second.

## Use this simulator / toolchain

`iPhone 17 Pro` for anything iOS. Backend is `dotnet build` / `dotnet test` /
`dotnet format --verify-no-changes` – all three must exit 0. **Never** `pgrep -f`/`pkill -f` for a
build (a brief is part of the process command line; that pattern killed a sibling agent once).

## What to build (the row, verbatim in intent)

1. **Every request** carries `X-Tankbook-Trace` (a **UUIDv7**) and
   `X-Tankbook-App: <version>+<build>` plus platform.
2. On **non-2xx**, the client reads `traceId` from the body onto the thrown error - so a support
   report maps to a server line. Without this, every field bug is a guess.
3. Server pushes `clientVersion`, `accountHash`, `deviceId`, `schemaVersion` into the log scope,
   **renames its own field to `serverVersion`**, and falls back to a generated UUIDv7 when the
   header is absent.
4. `AppVersion` parses `Info.plist`; bundle version is `1.0.0`.
5. `docs/LOGGING.md` §2 updated.

## Count the call sites yourself

`docs/PRACTICES.md` says there are **four** `TankbookHTTPClient` owners. There are **nine or more** -
`RemoteRateFetcher`, `RemoteConfigFetcher`, `RemoteHealthProber`, `SessionRefresher`, `AuthService`,
`RemoteVehicleCatalogFetcher`, `FeedbackClient`, `RemoteBlobTransport`, `RemoteSyncTransport`,
`ImportClient`, and possibly the gateway extract client. **Enumerate them yourself and report the
real number.** PRACTICES.md is a useful review and not a source to quote unchecked - five defects
have been found in it, and it also names `recordTransportOutcome` which is really
`recordRequestOutcome`.

If the headers can be applied at **one** chokepoint inside `TankbookHTTPClient` rather than at nine
call sites, do that - a per-caller change is how one transport gets missed. PR.3b hit exactly this:
`ImportClient` was outside the brief's fence and would have shipped unconverted.

## Hard rules that bound this task

- **Rule 12, never log domain values.** Ids, counts, codes, durations and field *names* are
  loggable; amounts, stations, notes, coordinates, payloads, tokens and images are not, at any
  level, in any build. `accountHash` and `deviceId` are identifiers and are fine; an email is not -
  the existing redaction sweep must still pass.
- **Rule 9, the server validates structure, never domain meaning.** Adding scope fields is logging,
  not interpretation - keep it that way.

## Named vacuous traps

- Asserting the header **exists** without asserting it is **unique per call**. A constant trace id
  passes an existence check and is useless in support.
- Asserting `traceId` lands on the error using a 2xx response - the row says **non-2xx**.
- A backend test that asserts the scope dictionary was built, rather than that the **rendered log
  line** carries the fields. `RedactionTests` has a helper (`WithoutMachineFields()`) for sweeping
  rendered output - use the existing pattern.
- Leaving one transport unconverted because the brief's list was short (see above).

## Checks

- iOS: `swift build --package-path ios` 0; `swiftlint lint` **0 from the repo root**; also
  `xcodebuild ... build` → `BUILD SUCCEEDED` (`swift build` does not compile `ios/App`).
  `swift test --package-path ios` – whole suite, never subsetted; it stood at **1094**.
- Backend: `dotnet build`, `dotnet test`, `dotnet format --verify-no-changes` – **all exit 0**,
  judged by exit code. Backend stood at **268 tests**; report the observed count.
- **Mutations, two**: (a) make the trace id constant instead of per-call and confirm a test fails on
  **uniqueness**; (b) drop `traceId` from the error path and confirm the non-2xx test fails.
  Restore by copying backups back and verifying `md5` – **never** `git checkout`.

## Report back

The real number of HTTP owners and where PRACTICES.md was wrong; whether you applied the headers at
a chokepoint or per caller and why; observed counts and exit codes for every command, both
toolchains; both mutation results; `md5` matches. Say whether you **ran** the tests or only wrote
them. Do not commit.
