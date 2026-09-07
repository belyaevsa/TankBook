# Backend Test Review and Improvement Plan

Review date: 2026-09-07

Scope:

- backend tests in `backend/tests/Tankbook.Api.Tests`;
- backend contracts and verification expectations in `docs/API.md`, `docs/SYNC.md`, `docs/SECURITY.md`, and `docs/TESTING.md`;
- the original backend work and later hardening rows in `docs/TASKS.md`;
- the backend CI and deployment checks in `.github/workflows/backend.yml` and `backend/scripts/deploy-blue-green.sh`.

This is a semantic review. It asks whether a test proves a behavior that matters to a client, an account owner, or an operator. It does not treat a large test count as evidence by itself.

## Overall assessment

The backend suite is materially stronger than a collection of controller status-code tests. It exercises real PostgreSQL behavior, HTTP middleware, authentication, concurrency, retention, privacy, and partial-failure rules. The best tests describe failures a real mobile client will encounter: refresh-token replay, concurrent sync writes, a revoked device, a missing blob upload, an LLM answer that cannot be delivered, or a feed that has no rate for a date.

The suite is still mostly a set of component workflows. It rarely follows one client through a complete journey spanning several endpoints. The main risk is therefore not that individual services have no tests; it is that the seams between well-tested services remain unproven.

The current static inventory contains 386 test attributes in 53 test-bearing files. Of those declarations, 210 use `SkippableFact` or `SkippableTheory` and can skip when Docker is unavailable. Runtime case counts differ because theories expand into more than one case. The large suite is useful, but its reliability currently depends on CI interpreting skips correctly.

The most important findings are:

1. The pull-request workflow does not reject skipped database tests. A PR can be green after the PostgreSQL half of the suite silently disappears.
2. The push/deploy workflow permits up to ten skipped tests. A release can therefore proceed with several unknown integration checks absent, and the gate considers only the number, not which tests skipped.
3. `docs/TESTING.md` defines L2 as PostgreSQL plus MinIO, but all blob endpoint suites replace the real object store with `RecordingBlobStorage`. There is no automated begin -> real upload -> commit -> download check.
4. `docs/API.md` documents `GET /v1/account`, but `Program.cs` maps no such route and the suite has no test for it.
5. The outbox contract promises that acknowledgement is idempotent and scoped to the caller's device. The tests cover drain and first acknowledgement, but not repeated acknowledgement, another device, or another account.
6. Background service logic is called directly, while three endpoint suites explicitly assert that their timers are absent from the test host. This protects test isolation but does not prove that production registers or runs those jobs.
7. Deployment uses the liveness-only `/health` response as its readiness check. That endpoint does not query PostgreSQL or object storage, although the deployment script says verification catches an image that cannot reach the database.
8. The real S3, APNs, and OpenAI-compatible adapters have little or no wire-contract coverage. Service behavior is thoroughly tested through recording doubles, leaving request serialization, authentication headers, provider error mapping, and response parsing exposed.

## Are these user scenarios?

A backend test should not imitate taps. Its equivalent of a user scenario is a sequence of client-visible requests and state changes, such as:

- sign in, refresh, retry an old refresh token, and discover that the chain is revoked;
- push changes from two devices, page through pull results, revoke one device, and keep the other working;
- begin an attachment upload, upload bytes, commit it, restore on another device, and download the same bytes;
- start extraction, lose the connection, reopen the app, drain the result, acknowledge it, and never receive it again;
- delete an account, remain in the grace window, then purge every content store after the window.

Several current tests implement meaningful parts of these sequences. Examples include `Refresh_ReuseRevokesTheWholeChain`, `Pull_UnderConcurrentWrites_NeverSkipsARecord`, `Begin_Dedupe_IsPerAccount_NotGlobal`, and `Drain_ReturnsThePayload_AndTheAckDeletesTheRow_SecondDrainIsEmpty`.

Most tests stop at one service boundary. That is appropriate for the majority of the suite and follows the repository's “mock the boundary” rule. A small set of critical cross-service scenarios is still needed because a recording double can only prove what the test told the double to do.

## Review of the initial backend tasks

The task definitions are generally good. They name observable outcomes, negative cases, concurrency, privacy, and exact persisted state. This is much stronger than tasks that merely request “endpoint tests” or “coverage.” The table below evaluates whether the resulting tests prove the intended meaning.

