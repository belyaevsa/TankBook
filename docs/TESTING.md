# Tankbook – Verification Strategy

*How every story, endpoint, and function is proven. Law: a story is DONE when its checks below pass in CI (or its named manual check is signed off) – "works on my phone" is not a verification level. Companion to `PHASES.md` (when each suite must exist), `JOURNEYS.md` (the stories), `API.md` (the contract), `SCHEMA.md` (invariants + golden vectors), `ERRORS.md` (the 3-question audit).*

## Standing rule: mock the boundary, don't boot the world

**Default to unit tests against mocked seams; reach for a real host or real infrastructure only when the thing under test IS the integration.** A test that boots the API to check a middleware's output is slow, order-dependent, and fails for reasons unrelated to its subject – our own logging tests proved it by failing on a database that wasn't running and on a framework cast that minimal APIs don't allow.

Applied concretely:
- **Middleware, formatters, redactors, validators** → construct them directly with a `DefaultHttpContext` / fabricated log event and a stub `RequestDelegate`. No `WebApplicationFactory`, no routes, no database.
- **Repositories and SQL** → real Postgres via Testcontainers, because SQL semantics ARE the subject (L2).
- **Endpoint contracts** → one thin host-level test per endpoint asserting the wire shape; the logic beneath it is already unit-tested.
- **iOS networking** → a stubbed `URLProtocol` returning canned responses; never a live backend in unit tests.
- **Never** let a unit test depend on Docker, a network, a clock, or a real filesystem path.

The rule of thumb: if a test can fail because something *else* is broken, it is testing too much.

## Verification levels

| Level | Tooling | Proves |
|---|---|---|
| **L1 Unit** | swift-testing / xUnit; pure functions, no I/O | Algorithms match golden vectors |
| **L2 Contract** | Backend integration tests against real Postgres + MinIO (Testcontainers); iOS client tests against a recorded/stub server implementing `API.md` | Both sides implement the same API.md |
| **L3 Scenario** | Multi-client sync simulator: N in-process clients + real backend, scripted interleavings | SYNC.md S1–S9 outcomes, deterministically |
| **L4 UI** | Snapshot tests per screen/state (dark+light, EN+RU, Dynamic Type L) against `design/screens/` intent; XCUITest for flows | Screens match artboards; flows navigate per SCREENMAP.md |
| **L5 Accuracy** | The Spike harness grown into CI: fixture corpus + `expected.csv`, per-locale scoring | OCR/parser gates; regression on every parser change |
| **M Manual** | Checklist per release, named checks only | What automation can't reach (camera feel, haptics, real pumps) |

## Per-story verification (journeys → checks)

