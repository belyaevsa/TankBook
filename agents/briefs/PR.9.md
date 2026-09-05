# PR.9 / OB.1 – error codes on the wire

**First of the OB cluster** (`docs/TASKS.md` → OB · Observability). A stable `code` is what every
later layer maps from: OB.3 needs it to record a failure meaningfully, and a status alone cannot
name a next step (hard rule 7).

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios` – **`backend/`, `ios/` and `docs/`.**
This row spans both tiers on purpose: the code is minted server-side and consumed client-side, and
splitting it would ship half a contract.
**Do not run `git add` or `git commit`. Do not touch `docs/TASKS.md`.**
**Never move, rename or delete a file you did not create.**

**Use the `iPhone 17` simulator.**

## What exists today

`backend/src/Tankbook.Api/Logging/TankbookErrorCodes.cs` holds **five** codes:
`internal_error`, `payload_invalid`, `payload_schema_violation`, `schema_version_unsupported`,
`upgrade_required`. There are **74 `Results.Problem` / `Problem(` call sites** in
`backend/src/Tankbook.Api`, so most errors reach the client as a bare status.

On the client, failures are classified by **status code** - see `TankbookHTTPClient`,
`RemoteConfigFetcher`, `URLSessionTransport` and the per-area clients. That is why
[RV.65]'s new "session expired" message had to be derived from a 401 rather than from something
the server actually said.

## What to build

**1. The envelope gains `code`.** Extend `TankbookErrorCodes` with the families the row names -
auth (`token_invalid`, `refresh_reused`, `provider_unsupported`), blobs, import, account, config -
and **make every `Results.Problem` set one.** 74 sites is the point: a code that is only sometimes
present is worse than none, because the client cannot rely on it.

**2. The client maps `code -> L10n string + next step`, with STATUS AS FALLBACK.** The fallback is
not optional: an older client must survive a code it has never seen, and a newer server must be
able to add one. Say how an unknown code behaves - it must degrade to today's status-based message,
never to a blank or a raw identifier.

**3. `docs/API.md` gains the `code` field in its envelope description, and `docs/ERRORS.md` rows
reference the codes** - that is what makes this documentation rather than a constant file.

**Hard rule 7 is the point of the row**: every error names its next step. A `code` is only worth
adding if it lets the client say something more useful than the status did. **For each code family,
say what the user now sees that they did not before** - if the answer is "the same message", the
code earned nothing.

**Hard rule 12**: a code is loggable (it is a code, not a domain value). The problem+json `detail`
must not gain user data on the way past.

**Do not invent a taxonomy larger than the endpoints need.** A code per call site is not a
contract, it is noise. Group by what the CLIENT must do differently - that is the only thing the
mapping table can act on.

## Read before writing

1. **`CLAUDE.md`** – hard rule 7 (every error names its next step and survives being ignored),
   rule 9 (the server validates structure, never domain meaning - a code names a shape failure, not
   a business rule), rule 10 (EN+RU, whole phrases), rule 12, rule 14.
2. `docs/API.md` → the error envelope and every endpoint's status list; `docs/ERRORS.md` → the rows
   that will reference codes; `docs/LOGGING.md` → what a code may carry.
3. `backend/src/Tankbook.Api/Logging/TankbookErrorCodes.cs`, the 74 `Results.Problem` sites,
   `ios/Sources/TankbookCore/Config/TankbookHTTPClient.swift` (it already parses `traceId` from the
   problem body - the natural place to parse `code` too), and the per-area clients that classify by
   status today.

## Tests

**Backend 392 and iOS 1426 today; neither may fall.**

- **The headline L2: EVERY problem+json in the endpoint suites carries a non-empty `code`.** Assert
  it as a property over the suite's responses, not per endpoint - so an endpoint added later
  without a code fails too. This is the assertion that makes the contract real.
- **L1: the mapping table covers every code**, with EN and RU strings (hard rule 10 - whole
  localised phrases, never concatenation).
- **L1: an UNKNOWN code falls back to the status-based message** rather than rendering blank or raw.
  This is the compatibility guarantee; test it explicitly.
- L2: a code never leaks a domain value into `detail` (rule 12).

**Vacuous-assertion traps, named:**
- Asserting `TankbookErrorCodes` contains a string - that tests the constant, not the wire.
- Testing one endpoint's code and calling the contract covered.
- Asserting the client "handles" a code without asserting the STRING the user sees changed.
- A mapping table with a RU entry that is a copy of the EN one.

**Mutation-check and report it**: drop the `code` from one `Results.Problem` and confirm the
every-response property test goes red. Restore byte-for-byte, confirm green.

## The baseline gate (CLAUDE.md rule 14)

    cd backend && dotnet build ; echo "BUILD=$?"
    cd backend && dotnet format --verify-no-changes ; echo "FORMAT=$?"
    cd backend && dotnet test ; echo "TEST=$?"
    cd ios && swift build ; echo "IOSBUILD=$?"
    cd ios && swift test ; echo "IOSTEST=$?"
    swiftlint lint ; echo "LINT=$?"               # repo ROOT
    swift run --package-path ios localization-gate --sources ios/App/Sources \
      --catalogue ios/App/Sources/Localizable.xcstrings ; echo "L10N=$?"   # from repo ROOT
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "APPBUILD=$?"

**Echo the exit code from the COMMAND, never through a pipe**; redirect to a file instead.
`backend/scripts/dev-up.sh` starts Postgres + MinIO (plain `docker run`, no compose).
**Never `pgrep -f`/`pkill -f`.**

## Screenshots

**Only if a user-visible message changed** - then EN and RU, dark, `design/screenshots/PR.9-*.png`
and `-ru.png`, captured OUTSIDE a test run. **Verify each pair differs by `md5 -q` before reporting
it**: RV.58 shipped an "RU" screenshot byte-identical to its EN one and could not tell. If no
message changed, say "none applies" - and note that if NO message changed anywhere, the row may not
have earned its keep, which is itself worth reporting.

## Report back

- Exit codes (captured, not piped) for BOTH tiers, test counts before/after, mutation result.
- **The full code list you settled on, grouped by what the client does differently.**
- **For each family: what the user now sees that they did not before.**
- **What an unknown code does**, and the test that pins it.
- What you changed in `docs/API.md` and `docs/ERRORS.md`.
- Anything you noticed that is not PR.9 - named separately.