| Task area | Semantic assessment | Main remaining gap |
|---|---|---|
| P0.8 scaffold and health | Build and host smoke coverage exists. The health test proves the public response shape and version. | It is a liveness test, not a Testcontainers infrastructure smoke test. It does not prove database or object-store readiness. |
| P0.9 migrations and constraints | Strong. Real PostgreSQL tests cover apply, repeat apply, individual rollbacks, uniqueness, cascades, composite keys, and SCN concurrency. | Rollback SQL gets more attention than deployment compatibility. The deploy process applies migrations before switching images and does not roll the database back. |
| P0.10 payload contract | Strong at schema, validation, transform, fixture, and forward-compatibility levels. | There is no cross-repository generated contract or end-to-end old-client/new-server compatibility gate beyond the committed fixtures. |
| P0.11 logging | Strong and meaningful. Tests seed sensitive values and inspect complete rendered log output, correlation, route templates, levels, and error envelopes. | Keep this style; extend the privacy sweep whenever a new request body or provider adapter is added. |
| P0.12a/P0.13 config | Strong. Canonical bytes, signature tampering, schema validation, monotonic publish, expiry choice, ETag, public access, and key parity are covered. | A full release-client verification of the served document remains an environment smoke check rather than a backend suite case. |
| P4.1 auth | Strong. It covers concurrent first sign-in, token hashing, rotation, chain reuse, device reuse, account separation, and the real Apple/Google verifier's issuer/audience/signature rules. | Provider transport failure and JWKS cache/rotation behavior deserve explicit tests if not already guaranteed by the framework library. |
| P4.2 sync | Strong endpoint semantics. Ordering, concurrent pagination, replay, per-item conflict, validation, clock clamp, device revocation, schema gates, and opaque unknown entities are meaningful. | There is no HTTP-level account-isolation scenario using the same record UUID in two accounts, and no compact multi-device journey across sign-in, push, pull, revoke, and restore. |
| P4.3 blobs | Service rules are well covered: per-account dedupe, caps, quota, commit checks, retention, deletion, cross-account lookup, and log privacy. | The stated S3 integration is represented by a recording store. No real S3-compatible server proves signed PUT/GET behavior and byte round-trip. |
| P4.8 notifications | The product rules are well covered: siblings only, throttling, invalid token removal, transient failure, silent payload, and sync success despite APNs failure. | `ApnsClient` itself is not contract-tested, so JWT/header construction and APNs response mapping can break while all notification tests pass. |
| P4.9 account lifecycle | Tombstone, grace-period purge, per-device revocation, push-token clearing, isolation, and privacy tests are meaningful. | The whole purge is not tested across database records, blob objects, imports, outbox content, and ledger content in one scenario. The documented `GET /account` endpoint is absent. |
| P4.10 extraction | Quota, metering, provider failure, response shape, per-account isolation, privacy, retention, and storage-outage behavior are unusually thorough. | Tests replace the actual provider and storage adapter. The OpenAI-compatible JSON and error contract is untested. Duplicate mobile retries remain open as PR.25. |
| RV.44 outbox | Enqueue on failed delivery, no enqueue on normal delivery, read-before-ack, payload round-trip, retention, and account purge are meaningful. | The actual endpoint sequence from an interrupted `/extract` request to drain and ack is split across direct service tests. Device/account isolation and idempotent repeated ack are promised but not asserted. |
| Rates/catalog/import/feedback | These suites have strong examples based on real captured feed/export fixtures, boundary dates, partial parsing, immutable caching, public access, caps, and privacy. | Cross-service retry/idempotency and production adapter readiness are weak. Rate-limit coverage checks only a subset of the routes listed in `API.md`. |

The task list sometimes marks a capability complete when the tests cover its service logic but not its named infrastructure. P4.3 is the clearest case: “S3 storage” is checked mostly through `RecordingBlobStorage`, and the known Content-Length signing limitation is accepted by a green test. The completion language should distinguish “service behavior through a storage seam” from “S3-compatible integration.”

## Tests with high value

These groups should be preserved and used as patterns:

- **Concurrency invariants:** sync pagination under concurrent writes, monotonic SCN allocation, concurrent first sign-in, and retry-safe rate backfill. They assert exact identifiers, sequence values, counts, or queue state.
- **Isolation:** per-account blob dedupe, cross-account blob/device access, quota per account, and composite record keys. These protect against data exposure and corruption.
- **Partial failure:** a mixed sync batch keeps valid items, provider failure does not bill, storage failure does not hide a paid answer, APNs failure does not fail sync, and an invalid import row does not discard valid rows.
- **Durability and retention:** account grace purge, blob orphan sweep, stored import expiry, outbox retention, LLM ledger content purge, and retry queue exhaustion.
- **Privacy:** seeded secrets and domain values are searched across full log output, with checks that the capture is non-empty. These are discriminating tests rather than assertions that a logger method was called.
- **Real data fixtures:** MFM exports and captured CBR/NBK responses catch delimiter, encoding, date-order, holiday, divisor, and locale behavior that hand-written examples would miss.
- **Protocol details that affect recovery:** refresh-token reuse, revoked-device `410`, push-only `426`, problem codes with trace IDs, ETag/304, and read-before-ack outbox semantics.

## Low-value, misleading, or misplaced tests

Very few tests are wholly meaningless. The following ones provide less product confidence than their green status suggests.

### A passing test that asserts a known security limitation

`S3PresignConstraintTests.DeclaredLengthIsNotYetSignedIntoTheUploadUrl_KnownGap` asserts that Content-Length is absent. It records an important fact, but it cannot serve as acceptance evidence for the intended upload constraint. A regression suite should eventually assert the desired bound. Until then, classify it as a known-gap characterization test, keep it out of completion counts, and link it to a tracked remediation or explicit risk decision.

### Tests that prove the test harness disables production work

The following tests assert that a hosted service is not registered:

- `AccountEndpointTests.PurgeTimer_IsNotRegisteredInTheTestHost`;
- `ImportEndpointTests.PurgeTimer_IsNotRegisteredInTheTestHost`;
- `BlobEndpointTests.BlobSweepHostedService_IsNotRegisteredInTheTestHost`.

They are useful harness checks, but they do not verify account purge, import purge, or blob sweep scheduling. Move the concern into one centralized test-host composition test. Do not count these three cases as product behavior. Add separate production-composition tests for all hosted services.

### Health response shape treated as deployment readiness

`HealthEndpointTests` correctly proves the documented liveness response. It becomes misleading only because `deploy-blue-green.sh` uses the same endpoint while claiming the candidate can reach the database. Keep `/health` cheap and add a separate readiness probe with explicit dependency semantics.

### Configuration-value assertions without behavior

`HttpClientTimeoutTests` proves the three named clients do not inherit the 100-second default. That is useful wiring coverage, but it does not prove that a slow request is cancelled and mapped to the promised outcome. Retain one wiring test and add focused cancellation tests to each real adapter where timeout behavior affects the client.

### Migration rollback emphasis

Individual migration apply/rollback tests are useful during development, but production deploys migrate first and never roll the database back automatically. A green `Down` migration test therefore does not prove rollback safety. Spend more of this budget on “new schema + previous application image” compatibility and on upgrading a committed previous-version database snapshot.

### Unit tests that are not scenarios

Canonicalizer, validator, parser, formatter, and feed-decoder tests are not user scenarios. They are still valuable unit tests because their subjects are algorithms and protocol parsers. They should be described as component evidence and should not be used to claim that a complete endpoint journey works.

## Missing scenarios

### 1. A complete two-device sync and restore journey

Create two sessions for the same account. Device A pushes a mixed data set including tombstones and non-ASCII payloads. Device B pulls from zero over multiple pages and compares a canonical hash. Device B edits one record, Device A receives the conflict/current value, Device A is revoked, and Device B remains usable. This joins the existing strong primitives into one client-visible scenario.

Also add an HTTP isolation variant: two accounts use the same record UUID, push different payload bytes, and each account pulls only its own version.

### 2. Real S3-compatible attachment round-trip

Start PostgreSQL and MinIO (or another disposable S3-compatible server), use the production `S3BlobStorage`, and perform:

1. `POST /blobs/begin`;
2. PUT the declared bytes to the returned URL with the declared content type;
3. `POST /blobs/commit`;
4. `GET /blobs/{sha}` and follow the signed URL;
5. assert byte equality and cross-account refusal.