| Story | Checks (level) |
|---|---|
| J1 first launch | L4: Welcome→AddVehicle→GuestHome flow; empty-state renders (no N/A tiles). M: time-to-first-entry < 3 min with a real receipt |
| J2 / F6 import | L1: importer round-trip per source format (parse→entities→export→byte-comparable); real My Fuel Manager export reproduces its own lifetime average. L4: partial-import review flow (6-bad-rows fixture) |
| J3 fill-up capture | L5: receipt corpus ≥ target accuracy; cross-check tolerance cases. L4: Confirm happy path, odometer delta shown. M: 5 live fill-ups, median capture-to-save < 15 s |
| J3 mixed receipt | L1: fuel-line-not-grand-total detection on fixture receipts (the ≥95% isolation gate). L4: "Also on this receipt" toggles; grouped save creates FillUp+Expense sharing purchaseGroupId |
| J4 pump photo | L5: pump-display corpus, ships only ≥95% (VISION gate). L1: bare-triple assignment incl. symmetry tie-break |
| J5 fiscal QR | L1: QR payload parser (FNS format fixtures incl. malformed). L2: enrichment fill-blanks-only. L4: F5 degraded save |
| J6 EV charge | L1: kWh stats, tariff cost computation, %→kWh via battery size. L4: charge confirm in headlight accent |
| J7/J7b/J7c service, parts, reminders | L1: lifetime→reminder proposal; shelf link never double-counts (cost/km invariant test); reminder lifecycle state machine (complete→new row anchored at completion; reschedule re-arms; delete vs dismiss). L4: ServiceEntry with date+odometer; ReminderComplete flow into ServiceEntry |
| J8/J9 trends & anomaly | L1: all SCHEMA derived formulas vs golden vectors; anomaly thresholds incl. seasonality fixture; dismiss-with-reason suppression. L4: tile grid, excluded-entry footnote |
| J10 / S8 currency | L1: Money semantics (homeAmount=amount/rate; rateDate=entry date; snapshot immutability; backfill fill-blanks-only; edit clears snapshot). L2: /rates correctness incl. weekend carry-forward. L4: foreign confirm shows rate+source+date |
| J11a/J11 sign-in & restore | L2: session exchange, refresh rotation + reuse-revocation, implicit account creation. L3: pull-from-zero restore equals origin dataset (hash compare). L4: wrong-provider empty-account detection; Restoring shows manifest stats; "sign out" escape |
| J12 (v2) sharing | deferred; S3 out-of-order test stands in |
| J13 export/archive | L1: backup round-trip (export→import→identical entities incl. tombstones); archived cars excluded from active stats |
| F1–F4, F8, F9 failure states | L4: each state renders with its ERRORS.md next-step actions present (snapshot per state). L1: confidence gating logic; pace/order validation matrix (F9a: every check × receipt-date priority) |
| F7 restore failure | L3: server-down mid-restore → partial usable + resume; empty-account honest path |
| F10 / S1–S9 sync conflicts | L3: one scripted test per scenario asserting the documented outcome (S1 LWW+undo entry, S2 single-count until resolved, S3 flag+exclusion, S4 resurrect/tombstone, S5 archived resurrect, S6 invisible retry, S7 queue+batch toast state, S8 identical backfill, **S9 a stale device must not revert a `Vehicle` field edited more recently on another device**). The S-matrix IS the test plan |

## Per-endpoint verification (API.md → L2, all also asserting RFC7807 error shapes)

- `POST /auth/session`: valid Apple/Google tokens (test signers), expired/garbage tokens, account auto-creation exactly-once under concurrent first sign-ins, device row upsert.
- `POST /auth/refresh`: rotation; **reuse of rotated token revokes chain** (the theft test).
- `GET /sync/pull`: SCN ordering, pagination stability under concurrent writes, since=0 completeness, 410 on revoked device.
- `POST /sync/push`: baseScn accept/conflict per item; idempotent replay; batch cap; future-clock clamping.
- `POST /blobs/begin|commit`, `GET /blobs/{sha}`: dedupe, caps (25/10 MB), quota 429, commit-verifies-object, presigned GET expiry, **cross-account 404** (the isolation test – mandatory).
- `GET /rates`, `/rates/pack`, `/catalog`: correctness, immutable caching headers, ETag.
- `POST /feedback`: rate limit, size cap, anonymous + authenticated.
- `POST /extract`: quota 402/429 paths, image cap; transient-processing asserted (no persistence side effects).
- `DELETE /account` + devices: 410 propagation, purge-after-grace job.

## Cross-cutting foundations (established in P0, exercised forever after)

