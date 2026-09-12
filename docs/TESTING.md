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

## Which gates for which change (standing rule, 2026-09-06)

**The gate is chosen by what the change TOUCHES, never by how big it feels or how confident the
agent's report sounds.** Everything below is measured, and the evidence column names what each gate
has actually caught - a gate that has never caught anything at its cost is not kept out of respect.

| Gate | Cost | Run it when | What it has caught |
|---|---|---|---|
| **Baseline**: `scripts/gate.sh` – `swift build` + `swiftlint lint` + the app-target `xcodebuild` Debug build + `swift test` + the app-target unit bundle (`xcodebuild test -only-testing:TankbookTests`) – plus the localization gate, all **from the repo ROOT** | seconds (package) to ~2 min (app build + app-target tests, warm DerivedData) | **Always. Every task, no exceptions, including doc-only changes** | Doc changes alter generated output more often than anyone expects; this is the floor that makes every other gate trustworthy. The localization gate itself has caught, since P0.3, a hardcoded string, a missing-RU key, an `L10n.localize` call with no catalogue entry, a literal in a `String`-typed expression (P5.3), and - since RV.102 - a literal routed through a `String` parameter or local into `Label`/`Text`/`Button`, the shape that shipped two English rows on a Russian device with 0 violations because both keys existed. Its current catch-set and its written-down blind spots: `docs/LOCALIZATION.md` |
| **App-target Debug build** (`xcodebuild ... build`, run by `scripts/gate.sh`) | seconds once DerivedData is warm | **Always. Every task, no exceptions** | `RV.174` (2026-09-10): `swift build` 0, `swiftlint` 0 and all 1826 package tests green while `xcodebuild` failed at `FeedbackComposerView.swift:50`. `swift build`/`swift test` compile the SwiftPM package only (`ios/Sources/TankbookCore`); every screen lives in the app target (`ios/App/Sources`), which only `xcodebuild` compiles - package-green is not app-green |
| **Full package unit suite** (`swift test`, ~52 s at 1522 tests) | ~1 min | **Always. Never subsetted** | It is a minute. Subsetting has never once been worth the reasoning about whether it was safe |
| **App-target unit bundle** (`xcodebuild test -only-testing:TankbookTests`, run by `scripts/gate.sh`) | ~15 s of test time on top of the gate (warm DerivedData) | **Always. Every task, no exceptions** | `RV.250` (2026-09-12): `RV212ServiceCreateDoorTests.testAMountedTireSetWithNoOdometerStillRefuses` was orphaned by `RV.214` two rows earlier - `saveReadiness` began branching on `mode == .tires`, the test set only `tireSetId`, and no gate saw it because `swift test` never runs the app-target bundle. The fix, `RV.247`, was a test correction; this step is the gate that would have caught it |
| **Named UI suites** via `-only-testing:` | 5-30 min | The change touches `ios/App/Sources/**` - any view, navigation, or state a screen reads | Regressions in the flow that was touched. **Name them in the brief**; "run the UI tests" is not a check |
| **Screenshots, EN *and* RU, opened by the orchestrator** | ~10 min | The change alters **anything on screen**: copy, layout, a new state, a new row | **The highest-yield gate in the project.** On 2026-09-06 alone it caught four defects no test could see: crushed titles in both languages (`RV.75`), a stale capture showing an affordance the code no longer rendered (`RV.76`), a doubled Russian period (`RV.77`), and an action line resting below the fold while staying tappable (`RV.80`) |
| **Screenshot manifest** (`scripts/check-screenshot-manifest.sh`) | seconds | Any change to `design/screenshots/` or `scripts/capture-screenshots.sh` - and in CI on every push | An orphan committed PNG that no capture line produces (`RV.176`'s class: `RV.150-station`), and a deleted capture line whose PNG stays committed (the named RV.150 mutation) |
| **Mutation of the load-bearing invariant** | 5-15 min | The change makes or modifies the claim the row exists for | Vacuous tests. Two of eight passed on 2026-09-06, and each meant the test grew: a scope released before the copy it was meant to frame (`RV.73`), and a carve-out whose removal left a state with nothing on screen (`RV.80`) |
| **RELEASE build** | 2-4 min | The change touches a `#if DEBUG` seam: a seed, a test hook, a `-seed*` argument, a preview helper | `PR.11`/`OB.4` shipped an unguarded call to a DEBUG-only type. Debug compiled, every gate passed, `main` broke for Release, and `RV.78` found it two rows later |
| **Backend** `dotnet build` + `format --verify-no-changes` + `test` | ~2 min | Any change under `backend/` | Its own tier's floor |
| **FULL UI suite** (~28 min) | 28 min | **Phase completion, before a release build or a TestFlight upload, and after merging parallel work** - never per task | See the section below: five full runs in one day cost 2h15m and produced one genuine defect and two false reds |
| **Cold-launch journey suite** (`-only-testing:TankbookUITests/ColdLaunchJourneyUITests`) | minutes, plus the full UI run it rides | **Phase completion**, with the full UI suite - never per task (it is slow, and it is the same "tap the real graph" class the full run covers) | The DEBUG-only route class at runtime: a screen reachable to a Debug UI test through `-presentScreen` and to no Release user. `RV.165`'s four walks; the guard beside it is `JourneyLaunchArgumentGuardTests` (L1, runs every task) |

### A green `dotnet test` is not evidence the suite ran (RV.107, 2026-09-07)

`dotnet test` prints `Passed!` and exits **0** when Testcontainers cannot start PostgreSQL: the
~214 database-backed tests report as skipped and the gate silently shrinks to the half that needs
no database. Both CI jobs therefore inspect the TRX rather than the exit code - a results file must
exist, `executed` must be non-zero, and the skip count must stay at or under a tolerance of **10**.

**The tolerance is deliberate and must not be set to zero.** Failing on any skip fired a red deploy
on 2026-09-02 over one transient `SkippableFact`. A wholesale skip is ~214; a handful is noise.

**Read the skip count from two sources and take the larger.** Measured on a real
docker-unavailable run: `<Counters ... executed="197" notExecuted="0"/>` while **214** result
elements carried `outcome="NotExecuted"` and the console printed `Skipped: 214`. A counters-only
gate reads that as green - which is the exact failure the gate exists for. The element count is the
direct evidence; the counter is kept because it is what fired the real 2026-09-02 red. The gate also
prints the skipped tests' **names**, because a numeric tolerance alone can hide the one case a
change broke.

### What a worktree backend run can prove (RV.92, 2026-09-07)

A git worktree is a **clean checkout**: files the repo ignores locally are absent there, and
`backend/src/Tankbook.Api/appsettings.json` (+ `.Development.json`) are exactly that - generated and
gitignored (`.gitignore`). Log-capture tests boot the real host, and its `Logging:LogLevel` rules come
from that file, so a worktree host filters **less** than the main checkout: framework Debug lines (a
redirect's `"Redirecting to {url}"`) reach the sink the privacy assertions read. That is not flakiness
in the row under test - it is a config difference the tree's file layout caused, and it reds a test
whose capture relied on the gitignored filter. Two rules follow:

- **A backend test host states its logging rules explicitly** (`Logging:LogLevel:*`), never by
  depending on the gitignored appsettings file - a log-privacy test that does is layout-independent
  (RV.92). A full backend suite cannot run meaningfully in a worktree at all: `.gitignore`'s own note
  records it aborting part-way without the generated appsettings.
- **A backend red measured in a worktree is checked against this before it is read as a regression**,
  and backend rows are verified in the main checkout (or with the appsettings generated into the
  worktree first). The unlocked-enumeration corollary (RV.92): log-capture tests assert against the
  writer's locked snapshot, because the host appends on its own threads and enumerating the shared
  backing list is a data race even when a given run never hits it.

### When lint and compile alone are enough

Only when **nothing that runs is different**:

- documentation, `agents/briefs/**`, queue and scratch files;
- `docs/TASKS.md` ticks and row registrations;
- comments, doc comments, and renames the compiler proves are total.

Everything else runs at least the baseline **plus the full unit suite**, because a minute is not a
saving worth reasoning about.

### The three traps this rule exists to close

1. **A green suite is not a verified change.** XCUITest asserts existence - never truncation, never
   a fold, never a colour, never a doubled period. Four defects on one day proved it; all four were
   found by opening a PNG.
2. **A mutation that PASSES is a finding, not a formality.** It means the test does not cover the
   claim the row was written for. Strengthen the test, then re-run the mutation and watch it fail.
3. **The cheap gates are cheap.** The temptation is always to skip the unit suite or the Release
   build to save a minute; both have cost far more than a minute exactly once, which is why they are
   now unconditional in their column.

### The money-aggregation guard (RV.167)

`MoneyHomeSideSumGuardTests` is a source-scan guard (same shape as `SyncTriggerSourceGuardTests`,
`PaletteAccentGuardTests`) that makes bypassing `LogStream.MonthTotal.Accumulator` a build failure.
The zero-summing defect - a rate-pending row's missing `homeAmount` banked as zero - was fixed one
surface at a time over six rows (RV.106, RV.112, RV.145, RV.147, RV.166), each time because nothing
made the next copy fail. The guard flags any `.reduce` whose closure reads a `Money`'s home side
(`homeAmount`) across **both** `ios/Sources/TankbookCore` and `ios/App/Sources`, and fails with
`file:line` naming the accumulator as the thing to route through. It is a pure function over source
text, so a newly written fixture can be shown to it - it matches the shape, not the one known line,
and the look-alike sums (a draft's untyped cost, an always-known original `amount`, an OCR
`Decimal`) are asserted NOT to flag. The accumulator's own file is the implicit allowlist; any other
entry is a reasoned, commented exception - the monthly-summary push (RV.148) is parked there, and a
bare path entry fails the guard's own self-check. Keeping this row's teeth is part of closing the
deferred defect: when RV.148 lands, route it through the accumulator and delete the parked entry in
the same change (the guard's stale-entry check demands it).

### The entity-writer guard (RV.163)

`SchemaEntityWriterGuardTests` + the `EntityWriterScanner` pure function it is built on: every
`###` entity heading in `docs/SCHEMA.md` must have a production writer outside test seeds, the
import path, sync and `#if DEBUG`, or the build fails naming the entity. It is the guard for the
`RV.156` shape - `upsertStation` was defined and called only by the import path and seeds, so three
shipped features stood on a set no hand-typing user could populate - and it binds the doc to the
repository's write calls across **both** `ios/Sources/TankbookCore` and `ios/App/Sources`. A writer
is a **call** (`.upsertVehicle(`, `createStation(`), never a definition, and comments, strings and
`#if DEBUG` regions are masked first, so prose and seed-only calls cannot satisfy it. Headings that
do not map mechanically to a row are resolved by a reasoned spec (`Entry` is the envelope of its
four concrete types; `ServiceRecord & Expense` is two rows; `ExchangeRate` is a local cache,
deliberately NOT synced, written by the /rates fetch -> persist path). An entity that legitimately
has no writer is a deliberate, reasoned entry in `documentedExceptions`; a bare entry fails the
self-check, and a spec whose heading leaves the doc is stale and fails. The named mutation is
deleting the `RV.156` station-creation door (or `#if DEBUG`-wrapping it): the guard then reports
`Station` with no production writer.

### The field-writer guard (RV.196)

`SchemaFieldWriterGuardTests` + `FieldWriterScanner`: the same question one level down. **A field a
ranking, filter or query reads and nothing writes is `PJ.55`'s shape** - `Station` had a writer
while `Station.favorite` had none, so rung one of the station ranking could never fire and three
features shipped onto a flag no surface could set. The scanner binds the same SCHEMA `###` headings
to the **Swift domain types** that carry their fields (SCHEMA.md names fields in prose and inline
structs, which a reflow would break; the compiled declaration is what the memberwise init and the
decoder agree on - the trade is that a field the docs promise but the type lacks is invisible here).
A field is written when, **in a production host**, it is assigned outside its own declaration, or
passed to its owner's init as a non-default argument (`nil`/`false`/`[]`/`0`, or the declaration's
own default, are not writes), or a production call reaches a repository write function whose body
assigns it (`setStationFavorite` writes `favorite`). The persistence decoder and the repository
write API are **not** hosts: a decoder restores what was stored and cannot originate a value - the
exact shape that hid `PJ.55`. The import path IS a field host (a user triggers it and it fills
`Station.name`), which the entity-level guard excludes but a field guard must not.

The calibration is a live pair: `Preferences.notifications.anomalies` (decoded at
`Records+Extras.swift:247`, set nowhere) is reported, and `Station.favorite` (written by
`StationSettingsView.swift:178`) is not - a guard that flags the field `PJ.55` fixed is tuned
wrong. The named mutation deletes that production call: the guard then reports `Station.favorite`.
Each exception carries a required reason, a bare entry fails the self-check, and a stale exception
(a field that gained a writer or no longer exists) fails too, so the list cannot rot into a config
file. Like RV.163 this is a test-target source scan: no runtime path differs, no screenshot, no
Release build.

**Coverage is the spec table, and the table can be incomplete (PJ.63).** The scan reads a heading's
`typeNames` from `FieldWriterScanner.entityFieldSpecs`, so a persisted type the table does not bind
is invisible even when the doc names it in prose. `ServiceItem` - the line-item child row - now
rides `ServiceRecord & Expense`, and `TireSet` has its own `###` heading; both were outside the
scan before. Two persisted types remain outside both guards: `Tariff` (documented inline under
`ChargeSession`) and `DuplicateResolution` (not in `SCHEMA.md` at all). Adding a heading or a spec
binding is what makes a type visible; a test-target scan cannot see a type the spec does not name.

### The station-minting guard (RV.170)

`StationMintingGuardTests` + the `StationMintingScanner` pure function it is built on: every
production `Station(...)` construction must sit inside the one canonical minting seam. **The seam
is `ImportStationResolver.station(for:existing:now:)` in `ImportStation.swift`** - the investigation
this row demanded found exactly one production construction site outside the decoder, and it is
inside that function. `TankbookRepository.createStation` is a **caller** that routes through the
resolver, and `ImportStationResolver.missingStations` (the import commit) calls it too; neither
constructs a `Station`. The persistence decoder restores a stored row and is not a creation path -
the same discrimination RV.196's field guard had to make, and the scanner's host rule excludes the
`Persistence/` surface, seeds and sync so neither can satisfy it. A second construction path would
mint a station the J4 suggestion ranking cannot rank - `RV.156`'s hole from the other side, after
`RV.150` made a save stamp `lastUsedAt`/`defaults` on the row. The seam is a **function**, not a
file: a second `Station(...)` in `ImportStation.swift` outside `station(for:)` is flagged too. A
future legitimate site is a reasoned exception; a bare entry fails the self-check and a stale one
fails the walk. The named mutation is moving a `Station(...)` construction outside the seam: the
guard then reports its `file:line`. This is a test-target source scan: no runtime path differs, no
screenshot, no Release build.

### The import-candidate copy guard (RV.170)

`ImportCandidateCopyGuardTests` + the `ImportCandidateCopyScanner`: every production
`ImportCandidate(...)` copy helper must round-trip **every** field of the memberwise init. `RV.189`
was the live case - the product owner's imported fills showed `92` instead of the station the file
named, because `ImportBatchMerge.remappingSourceRow` rebuilt the candidate without `station`
between the wire and the conversion; every documented link held and the value was dropped in
between. A compiler cannot catch it because `ImportCandidate.init` **defaults `station` to nil**,
so omitting it is legal; the four sibling helpers happened to pass it and the fifth did not. The
scanner parses the init's own parameter list from `ImportModels.swift` and compares it against what
each construction passes, so it is deliberately **not** keyed on `station` - the next field a helper
drops is caught the same way. In production an `ImportCandidate` is only ever built by copying (the
wire path decodes it with `Codable`), so every production construction is a copy helper; seeds,
tests and the decoder are not hosts. The pre-RV.189 defect is proven against the real broken file,
read from history with `git show e7a7a6c^`, not a synthetic fixture. A future deliberate omission is
a reasoned exception; a bare entry fails the self-check and a stale one fails the walk. The named
mutation is removing `station: station` from `remappingSourceRow`: the guard reports it. This is a
test-target source scan: no runtime path differs, no screenshot, no Release build.

### The receipt-binding guard (RV.171)

`ReceiptBindingGuardTests` + the `ReceiptBindingScanner` pure function it is built on: every
production path that persists a scanned entry binds its attachment id, provenance and
`purchaseGroupId` through the one canonical receipt seam, or the build fails naming the site. It
is the guard for the project's most expensive shape - a scanned save threw its photograph away on
one surface while another kept it, because the binding was a convention rather than a seam. `PJ.28`
fixed the expense scan, its fence stopped there, `RV.149` had to be filed for the fill-up, and
`RV.149` fenced out the grouped case, so `RV.173` had to be filed for the expense siblings. Three
correct fixes, each leaving the next copy unprotected.

**The canonical seam, decided by the investigation the row demanded, is
`ScannedSavePlan.binding(_:)` composed with `ScannedSavePlan.expenses(from:)`.** `binding(_:)`
rebinds the plan to the id the photo write actually produced (`ReceiptWriteOutcome.sharedID`);
`expenses(from:)` is the one place that stamps attachment + provenance + `purchaseGroupId` onto the
group's rows. The investigation found exactly **one** production `.expenses(from:)` call site
(`ManualFillUpView.swift` -> `save()`), and it is bound. The single-expense scan
(`ExpenseEntryView.save` -> `ExpenseReceiptWrite.write`) is a **distinct, non-group shape, not a
second canonical seam**: one row, one write, and the id comes from the write's return value rather
than a shared plan, so the dangling-id defect RV.173 fixed cannot arise there. The typed-attach
paths carry `.manual` provenance and are not scanned saves.

The scanner masks comments, strings and `#if DEBUG` first; seeds, tests, sync and the persistence
surface are not hosts. It reports three shapes: **`.unboundRowBuilder`** - a `.expenses(from:)` call
whose enclosing function never binds a plan to a `ReceiptWriteOutcome.sharedID` (RV.173's pre-fix
wiring exactly), **`.secondBindingSite`** - a `ScannedSavePlan(...)` with a scan provenance
outside the factory/rebind, or a read of the plan's `sharedAttachmentIDs` outside the seam, and
**`.thirdReceiptBuilder`** (RV.209) - an `Attachment(...)` row construction carrying
`extractionMeta:` outside the two canonical builders (`writeReceiptPhoto` and
`ReceiptAttachmentWriter.write`), so a second receipt-persistence path cannot appear silently. It is
deliberately not fooled by the mere presence of `.binding(`: binding the plan to its **own** id
(`scanned.binding(scanned.attachmentID)`) is RV.173's defect restored and is reported too, because
the argument must read the write outcome, not the plan. The calibration is a live pair - today's
bound `ManualFillUpView.swift` is not reported, while the pre-fix trees are: the guard reads
`git show c6df797^` (RV.173's broken grouped save) and `git show 0044e04^` (the same unbound builder
when RV.149 shipped) and reports `save()` as an unbound row builder. The pre-PJ.28 expense scan is
recorded as a **coverage limit**, not a pass: that defect was `attachments: []` on a path that
never built a `ScannedSavePlan`, a runtime degrade decision rather than a binding site, and it is
out of this seam's scope. A future deliberate binding is a reasoned exception; a bare entry fails
the self-check and a stale one fails the walk. The named mutation is reverting the RV.173 call site
in `ManualFillUpView.swift` to `scanned.expenses(from:)`: the guard reports
`ManualFillUpView.swift:577 save binds a receipt outside the canonical seam`. RV.209's mutation is a
third `Attachment(extractionMeta:)` builder in a receipt host: the guard reports it as
`thirdReceiptBuilder` naming the function. This is a test-target
source scan: no runtime path differs, no screenshot, no Release build.

### The screen-reachability guard (RV.162)

`ScreenRouteGuardTests` + the `ScreenRouteScanner` pure function it is built on: every screen in
`docs/SCREENMAP.md`'s per-screen index must have a **non-DEBUG production door**, or be recorded in
the doc's machine-readable `### Screens with no production route` marker (reason required - a bare
entry fails the self-check). It is the guard for the `PJ.4` shape - the Reminders screen whose only
route was gated on a DEBUG flag, so it was reachable to every UI test (they navigate through
`-presentScreen`, itself DEBUG) and to no Release user - and for `PJ.25` (a shelf reachable only
mid-service) and `PJ.20` (copy routing to a screen that did not exist). A DEBUG-wrapped route does
not count: comments, strings and `#if DEBUG` regions are masked before a witness is looked for, and
`DebugLaunch.swift`, `Routes.swift` and `Destinations.swift` are not door hosts - an enum case or a
destination map is not a way in. Each binding names the literal door (`Route.about` is Settings'
`NavigationLink`; `return .serviceEntry` is the capture-mode mapping) and carries a note, so the
table cannot degrade into a skip list. The named mutation is wrapping a real production door in
`#if DEBUG`: the guard then names that screen. **The reachability it proves is "a non-DEBUG door
exists", not graph reachability** - a door on an unreachable screen, or one behind a runtime
condition that can never be true, still passes; full-journey tapping is `RV.165`'s layer, at a phase
gate.

### The cold-launch journey suite (RV.165)

`ColdLaunchJourneyUITests` + the `JourneyLaunchArgumentGuardTests` source-scan guard over its own
file(s). **This is a NEW suite beside the existing UI suites, not a migration of them**: those keep
their seeds and `-presentScreen` navigation, and this one exists precisely because that shape cannot
discover an unreachable screen. A test that starts inside Edit entry can never prove Edit entry is
reachable; `PJ.4` shipped a Reminders screen whose only route was `#if DEBUG` while every UI test
navigated through the debug door and the suite stayed green.

**Four walks, each from a cold launch with the database reset, reaching its destination by tapping:**
J1 -> J3b (add a car, log a typed fill-up, set its station), J3 -> J8b (scan, save, reopen the entry,
see the receipt), J13 -> F10 (delete a car, find it in Recently deleted), and feedback (send it, see
it confirmed, in RU). Each asserts the outcome the user came for - the station in the Stations list,
the receipt on screen, the deleted car in Recently deleted, the confirmation visible without
scrolling - never merely that a screen appeared.

**The guard is half the row.** A journey test that passes a navigation argument must fail the build:
the scanner masks comments, extracts string literals, and rejects `-presentScreen`, any other
`-present*` except the fresh-install `-presentWelcome`, `-openFirst*`, `-select*Tab`, and any flag
not on a small reasoned allowlist. A bare allowlist entry fails the self-check and an unused one is
stale, the same discipline `RV.163`'s exception list uses. Without it the suite regresses to the
shape it replaced the first time a journey is awkward to walk.

**What the cold launch actually is** (measured, 2026-09-10): a launch with `-homeResetDatabase` alone
opens on the **guest Home** (the gate reads `-homeResetDatabase` as the seed harness's tabbed-app
flag and skips Welcome); `-presentWelcome` plus the reset runs the REAL onboarding gate and opens on
**Welcome**. The journeys use `-presentWelcome` for J1/J13, so the first-run path is walked.

**The DEBUG seams, stated rather than hidden.** The receipt walk needs the simulator's missing
camera replaced (`-captureFixtureImage`, `-cameraStatus`) and a deterministic parse
(`-seedFillUpScan`); the feedback walk needs a deterministic terminal outcome
(`-feedbackTransportSuccess`); and the Log is rendered only in the signed-in layout, so the receipt
round-trip cannot be walked by a no-account user at all - `-seedSettingsSignedIn` plants a session
(no vehicle, no entry) and that gap is recorded as a finding. Because those seams are compiled out of
Release, **the harness cannot run this suite against a Release build**; the class it covers is
nonetheless a Release class, and the route mutation (wrapping a production door in `#if DEBUG`) is
what proves the walks have teeth. This suite runs at a **phase gate, never per task**: a row that
adds its minutes to every task's gate gets turned off.

### The screenshot-manifest gate (RV.176 + PR.28)

`scripts/check-screenshot-manifest.sh` + `scripts/screenshot-manifest.py`: every committed
`design/screenshots/*.png` must be produced by a `capture` or `alias_shot` line in
`scripts/capture-screenshots.sh` **and** carry an entry in `design/screenshots/manifest.json`
recording its `runtime`, `device` and `commit`; or be a reasoned `legacy` frame. It is the mirror of
the duplicate-frame check the capture script already carries (`4bbb302`) - that one catches two
names for one frame, this one catches a name no line produces.

The manifest is written by `capture-screenshots.sh` on every run and merged, not rewritten, so a
`FILTER`ed run updates its own frames and preserves the rest. It is read by nothing else: this check
is what makes it load-bearing rather than a file that merely exists.

Why the gate exists, in one measurement: on 2026-09-10 an audit found **193 committed frames with no
producing line** - not the three found by hand, and accumulated over two weeks. Each was either given
a line (reconstructed from its task's DEBUG seed) or recorded as legacy. An unreproducible screenshot
is worse than no screenshot: it looks like evidence and ages invisibly when a shared change lands.

The named mutation is deleting one capture line whose PNG stays committed - `RV.150`'s exact state:
the check exits **1** and names the frame both as "no capture line produces this frame" and as a
stale manifest entry. The mirror - the tree clean - exits **0**. Both directions, and the alias
direction, are covered by `scripts/tests/check-screenshot-manifest.test.sh` (14 cases, synthetic
trees, no simulator). **Legacy is a narrow exception, not a dumping ground**: every entry carries a
reason and the check prints the whole list on each run, so growth is visible.

## When the FULL UI suite runs, and when it does not (standing rule, 2026-08-29)

**Per task: only the UI tests that cover what the task touched. The full suite runs at PHASE
completion.** Measured on 2026-08-28, which is why this rule exists: five full runs, 27-29 minutes
each, **about two and a quarter hours**. They found **one** genuine defect and produced **two** false
reds, both from machine contention, each costing another run to disprove.

| Level | When | Cost |
|---|---|---|
| `swift build` + `swiftlint lint` | **continuously, during implementation** | seconds |
| `swift test` (all 873, the package) | **every task** - it is 30 seconds, there is no reason to subset it | ~30 s |
| `xcodebuild test -only-testing:TankbookTests` (the app-target unit bundle, run by `scripts/gate.sh`) | **every task** - it is the whole bundle, and `swift test` never runs it | ~15 s of test time on top of the gate |
| `xcodebuild test -only-testing:<the UI suites the task touched>` | **every task** | seconds to ~2 min |
| `xcodebuild test` (the whole UI suite) | **phase completion, and before any release** | ~28 min |

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

## A suite can print "passed" while some of its tests never ran (the under-run gate, 2026-08-30)

A full run printed `Test Suite 'CaptureUITests' passed` while **ten** of its tests – across
`CaptureUITests`, `ConfirmManualUITests` and `CarSwitcherUITests` – never executed at all, though all
ten still existed in the source. The summary line and the observed cases disagreed: `xcodebuild`'s
`Executed N tests` is **not** the ground truth, and neither is a per-suite "passed". The only
trustworthy record is the observed test cases themselves.

**The rule: after any `xcodebuild test` run, the observed executed count must equal the declared
count, and a shortfall must FAIL.** The gate is `scripts/check-ui-test-count.sh <log>`:

- It counts the `Test Case '-[TankbookUITests.<Suite> <test>]' started.` lines – one per test that
  actually began executing – and compares that against the number of `func test` declarations in
  `ios/App/UITests/<Suite>.swift`. It deliberately does **not** read the `Executed N tests` summary,
  which is the number that lied.
- Run with no suite arguments it checks every suite the log says "started"; run with suite arguments
  it asserts that a specific `-only-testing:` selection ran its full count. A named suite absent from
  the log counts as 0 observed and fails, which also catches the "`--filter` matched nothing"
  trap (a filter matching nothing prints "Test run with 0 tests ... passed" and exits 0).
- Exit 0 means every checked suite executed its full declared count; exit 1 means an under-run.

The gate is mutation-checked: a log with a deliberately reduced count exits 1 and names the suite;
the full log exits 0. The count is derived from `func test` declarations, never hard-coded, so it
moves as tests are added. When a run surprises you by its count, run the gate before theorising –
the two known causes are a filter that matched nothing, and a runner/app that lost the device
mid-suite (never drive `simctl` while `xcodebuild test` runs; they fight over the device).

## A UI suite plants the session it needs; it never inherits one (2026-09-08, RV.82)

The order-dependence family has bitten the UI suites three times: 2026-08-30 (suites that only
pass in company), 2026-08-31 (the Keychain surviving `simctl uninstall`), and RV.82 (a suite whose
launch arguments planted no session, so it passed when an earlier suite left one in the Keychain
and failed alone on a clean device). The Keychain outlives the database reset and the app
reinstall: `simctl uninstall` does NOT clear it, only `simctl erase` does.

**The rule: a suite plants the session it needs; a suite that reads Home's signed-in chrome may
never inherit one.** Concretely:

- A launch that asserts anything only the signed-in layout draws (the `carSwitcherButton` header,
  the signed-in `typeItButton`) must carry a session-planting seed (`-seedSettingsSynced`, or a
  gate-planted seed such as `-seedVehicleForUITests`/`-seedRemindersDeepLink` whose data only
  exists on the signed-in Home), and that seed must be one of ITS OWN launch arguments.
- A suite must pass **alone** on a device whose Keychain was deliberately cleared (`xcrun simctl
  erase`), not only in a full run. A full run is the state that hides this defect: it is
  deterministic in both directions, green in company and red alone, which is worse than a flake
  because the full suite certifies it.
- Do not fix a suite by tolerating the guest layout it was not designed for, and do not plant the
  session in a shared `setUp` that other suites also mutate - both move the coupling rather than
  removing it. The seed that names the state belongs in the suite's own launch.

## The Vision OCR concurrency ceiling (RV.52)

Adding one more OCR test once made the whole `swift test` run hang (>210 s against a
~65 s clean run). It is Apple's framework, not the test, and it bounds every future OCR
test. This is the measurement and the rule that keeps it from recurring.

**The measured ceiling.** On a 12-core Mac (2026-09-04): **11 concurrent Vision
`perform` calls are safe, a 12th hangs** the process in `_dispatch_semaphore_wait_slow`
inside `VNControlledCapacityTasksQueue`. Measured three ways: a 12-way synchronous
parameterized test hangs (11 passes in 1.6 s, 12 never returns), a `DispatchSemaphore`
gate does not help, and `concurrentPerform` from libdispatch threads does not reproduce
it (24 fine). The hang is specific to blocking **Swift concurrency's cooperative thread
pool** – the pool `swift test` runs test cases on. A blocked cooperative thread still
consumes the pool, so any *blocking* gate (semaphore, serial queue) leaves 12 blocked
threads hanging exactly as 12 active ones do. The decisive variable is not the gate but
**where the `perform` runs**: on the caller's (cooperative) thread it hangs, on a
background dispatch thread it does not (40 concurrent callers measured clean).

**The fix, and it has two halves that are not interchangeable.** `VisionTextRecognizer`
(the single choke point every OCR request in the process passes through – tests and
app alike) runs its `perform` on a background dispatch thread through `VisionRequestGate`.
That is the half that removes the hang: no cooperative thread is ever inside the
recognizer. The API stays synchronous – the caller waits on a per-call completion
semaphore – so the app's callers are untouched. The second half is the gate's bound
(`VisionOCRConcurrency.limit = 8`) that caps in-flight performs so a future suite cannot
exhaust the dispatch pool. The **limit is defence-in-depth, not the hang fix**: raising
it to 100 leaves the suite green, while running the body on the caller's thread hangs it
again. `ios/Sources/TankbookCore/Extraction/VisionRequestGate.swift` records this so nobody
"restores rigour" by reverting to a blocking gate around a caller-thread perform.

**The rule for the next person adding an OCR test.** Call `VisionTextRecognizer` –
never `VNImageRequestHandler.perform` directly – and the gate applies automatically;
there is nothing to opt into. If you are tempted to raise `VisionOCRConcurrency.limit`,
re-measure the ceiling first (the probe pattern is the synchronous parameterized test
above) and keep the same margin: the recorded 8 is ceiling 11 minus 3. The cost of the
gate is nil in wall-clock – the suite runs *faster* than the blocking baseline because
the recognizer is no longer driven from the cooperative pool.

## The baseline gate: it builds and it lints (every task, no exceptions)

**Before any other check is even meaningful, every task must leave the repo compiling and the linter clean.** This is not a style preference – it is the floor that makes every other gate below trustworthy, and it applies to documentation-only changes too, because those change generated output more often than anyone expects. **On iOS the whole chain is one command, `scripts/gate.sh`**, and it deliberately does not stop at the package.

A task is not done until, for each tier it touched:

| Tier | Build | Lint |
|---|---|---|
| iOS | `scripts/gate.sh` – `swift build`, then the app-target `xcodebuild` Debug build, then `swift test`, then the app-target unit bundle (`xcodebuild test -only-testing:TankbookTests`); all exit 0 | `swiftlint lint` **from the repo root** – exit code 0 (also run inside the script) |
| Backend | `cd backend && dotnet build` – no errors | `dotnet format --verify-no-changes` |
| Spike | `cd Spike/ReceiptSpike && swift build` | covered by the root `swiftlint lint` |

Rules that make this stick:

1. **Run the linter from the repo root.** `.swiftlint.yml` and its `excluded:` paths are root-relative; running it from a subdirectory silently changes what is checked.
2. **Exit code is the gate, not the output.** `swiftlint lint` exits non-zero only on *errors*. Read the exit code – "it printed some warnings" is a pass, "it printed nothing" is not automatically one.
3. **Zero errors is the standard, and it is checked every task.** The count is allowed to be zero and nothing else. This was 13 for most of P0 because nothing verified it, and the single largest cause was a config bug that made SwiftLint check *generated* SwiftPM output – so the gate was failing on code nobody wrote, and everyone learned to ignore it.
4. **Never silence a violation by loosening the rule.** Fix the code, or exclude genuinely generated output (`**/.build`). Widening a threshold to fit new code is how a lint stops meaning anything. If a rule is genuinely wrong for this project, change it deliberately and say why in the same change.
5. **A refactor for lint must not change behaviour.** Where output is generated or ordered – schema `required` arrays, canonical bytes, error ordering – re-run the generator and diff, and say in the report that you did.
6. **Warnings do not block, but do not add them casually.** New code should not introduce warnings a reviewer has to learn to skip past.
7. **A task that touches a `#if DEBUG` seam also builds RELEASE** (added 2026-09-06, after it cost a shipped break): run **`RELEASE=1 scripts/gate.sh`**, which adds this build to the baseline chain.

   ```
   xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
     -configuration Release -destination 'generic/platform=iOS Simulator' build
   ```

   `swift build` and the ordinary `xcodebuild` gate compile **Debug**, where every `#if DEBUG` type
   exists. A production call site that references a DEBUG-only type therefore passes the whole gate
   and fails only when someone builds for release. That is not hypothetical: `PR.11`/`OB.4` shipped
   `AboutView` calling the DEBUG-only `DiagnosticsTestSeed` unguarded, was verified green by the
   orchestrator, reached `main`, and was found two rows later by `RV.78` - which would have surfaced
   at `SH.2` or a TestFlight upload instead. **Seeds, test hooks, `-seed*` launch arguments and
   preview helpers are all DEBUG seams**; if a row adds or calls one, build Release before ticking it.
8. **`swift build` and `swift test` are not the app build** (added 2026-09-10, `RV.174`). They compile
   the SwiftPM package (`ios/Sources/TankbookCore`) only; every screen lives in the app target
   (`ios/App/Sources`), which only `xcodebuild` compiles. `scripts/gate.sh` therefore runs the
   app-target Debug build as a baseline step and stops at it - **package-green is not app-green**.
   The escape is measured, not theoretical: a change passed `swift build` 0, `swiftlint` 0 and all
   1826 package tests green, and `xcodebuild` then failed at `FeedbackComposerView.swift:50`. A
   `scripts/gate.sh` that omits the `xcodebuild` step, or ignores its exit code, is the defect this
   rule exists for. The gate's own teeth are pinned by `scripts/tests/gate.test.sh` (synthetic
   tools, no simulator): each step's failure exits with its code and stops the ones after it, the
   step order is package -> lint -> app -> package-tests -> app-tests, and `RELEASE=1` adds the
   Release build.
9. **`swift test` is not the app-target test suite** (added 2026-09-12, `RV.250`). The package tests
   and the app-target unit bundle (`TankbookTests`, hosted in the app) are two different bundles, and
   `swift test` runs only the first. A test can therefore be orphaned by a change to the app's own
   types and every package gate stays green: `RV212ServiceCreateDoorTests.testAMountedTireSetWithNoOdometerStillRefuses`
   went red when `RV.214` made `saveReadiness` branch on `mode == .tires`, and stayed red for two rows
   because the bundle was run only when a brief happened to name one of its suites. `scripts/gate.sh`
   therefore runs `xcodebuild test -only-testing:TankbookTests` as its own step after `swift test`,
   **in its own invocation** - `-only-testing` naming both `TankbookTests` and `TankbookUITests` in one
   command runs one of them and exits 0 (the two-bundle rule). The UI bundle stays per-suite and
   per-brief; it is the slow one.

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

**Build green and lint green on every touched tier** (the table above – this is the precondition for everything that follows) · All L1 green · L2 green (backend PRs) · L4 snapshots reviewed-or-green · L5 accuracy not below the recorded high-water mark (ratchet, never regress) · SwiftLint/dotnet-format · pseudo-localization build (no hardcoded strings) · screenshot manifest (`scripts/check-screenshot-manifest.sh` – every committed PNG has a producing line and a manifest entry, or is reasoned legacy) · the ERRORS.md 3-question audit for any new user-facing message (reviewed in PR description).