Include wrong content type, wrong length, expired URL, unavailable object store, and delete-prefix behavior. This closes the gap between `docs/TESTING.md` and the current suite.

### 3. Interrupted extraction through the real outbox surface

Drive the endpoint and database in one test: start `/extract`, cancel the client after the provider has accepted work, allow the provider to complete, then call `GET /outbox` with the same device, decode and verify the payload, acknowledge twice, and confirm both acknowledgements return `204` with an empty final drain.

Add another device and another account. Neither may drain or delete the first device's row, and the response must not reveal whether the foreign ID exists.

### 4. Account deletion across every content store

Seed records, committed and pending blobs, a stored import, an outbox row, LLM ledger content, a pending ledger retry, and two devices. Delete the account, prove every device gets `410` during grace, advance an injected clock, run the production purge coordinator, and assert the exact retention decision for every store. This is the privacy-critical version of a user deleting their account.

### 5. Mobile retry idempotency

Complete `PR.25` from `docs/TASKS.md`. Repeat `POST /import/parse`, `/auth/session`, and `/extract` with the same `Idempotency-Key` after a simulated lost response. Assert one stored import, one device registration, one provider charge, one quota increment, and the same replayed response. Also prove that the same key from another account/device does not collide.

### 6. Route policy matrix

Build a table-driven test over every mapped endpoint and assert the contract metadata for:

- authentication or public access;
- rate-limit policy and partition key;
- request body cap;
- content type and problem envelope for rejection.

Current behavioral rate-limit tests cover auth-session and feedback, while `API.md` also promises policies for auth-refresh, import, extract, sync-push, and blob-begin. Current body-cap checks do not exhaust the documented “everything else = 64 KB” routes.

### 7. Real provider adapter contracts

Test outbound adapters through a deterministic local HTTP handler, without calling external services:

- `OpenAiCompatibleLlmProvider`: URL, bearer header, model, image encoding, response field parsing, token usage, malformed response, timeout, `429`, and `5xx` mapping;
- `ApnsClient`: production/sandbox URL, APNs headers and JWT, silent payload bytes, `BadDeviceToken`, `Unregistered`, transient failures, and timeout;
- identity JWKS: cache reuse, key rotation/refetch, timeout, and malformed key sets if those behaviors are owned by this code.

The service suites should keep their recording doubles. These adapter tests cover a different and currently missing responsibility.

### 8. Production composition and background scheduling

Build the application in a production-like environment with safe test secrets and inspect that every required hosted service is registered exactly once. Then test each scheduler with an injected tick/delay source so one tick invokes one pass and cancellation stops it. Avoid real sleeps.

The required set currently includes migration when enabled, import purge, blob sweep, account purge, rate fetch/backfill, LLM call purge/retry, and outbox purge.

### 9. Readiness and deployment rollback compatibility

Keep `/health` as liveness. Add `/ready` for the dependencies required to serve normal traffic, at minimum a bounded PostgreSQL query. Decide explicitly whether object storage is required for global readiness or reported as degraded, because sync can still work during an S3 outage. Make the deploy script wait on readiness.

For every migration, verify that the previous release can still start and serve its critical requests after the new migration has been applied. This matches the actual blue/green rollback path: the old container may restart against the new schema.

### 10. Documented account summary endpoint

Resolve the mismatch around `GET /v1/account`: implement and test the documented storage/quota/account summary, or remove it from `docs/API.md` if the product no longer consumes it. A contract that has neither a route nor a test should not remain silently normative.

## Reliability and CI findings

### Skipped integration tests can ship

`PostgresFixture` calls `Skip.IfNot` when Docker is unavailable. This is convenient locally, but unsafe as a release gate:

- the PR job runs `dotnet test` without TRX inspection, so any number of PostgreSQL tests may skip and the PR remains green;
- the push job parses TRX but accepts up to ten skipped cases;
- the comments and `backend/README.md` still refer to older totals such as 153 PostgreSQL-backed or 295 total tests, while the current static inventory has 210 skippable declarations and 386 total declarations.