| Concern | Checks |
|---|---|
| **Payload contract** (`SYNC.md`) | L1 coverage: every synced entity has a v1 schema – a new entity without one fails the build. L1 field coverage: every encoded key appears in its schema. L1 round-trip: an unknown field and unknown entityType survive decode→encode byte-identically (the forward-compatibility invariant, made executable). L2: push rejects malformed/oversize/schema-violating payloads with the right code and JSON pointer; unknown entityType accepted unvalidated; `minSupported` returns 426 on push while pull still succeeds. **Parity**: the Swift upcaster and the server's declarative transform produce byte-identical output for every fixture – the test that stops two implementations drifting. **L1 encoding: the fixture corpus must contain non-ASCII text – 2-byte (Cyrillic), 3-byte and 4-byte (emoji) UTF-8 – and a test asserts it does.** An all-ASCII corpus once hid a JSON string decoder that rejected *every* multi-byte sequence: a Russian station name could not be decoded at all, while the whole suite stayed green. We ship EN+RU from day one, so ASCII fixtures do not represent our data |
| **Logging** (`LOGGING.md`) | L1 redaction, both tiers: a fully populated entity through the log path leaks no Sensitive/Never value; `accountHash` replaces email. L2 correlation: a request's traceId appears in the request line, the operation line, and the problem+json body. L1: every mutation emits `begin` + terminal `ok`/`fail`. L1 volume: O(1) log lines per sync batch, not O(n) per record |
| **Remote config** (`CONFIG.md`) | L1 bootstrap: no cache + no network → bundled defaults, app usable. L1 **brick-proof**: unreachable `apiBaseUrl` + N failures → auto-revert to bundled, recovery without user action. L1 tamper: edited document or signature rejected **on cache read**; version below the Keychain floor rejected; expired document rejected. L1 credential binding: a non-allowlisted host is refused by the HTTP client and **no `Authorization` header is ever constructed for it**. L1 partial: an unknown key is ignored while the rest of the document applies. L1 snapshot: config changing mid-operation does not alter that operation's behaviour |
| **Security** (`SECURITY.md`) | L1 Keychain attributes are `AfterFirstUnlockThisDeviceOnly` (a wrong constant compiles fine and fails only in the field). L1 file protection asserted on `.sqlite`, `-wal` **and** `-shm`. CI: bundle scan for high-entropy strings and key prefixes; no-secrets-committed grep. L1 sign-out clears every Keychain item and leaves local data intact |

## Per-function golden suites (L1 – the algorithm core)

1. **Consumption engine**: D1–D4 four-drivers outputs verbatim; edit-cases (volume edit shifts headline, isFull split/merge, date reorder); window floor/extension labels; distance-weighted (not mean-of-per100s) check; conflict-flag exclusion; tank-level adjustment.
2. **Timeline validation**: order/pace matrix, receipt-date priority, save-anyway flagging.
3. **Receipt parser** (exists in Spike): keep green, grow with every OCR bug fixed – each fix adds its fixture.
4. **Money/conversion**: the S8/J10 suite above.
5. **Cross-check + mixed-receipt detection**: tolerance boundaries, line-vs-total.
6. **Importer per format**: round-trips + known-value assertions.
7. **Backup format**: round-trip + schema-version migrator test (v1→v2 fixture from day one, so additive evolution stays honest).

## When the FULL UI suite runs, and when it does not (standing rule, 2026-08-29)

**Per task: only the UI tests that cover what the task touched. The full suite runs at PHASE
completion.** Measured on 2026-08-28, which is why this rule exists: five full runs, 27-29 minutes
each, **about two and a quarter hours**. They found **one** genuine defect and produced **two** false
reds, both from machine contention, each costing another run to disprove.

| Level | When | Cost |
|---|---|---|
| `swift build` + `swiftlint lint` | **continuously, during implementation** | seconds |
| `swift test` (all 873) | **every task** - it is 30 seconds, there is no reason to subset it | ~30 s |
| `xcodebuild test -only-testing:<the suites the task touched>` | **every task** | seconds to ~2 min |
| `xcodebuild test` (the whole suite) | **phase completion, and before any release** | ~28 min |

The reasoning, so nobody "restores rigour" by reverting this:

- **The suite is a gate, not a search tool.** Its unique value is a narrow class - a control that
  renders correctly, reports `isHittable = true`, and does nothing. Nothing else finds those. But it
  finds them in the suite that covers that screen, not in the other 180 tests.
- **Unit tests are not subsetted.** 873 tests in 30 seconds is free; a filtered unit run is how a
  corpus change once shipped red to `main`.
- **A filter that matches nothing reports success.** `--filter` with a bad pattern prints
  "Test run with 0 tests ... passed". Always check the count is non-zero - a subset you cannot see
  running is worse than no subset.
- **Run it alone.** Every false red measured came from a full suite competing with `swift test`,
  lint, or a capture for the machine.

A task brief must therefore **name the suites it expects to run**, e.g.
`-only-testing:TankbookUITests/ConfirmManualUITests`. "Run the UI tests" is not a check.

**The trade, stated honestly:** a subset can miss a regression on a screen the task did not touch.
That is what the phase-completion full run is for, and it is the reason this rule sets a floor
rather than removing the suite.

## The baseline gate: it builds and it lints (every task, no exceptions)

**Before any other check is even meaningful, every task must leave the repo compiling and the linter clean.** This is not a style preference – it is the floor that makes every other gate below trustworthy, and it applies to documentation-only changes too, because those change generated output more often than anyone expects.

A task is not done until, for each tier it touched:

| Tier | Build | Lint |
|---|---|---|
| iOS | `cd ios && swift build` – no errors | `swiftlint lint` **from the repo root** – exit code 0 |
| Backend | `cd backend && dotnet build` – no errors | `dotnet format --verify-no-changes` |
| Spike | `cd Spike/ReceiptSpike && swift build` | covered by the root `swiftlint lint` |

Rules that make this stick:

1. **Run the linter from the repo root.** `.swiftlint.yml` and its `excluded:` paths are root-relative; running it from a subdirectory silently changes what is checked.
2. **Exit code is the gate, not the output.** `swiftlint lint` exits non-zero only on *errors*. Read the exit code – "it printed some warnings" is a pass, "it printed nothing" is not automatically one.
3. **Zero errors is the standard, and it is checked every task.** The count is allowed to be zero and nothing else. This was 13 for most of P0 because nothing verified it, and the single largest cause was a config bug that made SwiftLint check *generated* SwiftPM output – so the gate was failing on code nobody wrote, and everyone learned to ignore it.
4. **Never silence a violation by loosening the rule.** Fix the code, or exclude genuinely generated output (`**/.build`). Widening a threshold to fit new code is how a lint stops meaning anything. If a rule is genuinely wrong for this project, change it deliberately and say why in the same change.
5. **A refactor for lint must not change behaviour.** Where output is generated or ordered – schema `required` arrays, canonical bytes, error ordering – re-run the generator and diff, and say in the report that you did.
6. **Warnings do not block, but do not add them casually.** New code should not introduce warnings a reviewer has to learn to skip past.

## Snapshot baselines are runtime-specific (temporary, until iOS 18 is installed)

P1 development runs on the **iOS 26.5** simulator, because that is the only runtime installed; the
deployment target is and stays **18.0** (`CLAUDE.md` → decisions). The compiler catches API misuse
against an 18.0 target, so the gap is not about APIs – it is about **appearance and runtime behaviour**,
and iOS 26 ships a different default look than iOS 18.

Consequences, which apply to every L4 task until an iOS 18 runtime lands:

1. **Record which runtime a baseline came from**, in the baseline's path or name. A snapshot with no
   runtime recorded is an artefact nobody can re-derive.
2. **A green snapshot suite on 26.5 is not evidence the screen is correct on the floor.** Do not report
   it as such, and do not close an L4 check on that basis alone.
3. **Expect to re-record every baseline on 18** – budget it as known work, not as a regression. The
   alternative (deferring all snapshot work to later) would leave P1 with no visual gate at all, which is
   worse.
4. XCUITest *behaviour* assertions – navigation, back paths, tab-stack preservation, the dead-end audit –
   are far less runtime-sensitive than pixels. Prefer them where a check can be expressed either way.

## CI gates (what blocks merge)

**Build green and lint green on every touched tier** (the table above – this is the precondition for everything that follows) · All L1 green · L2 green (backend PRs) · L4 snapshots reviewed-or-green · L5 accuracy not below the recorded high-water mark (ratchet, never regress) · SwiftLint/dotnet-format · pseudo-localization build (no hardcoded strings) · the ERRORS.md 3-question audit for any new user-facing message (reviewed in PR description).