In CI, unavailable required infrastructure should fail the integration job before test discovery. Local runs may retain an explicit “unit only” command. A transient individual skip should be retried or fail with its test identity; accepting any arbitrary group below a numeric tolerance can hide the one case relevant to a change.

Add these assertions to both PR and push gates:

- test assembly discovered a non-zero expected minimum;
- zero unexpected skipped tests;
- the integration category ran;
- TRX is always uploaded on failure.

### Expensive database isolation

Each database-backed test creates a new database and reapplies all migrations. Workflow comments record 178 databases and roughly 2,100 migration executions per pass, along with prior memory and timeout failures. Isolation is good; repeatedly testing migration application as setup is unnecessary.

Create one migrated template database per run and clone it for ordinary endpoint tests, or use isolated schemas/transactions where semantics allow. Keep fresh-from-empty databases only for migration tests. This preserves independence while reducing runtime, connection pools, and infrastructure flakes.

### Test-host construction is duplicated

Many suites independently create a database, apply migrations, configure `WebApplicationFactory`, replace the identity verifier, replace storage/provider clients, and remove hosted services. Divergent host configuration can make one suite exercise a different application from another.

Introduce a small shared `ApiTestHost` builder with explicit options for real/fake PostgreSQL, storage, identity, provider, APNs, clock, and hosted services. Keep assertions in each feature suite and avoid hiding endpoint calls behind a large custom DSL.

### CI path filters miss normative contract documents

Backend CI runs for `backend/**` and `docs/schemas/**`, but not for changes to `docs/API.md`, `docs/SYNC.md`, `docs/SECURITY.md`, or `docs/CONFIG.md`. Those files define behavior used by the tests and task acceptance criteria. Add them to the PR path filter, or run a lightweight contract-consistency job whenever they change.

### Coverlet is installed but unused

The test project references `coverlet.collector`, but the workflow neither collects nor publishes coverage. Raw percentage should not replace semantic review. Collect coverage as a diagnostic, fail on uncovered new endpoints/adapters, and use focused thresholds for security- and durability-critical components rather than optimizing a repository-wide number.

### Time behavior is mostly healthy

Most retention and throttle tests use `MutableTimeProvider`, and only the rate startup test uses short polling with `Task.Delay`. Preserve this approach. Replace the remaining polling when the scheduler abstraction is introduced.

## Improvement plan

### Priority 0 — make the existing gate truthful

1. Split fast/unit and PostgreSQL integration execution into named CI steps.
2. Fail CI before tests if Docker/PostgreSQL is unavailable; reject every unexpected skip on PR and push.
3. Record and upload TRX from both jobs, assert a minimum discovered count, and remove stale hard-coded counts from comments/docs.
4. Resolve the missing `GET /v1/account` contract.
5. Add outbox device/account isolation and repeated-ack tests.
6. Add sync HTTP account-isolation using the same record UUID.

### Priority 1 — cover real boundaries and critical journeys

1. Add the production-S3/MinIO attachment round-trip.
2. Add deterministic wire tests for `OpenAiCompatibleLlmProvider` and `ApnsClient`.
3. Add the interrupted-extract -> outbox -> ack journey.
4. Add the two-device sync/restore/revoke journey.
5. Add the all-stores account deletion/purge scenario.
6. Complete PR.25 idempotency for requests commonly replayed after a mobile timeout.

### Priority 2 — prove operations and compatibility

1. Add production DI composition tests and controllable scheduler-tick tests.
2. Add `/ready` and make blue/green verification use it.
3. Test the previous application release against each newly migrated schema.
4. Add the route authentication/rate-limit/body-cap matrix.
5. Clone a migrated template database for normal integration tests to lower runtime and flake pressure.

### Priority 3 — maintainability and visibility

1. Consolidate test-host setup behind a small explicit builder.
2. Label tests as unit, PostgreSQL integration, storage integration, adapter contract, or scenario so CI failures identify the broken layer.
3. Collect and publish coverage as review evidence, with focused checks for new routes and adapters.
4. Add normative backend documents to CI path triggers.
5. Keep known-gap characterization tests in a separately reported category and never use them as completion evidence.

## Proposed scenario set

A compact durable scenario layer could start with these tests:

| Scenario | Principal proof |
|---|---|
| `NewAccount_TwoDevices_PushRestoreRevoke` | A normal account can restore exact data on a second device and revoking the first does not damage the second. |
| `SameRecordId_TwoAccounts_RemainsIsolated` | Tenant scoping holds through the HTTP surface, not only the database primary key. |
| `Attachment_RealS3_BeginUploadCommitDownload` | Production URL signing and S3-compatible bytes work together. |
| `Extract_Disconnect_DeliversOnceThroughOutbox` | Paid work survives a lost mobile connection and remains device-scoped. |
| `DeleteAccount_GraceThenPurgesEveryStore` | The privacy promise applies to every persistence path. |
| `RetrySameIdempotencyKey_ProducesOneEffect` | A normal mobile retry cannot duplicate data, billing, or quota. |
| `CandidateReady_PreviousReleaseStillCompatible` | Blue/green rollback remains possible after migration. |

Keep this layer small. Its purpose is to test connections between components. The existing focused suites should continue to own boundary matrices, parser examples, schema variants, and detailed failure cases.

## Completion criteria

The improvement is complete when:

- both CI paths fail if any required integration test does not execute;
- the API document and route inventory agree;
- the outbox's device scoping and idempotent ack are executable contracts;
- at least one production-adapter test exists for S3, APNs, and the OpenAI-compatible provider;
- the critical multi-device, delayed-extraction, and account-deletion journeys run through the HTTP surface and real PostgreSQL;
- deployment verifies readiness and the prior release remains compatible with the migrated schema;
- the suite retains its current strengths in concurrency, privacy, exact persisted state, and captured real-world fixtures.

## Brief quality summary

Static inventory, counting test attributes rather than expanded runtime theory cases:

| Measure | Count | Share |
|---|---:|---:|
| Test-bearing files | 53 | — |
| Test declarations | 386 | 100% |
| `Fact` | 165 | 42.7% |
| `Theory` | 11 | 2.8% |
| `SkippableFact` | 209 | 54.1% |
| `SkippableTheory` | 1 | 0.3% |
| Docker-skippable declarations | 210 | 54.4% |
| Non-skippable declarations | 176 | 45.6% |

Thematic categorization:

| Category | Declarations | Share | Docker-skippable | Quality assessment |
|---|---:|---:|---:|---|
| Reference data, config, rates, catalog | 119 | 30.8% | 58 | **Strong.** Good real fixtures, date boundaries, signatures, cache semantics, and data provenance. |
| Sync, payload contracts, SCN, migrations | 73 | 18.9% | 43 | **Strong components; incomplete journeys.** Excellent concurrency and schema checks, with limited whole-client sequences and migration rollback compatibility. |
| Blob storage and import | 55 | 14.2% | 28 | **Good service behavior; weak infrastructure realism.** Import fixtures are strong, but storage is almost entirely a recording double. |
| HTTP, logging, feedback, limits, health | 50 | 13.0% | 13 | **Mixed.** Logging/privacy is excellent; readiness and the route limit/body-cap matrix are partial. |
| Identity, accounts, constraints, startup security | 47 | 12.2% | 30 | **Strong.** Token lifecycle, verifier security, account isolation, and startup refusal are meaningful. The documented account-summary route is missing. |
| LLM, delivery outbox, notifications | 42 | 10.9% | 38 | **Strong failure semantics; weak adapter contracts.** Billing, retention, outage, and throttle rules are detailed, but real provider/APNs wire behavior and the complete delayed-delivery path are unproven. |
| **Total** | **386** | **100%** | **210** | — |

Quality by test purpose:

- **High quality:** exact database state, concurrency invariants, account isolation, privacy sweeps, captured provider/export fixtures, retry queues, and retention boundaries.
- **Adequate but fragmented:** endpoint happy/error paths and service workflows. Most are meaningful, but the client-visible result is often split across several suites.
- **Weak coverage:** real S3/APNs/LLM adapter contracts, cross-service user journeys, production scheduler registration, deployment readiness, and old-release compatibility after migration.
- **Misleading as completion evidence:** the green known-gap Content-Length test, hosted-service-absence tests, liveness used as readiness, and arbitrary CI skip tolerance.

Overall rating: **strong component and PostgreSQL integration coverage, moderate client-scenario coverage, weak external-adapter and operational coverage, with a high CI under-run risk because 54.4% of declarations may skip.**
