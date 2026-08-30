# Tankbook – Mobile + Backend Integration Practices

*The checklist a mobile app with a server behind it is held to, in four areas: architecture,
UX under a network, security, and debuggability - plus the policy for tunable constants and a
review of the ones the code actually uses. Companion to `SYNC.md` (the protocol), `SECURITY.md`
(where secrets live), `LOGGING.md` (what is logged), `ERRORS.md` (what the user sees) and
`CONFIG.md` (what may change without a release). Where a practice below is already a hard rule
in `CLAUDE.md`, the rule number is cited; this document explains the reasoning behind it and
records what the code does about it.*

Scope: **v1** (`CLAUDE.md` → Version scope); the v2 agent's own practices live in `docs/AGENT.md`. Written 2026-08-29. Section 7 is the review of the current implementation against sections 1-6;
it is re-run at each phase gate and dated.

## 1 · Architecture choices that set everything else up

| # | Practice | Why it matters | Tankbook |
|---|---|---|---|
| A1 | **One source of truth per data type, written down.** Local-first (device owns the data, server is a hub) or server-first (device is a cache) - never a per-screen mix without a rule | Every "why is this stale" bug traces to an undocumented mix | Hard rule 1; `SYNC.md`. Local-first for all user data; reference data (rates, catalog) is server-authored, device-cached |
| A2 | **Version the contract.** Every request carries app version and build; the server may reject, warn or degrade | Old clients live for years; the deprecation path must exist before the first release | `CONFIG.md` -> `appUpdate` (`minSupportedVersion`, `latestVersion`), `426 upgrade_required` in `API.md` |
| A3 | **Idempotency everywhere the network can drop.** Client-generated entity ids, idempotency keys on mutating calls, upserts on the server | A retried POST must never create a second fill-up | `SYNC.md`: push is idempotent by id + `baseScn`; blob upload is re-begun, not resumed |
| A4 | **Structure on the server, meaning on the client** - or the reverse, but one of them | Domain logic split across tiers doubles the bug surface and makes offline impossible | Hard rule 9 with its one named exception (`/import/parse`) |
| A5 | **Schema evolution is data, not deploys.** Device migrations are the scariest code in the app: they run once, on the user's data, with no retry | A migration that works on the dev DB and fails on a three-year-old user DB loses everything | `SYNC.md` -> Payload contract; schema registry + declarative transforms. Device-side: back up before migrating, test migrations against exported real DBs |
| A6 | **Stats are derived, never stored** | Stored aggregates drift from their inputs after every edit, merge and import | Hard rule 2 |

## 2 · UX with a network in the loop

| # | Practice | Why it matters | Tankbook |
|---|---|---|---|
| U1 | **Never block the UI on a request the user did not ask for.** Sync, refresh and prefetch run in the background; the user sees badges, not spinners | A spinner on launch is a broken app on a train | `CONFIG.md`: the config fetch is never awaited by a view; `SYNC.md` -> the user-initiated vs background table |
| U2 | **Optimistic writes, reconciled later.** Save locally, show immediately, push when possible | Waiting for the server to confirm a save is a server-first design wearing local-first clothes | `SYNC.md` S1-S8 |
| U3 | **Conflicts surface where the data lives, never as a modal at sync time** | A modal at sync time interrupts something unrelated and is dismissed without reading | Hard rule 8 |
| U4 | **Offline is a status, not an error.** Distinguish no network / server unreachable / server rejected / auth expired - each has a different next step | "Something went wrong" tells the user nothing and support less | `ERRORS.md` severity vocabulary; F-journeys in `JOURNEYS.md` |
| U5 | **Every error names its next step and survives being ignored** | An error the user cannot act on is noise; one that blocks is a trap | Hard rule 7 |
| U6 | **Timeouts are UX.** Mobile radios sit half-connected for 20-60 s. Short connect timeout (5-10 s), longer read timeout, progress + cancel for anything over ~2 s | A 60 s default timeout is a 60 s frozen button | See section 6, constants T1-T3 |
| U7 | **Retry with jittered exponential backoff, capped; never retry a non-idempotent call without a key** | Synchronised retries from a fleet of devices are a self-inflicted outage | `API.md` line 316: one silent retry at most for user-facing calls; `SYNC.md`: push backs off exponentially |
| U8 | **Token expiry is invisible.** A 401 refreshes transparently; a failed refresh re-authenticates *without losing unsaved input* | Losing a half-filled form to a sign-in screen is the classic mobile UX crime | `API.md` auth; check in section 7 |
| U9 | **Respect the power and data budget.** Batch network work, honour Low Power / Low Data Mode, do not poll when push or background refresh will do | Battery complaints are the review that kills a utility app | `NOTIFICATIONS.md`; `CONFIG.md` "poll, push as a hint"; `SYNC.md` -> heavy work only when the user asked (P6.8 power policy) |
| U10 | **Localise from day one, including server-driven text** - or better, the server sends codes and the client renders them | Server-sent English is unlocalisable later, and a server-sent string is a phishing surface | Hard rule 10; `CONFIG.md`: no server text on the update notice; `LOCALIZATION.md` |
| U11 | **Remote flags with guardrails and auto-revert** | The flag that cannot be turned off is the outage that cannot be stopped | `CONFIG.md`: the three layers, `apiBaseUrl` guardrails |
| U12 | **The app suggests, the user decides.** Every derived value is a default input, editable now and later, and permanently the user's once changed | A pre-fill the user cannot correct is worse than an empty field | Hard rule 13; hard rule 15 (two doors) |

## 3 · Security

**On the device**

| # | Practice | Why it matters | Tankbook |
|---|---|---|---|
| S1 | **No secrets in the bundle** - an IPA is a zip. Third-party keys stay behind your own server | Anything shipped is public within a day of release | Hard rule 11; the LLM gateway exists for this reason |
| S2 | **Tokens in the Keychain with the right accessibility class**; the database and attachments under file protection, *including* SQLite `-wal`/`-shm` | The WAL file holds the last N transactions in clear and is the file people forget | `SECURITY.md` -> iOS table; Keychain class enforced by `KeychainSessionStoreTests`, file protection by the app-target `TankbookTests/FileProtectionTests` (L2, check in section 7) |
| S3 | **Short-lived access token + rotating refresh token; revoke server-side on sign-out** | Deleting the token locally does not end the session | `SECURITY.md`: access ~1h, refresh rotating; `API.md` `/auth/logout` |
| S4 | **Never log domain values, at any level, in any build.** Crash reporters and analytics SDKs are the usual leak path; audit their defaults | One `print(payload)` at 2 am ships to production | Hard rule 12; `LOGGING.md` three classes, redactor at the logger |
| S5 | **Certificate pinning is a trade-off, not a default.** Pinning bricks the app on cert rotation unless backup pins ship with remote update; plain TLS + ATS + no user-CA trust serves most apps better | A pinned app with an expired pin is 100% down with no fix but a store release | `SECURITY.md` -> Transport: TLS 1.2+, ATS, no exceptions, no pinning |
| S6 | **Jailbreak detection is theatre.** The OS is the trust boundary | It breaks legitimate users and is bypassed in minutes | `SECURITY.md` threat model, "we do not defend against" |
| S7 | **Refresh-token races are real.** Two requests 401 at once, both refresh, the second invalidates the first - serialise refresh behind one in-flight task | Users get signed out "randomly" and nobody can reproduce it | Check in section 7 |

**On the server**

| # | Practice | Why it matters | Tankbook |
|---|---|---|---|
| S8 | **Device identity and account identity are separate.** An anonymous device id from first launch supports no-account users and later linking | Forcing sign-in to use the app is a local-first violation and a conversion cliff | `API.md` device auth; import stored under device identity |
| S9 | **Rate-limit per device and per account; size-limit every payload; validate against a registered schema before any code reads it** | Unbounded input is the cheapest DoS there is | `API.md` envelope limits; `SYNC.md` payload contract; check limits in section 6 |
| S10 | **Blobs via presigned URLs, never proxied; content-type and size enforced at the storage layer too** | Proxying blobs makes the API tier the bottleneck and the attack surface | `SYNC.md` blob pipeline |
| S11 | **Retention is a written number honoured by a job, not a promise** | "We delete it eventually" is not a policy | `SECURITY.md`: 30 days for import files, matching the tombstone window |
| S12 | **Account deletion is a tested feature, not an ops ticket** | Store requirement and a legal one | `API.md` `/account` DELETE; check in section 7 |
| S13 | **A one-page threat model in writing** | Keeps "should we encrypt this" answers consistent across years of contributors | `SECURITY.md` -> Threat model |

## 4 · Debuggability

| # | Practice | Why it matters | Tankbook |
|---|---|---|---|
| D1 | **Trace correlation end to end.** Client-generated trace id per action, sent as a header, logged on every server line, returned in every error body | "It failed at 14:32" becomes an exact request on both tiers | `LOGGING.md` §2: `X-Tankbook-Trace`, UUIDv7, echoed in `problem+json`; note the `Response.Clear()` caveat on 500 |
| D2 | **Structured logs with a privacy class per field, enforced by a wrapper or lint** | Intentions do not survive the on-call engineer | `LOGGING.md` §1; the substring-sweep tests |
| D3 | **Diagnostics export the user can send**: recent logs, versions, device, sync state, DB stats, with a preview of what leaves the device | The interesting bugs do not crash; a crash reporter never sees them | `LOGGING.md` §5, opt-in, previewed; check whether it is built in section 7 |
| D4 | **Error codes cross the wire, not messages.** `{ code, traceId, details }`; the client maps code -> localised text + next step | Messages change and are unlocalisable; codes are greppable in both codebases | `API.md` `problem+json`; `ERRORS.md` |
| D5 | **Sync state is visible**: last successful sync, pending count, last error - in Settings for the user, not only a debug screen | "Is it synced?" is the number-one support question for any local-first app | `SCREENMAP.md` Settings -> Sync; check in section 7 |
| D6 | **Deterministic reproduction**: seeded fixtures, a launch argument that freezes time and cuts the network, a way to load an exported DB into the simulator | A bug you cannot reproduce is a bug you cannot close | P6.21 (seeded launches, frozen screenshots); DB-import path to check |
| D7 | **Log the platform's asynchronous edges at the moment they happen**: background task expiry, kill mid-write, network flip mid-upload, device/server clock skew | Each of these is a bug nobody will ever see in a log unless it was written then | `SYNC.md` background section; check in section 7 |
| D8 | **Crash-free is not correct.** Track silent-failure counts: sync retries, conflicts, failures per error code, OCR pre-fills fully overwritten by the user | The product hurts long before it crashes | `LOGGING.md` §3 events; `EXTRACTION.md` accuracy gate |
| D9 | **Server: bodies redacted by schema, slow-query log, per-endpoint error rate keyed by app version** | A bad build is found in hours, not in reviews | `LOGGING.md` server section; check in section 7 |
| D10 | **Snapshot and UI baselines are runtime-specific artefacts**; test on the oldest device you promise | A green suite on iOS 26 proves nothing about iOS 18 | `CLAUDE.md` decided: 26.5 now, iOS 18 re-record later |

## 5 · The ten that always bite

1. A retried POST without an idempotency key -> duplicates (A3).
2. Refresh-token race (S7).
3. Time zones and "today": store UTC plus the user's local date whenever the date is the domain fact. Tankbook's `rateDate` = entry date, never today (hard rule 3).
4. Migrations that pass on the dev DB and fail on an old user DB (A5).
5. Logging the payload "just for debugging" and shipping it (S4).
6. A background upload that finishes after the app was killed, whose completion nobody wrote to disk (D7).
7. Assuming device and server clocks agree (D7).
8. Server-localised errors in one language (U10).
9. Conflicts resolved by last-write-wins on device clocks (U3, S8 in `SYNC.md`).
10. Nothing tells the user what went wrong *and* what to do next (U5).

## 6 · Constants: which values may be compiled in, and what each one costs

A tunable value can live in one of four places. The choice is a product decision with a user
cost, not a code-style preference, and the wrong tier shows up as one of three failure shapes:
**the user cannot change something they should own** (a UX bug, hard rule 13), **we cannot
change something without a store release** (a maintenance bug: a 7-day review cycle for a
one-number fix), or **a change silently alters what stored data means** (a correctness bug:
the number should have been frozen).

| Tier | Lives in | Use when | Cost of getting it wrong |
|---|---|---|---|
| **C - compiled constant** | `static let` / `const`, one definition, named | The value defines *meaning* (consumption window, money precision, file-protection class) or is a security invariant. Changing it must go through review and tests | Too many here: every tuning is a release. A magic literal instead of a named constant: the same number diverges across tiers |
| **R - remote config** | `CONFIG.md` document, signed, cached, bundled fallback | The value is *operational*: thresholds, quotas, kill switches, polling cadence, endpoints. Wrong values must be recoverable without a release | Too much here: a config edit changes what a number means for users who never updated; the config becomes an unreviewed second codebase. `CONFIG.md` forbids business rules and consumption math for exactly this reason |
| **U - user setting** | Per-car or per-app setting, synced, user-owned once changed | The value is a *preference* or a fact about the user's world (units, currency, tank size, "warn me when...") | Too few here: hard rule 13 violations. Too many: a settings screen nobody reads, and defaults that must still be right |
| **F - frozen snapshot** | Stored on the record at write time | The value participated in a computation whose result must not drift (`rateDate`, rate snapshot, schema version of a payload) | Reading a "current" value where a snapshot was needed rewrites history on every recompute |

Rules that follow:

- **Every number that appears in two places is a bug waiting.** A timeout in the client and its
  twin on the server, a retention window in a job and in a doc, a page size in a query and in a
  test: define once, reference everywhere, and where the two tiers must agree, put the value in
  `API.md` and test that both read it.
- **A constant the user can hit deserves an error that names it.** A 10 MB image limit the
  user cannot see is "upload failed"; one they can see is "photos over 10 MB are shrunk first"
  (hard rule 7).
- **Time windows in days are user-visible promises** (30-day undo, 30-day import retention,
  ~2 years of rates). They belong in `SECURITY.md`/`SCHEMA.md` as written commitments, in code
  as one named constant each, and in copy through the String Catalog with the number
  interpolated, never typed into the string.
- **Consumption-model parameters (90 days, floor 3, drift 0.12) are meaning, not tuning.**
  Compiled, tested against the D1-D4 golden vectors, changed only with a doc change. Remote
  config may never touch them (`CONFIG.md`).
- **OCR confidence cutoffs are the opposite**: pure tuning against a growing corpus, already
  designated remote in `CONFIG.md`. A compiled cutoff is a maintenance bug.
- **Timeouts, backoff and poll intervals are operational** and belong in one place per tier
  with a remote override for the cadence ones (`configPollInterval`, sync cadence), not for the
  transport ones (a remote-set 0 s timeout is a remote-triggered outage).
- **Default currency and units are locale guesses** - tier U from the moment they are shown
  (hard rule 13); the compiled part is only the guess table.

### 6.1 · Inventory of constants in the code (2026-08-29)

The table is filled from a full scan of `ios/` and `backend/` (test code and design tokens
excluded). Columns: where it is, the value, what it governs, the tier it is in today, the tier
it should be in, and the consequence of the gap.

Legend for "today": **a** named constant · **b** inline literal · **c** remote key · **d** user
setting · **e** server option (bindable from environment / appsettings). Tier columns use C/R/U/F
from the table above. Values that match their spec doc are listed once and not argued about; the
review is about placement, duplication and disagreement.

**Transport - timeouts, retries, backoff**

| Where | Value | Governs | Today | Should be | Consequence of the gap |
|---|---|---|---|---|---|
| `ios/Transport/TransportTimeouts.swift` | readJSON **30 s**, upload **120 s**, resource **300 s** | Every API call in the app (per-request override on the two long paths) | a | C (matches U6; PR.6) | Fixed: a half-connected radio stops freezing a sign-in/sync/gateway call at the 60 s default. The `URLSession.shared` ban is enforced by a grep-gate test |
| `backend/src/Http/HttpClientTimeouts.cs` | RateFeed **30 s**, Jwks **15 s**, Apns **30 s** | Rate feeds, JWKS, APNs (each a named client) | a | C per named client (PR.6) | Fixed: a slow ECB/CBR feed no longer pins a job thread, and a slow JWKS fetch no longer stalls every sign-in behind it |
| `Extraction/Gateway/GatewayBudget.swift:20` | 3 s | UI wait before Confirm moves on | a | C (matches `API.md`) | Correct: it is a UX promise, not tuning |
| `Sync/SyncEngine.swift:57` | 3 | Conflict re-push attempts | a | C | Correct |
| `Config/ConfigStore.swift:109` | 5 | Failures before `apiBaseUrl` auto-revert | a | C (security control, never R) | Correct |
| `Config/ConfigStore.swift:208` | **no throttle** | `GET /config` cadence; `CONFIG.md` promises "once per 6 hours" | absent | C default + R override (`configPollInterval`) | Every foregrounding fetches: battery and data cost, and the doc is fiction (U9). **Gap, doc disagrees** |
| `Data/MigrationHostedService.cs:39,77` | 1 s, ×2, cap 30 s, 30 attempts | Startup migration backoff | a + b | C, all four named together | Two of four shape parameters are inline; harmless but unfindable |
| `Auth/AuthOptions.cs:43` | 30 s | Token clock-skew tolerance | e | C | Correct; must not be remote (S) |
| `Sync/SyncService.cs:31` | 24 h | Clamp on client `clientUpdatedAt` | a | C, and **state it in `SYNC.md`** | The one clock-skew defence in the protocol is undocumented (D7) |

**Cadences and retention windows**

| Where | Value | Governs | Today | Should be | Consequence |
|---|---|---|---|---|---|
| `Persistence/Repository.swift:53`, `DeletedEntries.swift:42`, `BlobOptions.cs:35`, `AccountOptions.cs:20`, `ImportOptions.cs:20` | 30 days, five definitions | Tombstone sweep, "N days left" copy, orphan blobs, account purge, import retention | a / e | C: **one** `RetentionPolicy.days` per tier, referenced by the four jobs and the copy; `SECURITY.md` is the authority | Five places to edit for one written promise; the server ones are env-bindable, so ops can silently break the "30 days" the app shows the user (§6 rule 3). **Gap** |
| `Auth/AuthOptions.cs:28,31` | 60 min / 90 days | Access / refresh lifetime | e | C with env override (ops need it for incident response) | Correct; matches `SECURITY.md` (~1 h) |
| `Rates/RateOptions.cs:20`, `Auth:40`, `Account:23`, `Import:23`, `NudgeOptions.cs:15` | 6 h, 6 h, 60 min, 60 min, 15 min | Server job cadences | e | e | Correct tier; operational |
| `Catalog/VehicleCatalogUpdater.swift:78` | 3600 s | Catalog refresh throttle | a | C default + R override | Fine today; when the catalog grows this is the number ops will want |
| `Config/ConfigBaselineSeeder.cs:21` vs client | 90 days | Config `notAfter` validity | a (server only) | C server; client honours the document | Correct, but `CONFIG.md:242` reads as if the client had a default - clarify |

**Meaning - consumption model, money, validation (must be C, may never be R)**

| Where | Value | Governs | Today | Should be | Consequence |
|---|---|---|---|---|---|
| `Consumption/ConsumptionEngine.swift:132,194`, `AnomalyEngine.swift:157-194` | 90 / 3 / 30 / 365 / 0.12 | Headline, cost/km, anomaly model | a | C, tested against D1-D4 | Correct |
| `Consumption/TrendsStats.swift:147` | `Double(90) * 86_400` | Trends pace window | **b** | reference `ConsumptionEngine`'s constant | If the window ever changes, Trends silently disagrees with Home (A6) |
| `Consumption/TrendsStats.swift:91,143` | 12 months | Chart span | b | C, named | Cosmetic; name it |
| `Domain/Entities.swift:55,79` | 1500 km/day | Implausible-pace guard | a, **literal on two lines** | C, one definition (the user may override the warning per entry - that is the U part, already there) | Duplicate literal |
| `Validation/DuplicateDetector.swift:104,107` | 30 min / 5 % | Duplicate rule (`SYNC.md:302`) | **b** | C, named | The only documented heuristic the user can trip that has no name in code |
| `Extraction/ConfirmPrefill.swift:47` and `FuelExtractor.swift:273` | `max(0.02, 0.5 %)` | CHECK 3 tolerance | a and **b duplicate** | C, one definition | Two tolerances for one invariant (hard rule 4) |
| `Extraction/CrossCheck.swift:185`, `FuelExtractor.swift:307` | 0.012 | Same-baseline band | b, twice | C, named once | Duplicate |
| `Extraction/FuelExtractor.swift:126-241`, `CrossCheck.swift:123`, `InvoiceSplitter`, `NumberScanner`, `CurrencyDetection` | ~15 geometry and heuristic literals (0.05, 0.03, 0.1, 0.02, 0.6, 0.25, ≤3 tokens, ≥2 corroborations, "16%" ...) | OCR layout heuristics | **b** | C, one `ExtractionTuning` struct with names, **pinned by the corpus gate** | These are the values the corpus will move; unnamed, each retune is archaeology (`EXTRACTION.md`). They are the R candidates of the future, but not yet: R without a corpus gate is tuning blind |
| `Config.default.json:9` `ocrConfidenceThreshold` 0.75 | R key | Documented as the dimming boundary | c, **no consumer** | Remove, or wire it | A live remote knob that does nothing: ops "retunes" and nothing changes (`CONFIG.md` disagrees with `ConfirmPrefill.swift:8-14`). **Doc disagrees** |
| `Extraction/ConfirmPrefill.swift:216` | year < 50 → 2000 | Two-digit-year pivot | b | C, named | A 2050 bug with a name is a bug you can grep |
| `Backup/ArchiveCrypto.swift:17-18` | 100 000 / 32 | PBKDF2 rounds, key size | a | C - **F** in effect (stored archives depend on it) | Correct; a change needs an archive version, note it in `SECURITY.md` |

**Limits and quotas (agreed across tiers)**

| Where | Value | Governs | Today | Should be | Consequence |
|---|---|---|---|---|---|
| `SyncEngine.swift:58-59` vs `SyncService.cs:28-29` | 200 / 500 | Push batch, pull page | a, **duplicated across tiers** | C both, **stated once in `API.md`**, L2 test that the client never exceeds the server cap | If the server is lowered by env, every push 413s and the client has no idea why (S9) |
| `AttachmentRendition.swift:19` vs `BlobOptions.cs:22` | 10 MB | PDF cap | a / e | same as above; user-facing error must name the number (§6 rule 2) | Duplicate; env-changeable on one side only |
| `GatewayRendition.swift:45` vs `LlmGatewayOptions.cs:20` | 4 MB | Extract envelope | a / e | same | Duplicate |
| `BlobOptions.cs:16,19`, `ImportOptions.cs:17` | 5 GB / 25 MB / 8 MB | Quota, image, import | e | e + **client-side pre-check with a named error** | The user learns the limit from a failure, not before it (U5) |
| `PayloadValidator.cs:18,19,56` | 256 KB / 64 / depth 128 | Envelope validation | a, a, **b** | C | Name the depth |
| `Config.default.json:8` `llmQuota{200,50}` vs `LlmGatewayOptions.cs:23-28` `{free 0, pro 200}` | two quota models | Client-shown vs server-enforced LLM quota | c / e, **unreconciled** | One model: server enforces, client displays what the server said (`/extract` 402/429 bodies) | The client can show "50 left" while the server says 0. **Bug in waiting** |
| `SyncSurface.swift:93` | 95 % | "quota full" surface | b | C, named | Cosmetic |
| `VehicleSelection.swift:36` `freeTierLimit` | 3 | Cars on free tier | a | **R** (it is the one monetisation number, and "no retroactive limit changes" needs a per-account floor, not a compile-time one) | Changing the free tier is a store release today |

**Endpoints, identity strings, defaults**

| Where | Value | Governs | Today | Should be | Consequence |
|---|---|---|---|---|---|
| nine `?? URL(string: "https://api.tankbook.live")!` sites in `ios/App/Sources` (`AppSync.swift:14,47`, `AccountDevicesService.swift:24`, `ManualFillUpCurrencySupport.swift:108`, `GatewayScanSession.swift:130`, `SignInFlow.swift:279,314`, `ImportService.swift:94`) plus `AppConfigService.swift:187` and `Config.default.json:5` | base URL | Fallback when config has no URL | **b ×9** | one `AppConfig.bundledBaseURL`; the fallback branch should not exist at all - the config layer already guarantees a base URL | Nine ways to bypass the `apiBaseUrl` guardrails (`CONFIG.md`); a region migration misses one. **Bug** |
| `Config.default.json`, `ConfigBaselineSeeder.cs:125-133`, `AppConfigService.swift:187-198` | the whole bundled config document | Bundled defaults | **three hand-kept copies**, one as C# string concatenation | one JSON fixture shared by the SwiftPM resource and the seeder, parity test | They will drift; the seeder's copy already differs in `version` |
| `Config.default.json:12` and `ConfigBaselineSeeder.cs:20` | `rolloutSalt` | Staged-rollout bucketing | c, duplicated in server code | server-authored only | Cosmetic, same root cause |
| `AppConfigService.swift:117,172` | `""` public key, `""` App Store id | Signature verification, update button | a (empty) | C, filled before release; **a release-blocker lint** | Every config signature "fails open to bundled" and the update button never renders. Known, but nothing fails a build for it |
| `HostAllowlist.swift:25-36` | comment "PLACEHOLDER, release blocker" | stale prose on a security control | - | delete the comment; `CONFIG.md` says closed 2026-08-28 | A reviewer trusts the comment |
| `Rates/EcbRateFeed.cs:17`, `CisRateFeed.cs:17` | feed URLs | Rate sources | a, not bindable | e | A feed moves host and it is a deploy, not a config change |
| `Catalog/LocaleCurrency.swift:12-25` | region → currency table, else EUR | Home-currency guess | a, user-overridable | C table + U value (correct) | Correct per hard rule 13 |
| `en_US_POSIX` at 12+ sites; `"yyyy-MM-dd"` twice in `RemoteRateFetcher.swift` | parse locale / wire date format | Parsing | b, widely duplicated | one `WireFormat` enum | A locale-bug fix has to be found twelve times |
| `ReminderNotification.swift:105-112`, `MonthlySummaryNotification.swift:106`, `ReminderLifecycle.swift:54,58` | 9:00, 10:00, 7 d, 12 d, 500 km | When reminders fire, what "due soon" means | a | **U** for the hours (a 9 am notification is a preference, `NOTIFICATIONS.md` permission timing), C for the windows | A user who wants reminders at 19:00 cannot have them (hard rule 13 for a derived time) |
| `PumpPhotoGate.swift:22-40` | 25 / 111 / 0.95 | Ship gate for pump photos | a | C, but the **comment disagrees with its own numbers** (says 21/84, 25 %) | Prose lies about a gate |
| `CaptureAlphaNotice.swift:68` | 3 | Alpha-notice retirement | a | C | Fine |
| `ToastCenter.swift:42`, 0.2 s easings at six sites, `CarSwitcherView.swift:218` height 340 | durations / detent | Motion | a / b | `Theme.generated.swift` motion tokens (`DESIGN.md`) | Motion is a design token by rule 5's spirit; six literals cannot honour reduce-motion uniformly |

**Secrets with committed defaults** (`LoggingOptions.cs:18` hash salt, `appsettings.Development.json` signing key, admin token, S3 and Postgres credentials): dev-only and overridden by the secret store per `SECURITY.md`. The one hardening worth doing: the salt default should make the server **refuse to start outside Development** rather than run with `change-me`.

### 6.2 · What the inventory says in one paragraph

The meaning-class constants (consumption, money, validation, crypto) are named, tested and in
the right tier - the design held where it mattered most. The gaps are all of one shape:
**operational values that were never given a home**. Transport has no timeouts at all; the
config poll has no cadence; the 30-day promise is defined five times; the two tiers each keep
their own copy of every shared limit; the base URL fallback is pasted nine times around the one
layer built to own it; and the OCR heuristics are ~15 anonymous decimals in the code the corpus
will most want to retune. Nothing here loses data today. Every one of them is a release where a
config edit should have been enough, or a frozen screen where a short timeout should have been.
The task list in §7 turns each row into a change.

## 7 · Review of the current implementation

Reviewed 2026-08-29 against the tree at `93d2619` by four read-only passes (one per area,
brief `agents/briefs/REVIEW-PRACTICES.md`); every MISSING and every headline PARTIAL below was
re-verified by hand with a grep or a read before it was written here. The per-row verdicts are
first, the consolidated task list second. Task ids `PR.n` are stable and mirrored in
`docs/TASKS.md` -> "PR · Practices review".

### 7.1 · Verdicts

**Architecture**

| Row | Verdict | Evidence |
|---|---|---|
| A1 | MET | `Sync/SyncEngine.swift:30-120`; server stores opaque records `Sync/SyncRepository.cs:46-59`. Caveat: production wires `InMemorySyncPayloadMemory` (`App/Settings/AppSync.swift:33`), so field-level Vehicle merge degrades to "every field changed" after each relaunch - PR.4 |
| A2 | PARTIAL | `426` and `appUpdate` exist; **no request carries app version or build** (`Config/TankbookHTTPClient.swift:134-140` adds only `Authorization`), the server's `appVersion` log field is its own assembly version, and the live config fetcher is `nil` (`App/Config/AppConfigService.swift:80`) - PR.3, PR.8 |
| A3 | PARTIAL | Push idempotent by id + `baseScn` (`SyncRepository.cs:105-161`), blob commit and account delete replay-safe. `POST /import/parse`, `/auth/session` device registration and `/extract` metering accept no idempotency key - PR.25 |
| A4 | MET | `Sync/PayloadValidator.cs:22-80`; the one exception isolated in `Import/MfmParser.cs` |
| A5 | PARTIAL | Server migrations ledgered and transactional; device migrations additive. **No backup copy before migrate, no downgrade detection**, no test over an exported real DB (`App/Persistence/AppStore.swift:50-58`, `Persistence/Database.swift:17-25`) - PR.15 |
| A6 | MET | No aggregate columns (`Persistence/Migrations.swift:69-107`); all stats computed on read |

**UX under a network**

| Row | Verdict | Evidence |
|---|---|---|
| U1 | MET | Launch and foreground work runs in `.task` after first draw (`App/Navigation/TabRoots.swift:172-215`); gateway 3 s budget never blocks the sheet |
| U2 | MET | Dirty-row model, transport failure returns rows to dirty (`SyncEngine.swift:112-115`) |
| U3 | PARTIAL | Conflict badge on the row exists; the "Changed by sync" row is a fixture behind `-forceChangedBySync` (`App/EditEntry/EditEntryRows.swift:68-76`) and the `syncOverwrite` table is written but never read by a view; the S7 "N entries need a look" toast has no producer - PR.14 |
| U4 | PARTIAL | 410/426/402/429 distinguished. **Offline and 5xx are one flag** (`SyncEngine.swift:88,113`) though `ERRORS.md:152-153` prescribes two rows; **a 401 falls into `400...499` and is shown as "the server has moved ahead - update the app"** (`Sync/RemoteSyncTransport.swift:68-71`), an untrue next step - PR.1, PR.13 |
| U5 | MET for what exists; the U4 401 case names a wrong step |
| U6 | **MET** | `ios/Transport/TransportTimeouts.swift` (readJSON 30 s, upload 120 s, resource 300 s) builds the app's own `URLSession` (`Auth/URLSessionTransport.swift`, `URLSession.shared` banned by a grep-gate test); blob PUT (`Sync/RemoteBlobTransport.swift`) and import multipart (`Import/ImportClient.swift`) ask for the upload budget via the `TankbookHTTPRequest.timeoutInterval` override; backend `Http/HttpClientTimeouts.cs` names RateFeed/Jwks/Apns clients; Cancel on the import parse (`ImportFlowModel.cancelParse`) and the restore progress (`SignInFlow.cancelRestore`) - PR.6 |
| U7 | **MISSING** | No retry or backoff on the client; `Retry-After` is decoded and *displayed* ("Retrying in N minutes", `Sync/SyncServerNotice.swift:61`) but nothing schedules the retry; the one silent `/extract` retry in `API.md:316` is not implemented; `CONFIG.md`'s 6 h config throttle does not exist - PR.7 |
| U8 | **MISSING** | `RemoteAuthService.refresh` (`Auth/AuthService.swift:88`) has **no production caller** - the only call is `App/SignIn/SignInTestSeed.swift:79`; no 401 interception in `TankbookHTTPClient`. **Every signed-in install stops syncing about 60 min after sign-in** and is told to update the app - PR.1 |
| U9 | PARTIAL | Low Power deferral and batching exist (`Power/PowerState.swift`, `Sync/SyncCoordinator.swift:74-79`). No debounced sync after writes (`SYNC.md:121`), no APNs registration or push-token PUT, so the server's nudges reach no device; no Low Data Mode handling - PR.20 |
| U10 | MET | Client renders by status, never `detail`; copy from the String Catalog |
| U11 | PARTIAL | Allowlist, health gate, auto-revert and signature floor are built; **none of it is live**: `fetcher: nil`, no prober, empty public key, and the transports build their base URL from a hardcoded fallback rather than `ConfigStore.current` (nine `?? URL(string: "https://api.tankbook.live")!` sites) so `recordTransportOutcome` never counts - PR.3 |
| U12 | MET | Defaults editable at offer and afterwards; field-level merge protects user edits; gateway late answer fills blanks only |

**Security**

| Row | Verdict | Evidence |
|---|---|---|
| S1 | PARTIAL | No secret in `ios/`; dev values only in `appsettings.Development.json`. The CI bundle scan and no-secrets-committed check `SECURITY.md` names as enforcement do not exist in either workflow - PR.19 |
| S2 | MET | Keychain classes correct and tested (`Auth/KeychainSessionStore.swift:30,95`, `KeychainSessionStoreTests`). **PR.16 closed the file-protection gap**: `AppStore.makeRepository` sets `completeUntilFirstUserAuthentication` on the database triple after open, `VehiclePhotoStore.attachmentsDirectory` sets it on the attachments directory (invoice pages and `FileBackedBlobStore` share that pool; `FileBackedBlobStore.save` sets it on its own directory, iOS-only), and the app-target `TankbookTests/FileProtectionTests` (L2) asserts the class on all three database files and a written attachment in the app's real container. The `VehiclePhotoStore` backup comment is corrected: attachments are user data and stay in device backups like the database - only the regenerable caches are excluded |
| S3 | PARTIAL, **bug** | Server rotates, detects reuse, revokes on logout (`Auth/AuthService.cs:128-178`). **The client never refreshes and never revokes**: every sign-out path clears the Keychain only, leaving a 90-day refresh chain valid server-side - PR.1, PR.2 |
| S4 | MET | Both redactors are single enforcement points and tested. PR.5 closed the one hole: the app logs through one `TankbookLog` facade (`AppLog`), the 41 `.public` sites spread across 19 raw `os.Logger` instances are replaced by the typed `app.error`/`app.warning` events with `errorDescription` classified Sensitive, the backend routes `exceptionMessage`/`stackTrace` through its redactor, and the SwiftLint rule `no_raw_os_logger` forbids `Logger(subsystem:` outside `Logging/`. |
| S5 | MET | No ATS exception, no pinning, HTTPS enforced by the allowlist |
| S6 | MET | No detection code; stance written |
| S7 | PARTIAL | Server serialises with `FOR UPDATE`. Client has no refresh (S3); four independent `TankbookHTTPClient` owners would race once it exists unless refresh is one shared actor - PR.1 |
| S8 | MET | `devices` table, per-sign-in row, signed-out import attributed to `X-Device-Id`. Hardening: the signed-out device id lives in `UserDefaults` and migrates with backups - PR.29 |
| S9 | PARTIAL | Size limits and schema-before-write are real and tested. **No rate limiting exists** (`grep RateLimiter backend/src` -> 0) though `API.md:5,198` promise it; quota 429s carry no `Retry-After`; no explicit Kestrel body cap, and the 30 MB default is below a maximal legal push batch (200 x 256 KB) - PR.17 |
| S10 | PARTIAL | Never proxied; ownership checked before minting. The presigned PUT binds **no content type and no length** (`Blobs/S3BlobStorage.cs:49-60`), and the orphan sweep that would clean a mismatch is implemented but **never scheduled** - PR.18 |
| S11 | PARTIAL | Import purge and account purge run on hosted services; blob orphan sweep unscheduled - PR.18 |
| S12 | MET | Tombstone + revoke + cascaded purge, tested across three suites |
| S13 | MET | `SECURITY.md` threat model |

**Debuggability**

| Row | Verdict | Evidence |
|---|---|---|
| D1 | PARTIAL | Server reads/echoes the header and puts `traceId` in every problem body including the 500 path (`Logging/TraceCorrelationMiddleware.cs:28-40`, `Program.cs:85-94`). **The client never sends `X-Tankbook-Trace`** (0 occurrences outside tests) and never reads `traceId` from a failed body; `accountHash`/`deviceId` are never pushed into the server scope so every line has them null - PR.8 |
| D2 | MET | Typed fields and redactors on both tiers; the app logs through the facade (`AppLog`) and the SwiftLint rule `no_raw_os_logger` forbids a raw `Logger(subsystem:` outside `Logging/` (PR.5) |
| D3 | PARTIAL | `Logging/DiagnosticsExport.swift` assembles and redacts a bundle; **no UI exists** on About (`App/Settings/AboutView.swift:48-65`), nothing reads `OSLogStore`, and the bundle carries no sync state or DB stats - PR.11 |
| D4 | PARTIAL | Per-item push results carry stable codes. **Top-level `problem+json` has no `code` member** by spec and by code; the client maps HTTP status to an enum, so two different 401s or 400s are indistinguishable - PR.9 |
| D5 | PARTIAL | Settings shows age, pending and flagged counts. Last success and last error are **in-memory only** (`Sync/SyncCoordinator.swift:23-36`): after relaunch the row cannot say "synced 3 hours ago" and the last failure vanishes while the queue stays - PR.12 |
| D6 | PARTIAL | Seeds, `-presentScreen`, network cut on seeded launches exist. **No frozen clock** (seeds derive from `Date()`), and no way to load an exported archive into the simulator although the reader exists in core - PR.26 |
| D7 | **MISSING** | Every event is defined (`Logging/LogEvents.swift:162-310`) and **none has a call site** (0 outside `Logging/` and tests): no cycle, merge, queue, request, mutation pair, background-expiry, path-change or clock-skew line is ever written on the device - PR.10 |
| D8 | PARTIAL | Server tallies push outcomes and extract results. iOS emits nothing (D7); the "pre-fill overwritten by the user" feed `EXTRACTION.md:27` relies on does not exist - PR.10 |
| D9 | PARTIAL | Redaction by catalog, request line with route + status + duration. No slow-query log; error rate cannot be keyed by client version because none is sent (A2) - PR.8, PR.27 |
| D10 | PARTIAL | Policy written; screenshots carry no runtime in name or manifest, and no snapshot baselines exist to diff - PR.28 |

`docs/TASKS.md` row **P0.11** is marked done with "X-Tankbook-Trace correlation end to end" and
"every mutation path emits begin + ok/fail"; the client half of both was never wired. The row is
footnoted to PR.8 and PR.10 rather than reopened, so the history stays honest.

### 7.2 · The picture in three sentences

The parts that were designed as invariants - local-first storage, schema-only validation, derived
stats, money pairs, the redactors, the Keychain classes, the threat model - are built and hold.
The parts that connect the two tiers at runtime were built on the core side and **never plugged
in on the app side**: no token refresh, no live config, no trace header, no log events, no
timeouts, no retries. The result is a product that works perfectly offline and quietly stops
working an hour after the first sign-in, with nothing on either tier able to say why.

### 7.3 · Task list

Consolidated across the four areas and §6 (duplicates merged; the area-local ids from the agent
reports are not used). Ordered by severity, then by how much each unblocks. Rows are mirrored in
`docs/TASKS.md` with their checks; the checks here are abbreviated.

**Bugs - a hard rule is violated or a user loses time or data**

| Id | Deliverable | Why now |
|---|---|---|
| PR.1 | **Client token refresh**: one shared `SessionRefresher` actor used by every `TankbookHTTPClient` owner; on 401 refresh once (single in-flight task, concurrent callers await it), persist the rotated pair, replay the request; on refresh failure surface `authExpired` -> a Settings card "Sign in again", never "update the app"; remove `.refused(status: 401)` from sync, gateway, account and blob transports | Every account stops syncing ~60 min after sign-in with a false next step (U8, S3, S7, hard rule 7) |
| PR.2 | **Sign-out revokes server-side**: every sign-out path calls `DELETE /auth/session` best-effort, then clears the Keychain even offline; an explicit Sign out in Settings | A handed-over phone keeps a 90-day refresh chain (S3) |
| PR.3 | **Make the config layer live**: `ConfigFetcher` over `TankbookHTTPClient` (`GET /v1/config`, ETag, a named 6 h throttle with remote override), `HealthProber`, bundled Ed25519 public key; every transport takes `apiBaseURL` from `ConfigStore.current` per operation and reports to `recordTransportOutcome`; **delete the nine `?? URL(string: "https://api.tankbook.live")!` fallbacks** and the `AppConfigService.swift:187-198` copy of the defaults | Kill switches, quotas, `appUpdate` and region migration are unreachable without a release; nine bypasses of the `apiBaseUrl` guardrails (U11, §6) |
| PR.4 | **Persist `SyncPayloadMemory`** (column or side table on `vehicle`) and wire it in `AppSync.swift:33` | S9 field-level merge degrades on every relaunch; a stale device can revert a user's edit (hard rule 13) |
| PR.5 | **App logging through the facade**: one app-wide `TankbookLog`, the forty `os.Logger` sites replaced with typed events, `error.localizedDescription` classified Sensitive, backend `exceptionMessage` through the redactor; a SwiftLint custom rule forbidding `Logger(subsystem:` outside `Logging/` | Hard rule 12 is upheld by a GRDB default, not by our code (S4, D2) |

**Gaps - the docs promise it, the code lacks it**

| Id | Deliverable | Why |
|---|---|---|
| PR.6 | **Transport timeouts named once per tier**: `TransportTimeouts` (connect ~8 s, read 30 s JSON, longer for blob PUT / import multipart) building the app's own `URLSession`; per-request override on `TankbookHTTPRequest`; named `HttpClient` timeouts for rate feeds, JWKS, APNs; Cancel on the Import and Restore progress surfaces | 60 s frozen "Sync now", "Import", "Sign in" on a half-connected radio (U6) |
| PR.7 | **Client retry policy**: jittered exponential backoff (cap ~5 min) in `SyncCoordinator` for the unavailable class, honouring `Retry-After`; the one silent `/extract` retry from `API.md:316`; retry only idempotent calls | The notice promises a retry that never happens; lockstep retries after an outage (U7) |
| PR.8 | **Trace and client version on the wire**: `X-Tankbook-Trace` (UUIDv7) and `X-Tankbook-App: <version>+<build>` + platform on every request; on non-2xx the client reads `traceId` from the body onto the thrown error; server pushes `clientVersion`, `accountHash`, `deviceId`, `schemaVersion` into the log scope and renames its own field `serverVersion`; bundle version `1.0.0` so `AppVersion` parses | Support cannot map a report to a server line; a bad build cannot be found by version; the `appUpdate` gate can never fire (D1, D9, A2) |
| PR.9 | **Error codes on the wire**: `API.md` envelope gains `code`; `TankbookErrorCodes` extended for auth, blobs, import, account, config; every `Results.Problem` sets it; client maps `code -> L10n string + next step`, status as fallback | Distinct failures collapse into one status and one generic string (D4, hard rule 7) |
| PR.10 | **Emit the defined log events and the async edges**: `DataMutationLogger` around repository writes, `SyncCycleBegin/End`, `SyncMerge`, `SyncQueue`, `NetRequest/Response`, `CapturePipeline(userCorrected:)`; `app.lifecycle` on scene phase, `beginBackgroundTask` with an expiry event around push/upload, `NWPathMonitor` path-change event aborting an in-flight blob upload, `sync.clock.skew` client-side and a `clamped` count on the server push line | Nothing the device does is observable in the field (D7, D8) |
| PR.11 | **Diagnostics export end to end**: "Attach diagnostics" on About/feedback, last 24 h via `OSLogStore` plus the breadcrumb ring, sync state and DB row counts in the bundle, a preview screen, share sheet; EN+RU screenshots | The interesting bugs never crash; today the user can send only a version string (D3) |
| PR.12 | **Persist last sync date and last failure** (timestamp, class, code, traceId) and restore them into the coordinator; Settings shows "Synced N hours ago" after relaunch | "Is it synced?" is unanswerable after a relaunch (D5) |
| PR.13 | **Split offline from server-unavailable** in `SyncOutcome`; `SyncSurface` renders the two `ERRORS.md:152-153` rows | Offline and an outage read identically; the "Try again" step is missing (U4) |
| PR.14 | **Real "Changed by sync" row** from the `syncOverwrite` log (device, date, "Restore my version") and the post-batch "N entries need a look" toast; delete the `-forceChangedBySync` fixture | Overwrites are stored but invisible where the data lives (U3, hard rule 8) |
| PR.15 | **Device migration safety**: copy `.sqlite` + `-wal` + `-shm` aside before pending migrations, delete on success, restore on throw; refuse to open a DB carrying unknown migrations with an `ERRORS.md` row; a test migrating a committed exported real-DB fixture through every version | A failing migration on an old DB is unrecoverable; a downgrade opens a newer schema blind (A5) |
| PR.16 | **File protection set explicitly** on the database triple and every attachment directory; the promised file-protection test; fix the `VehiclePhotoStore` comment or implement `isExcludedFromBackup` | The `SECURITY.md` promise rests on a platform default (S2) |
| PR.17 | **Rate limiting and body caps**: ASP.NET `RateLimiter` per IP on `/auth/*`, `/import/parse`, `/catalog/publish`; per device on `/extract`, `/sync/push`, `/blobs/begin`; `Retry-After` on every 429; explicit `MaxRequestBodySize` per endpoint written into `API.md`; client caps a push batch by bytes | `API.md` promises limits that do not exist; a maximal legal push batch exceeds the Kestrel default (S9) |
| PR.18 | **Presigned PUT bound to declared content type and length**; schedule `SweepOrphansAsync` + `DeleteStalePendingAsync` hourly | Any bytes of any size for 15 min, then never cleaned (S10, S11) |
| PR.19 | **CI secret scans**: `appsettings*` placeholder check in `backend.yml`; `strings` over the built `.app` in `ios.yml` failing on key prefixes / high entropy | Named as enforcement in `SECURITY.md`, absent (S1) |
| PR.20 | **Debounced sync after local writes** (~5 s trailing), APNs registration + push-token PUT with silent push -> opportunistic sync, `allowsConstrainedNetworkAccess = false` for blob uploads | Other devices learn nothing until foregrounded; the server's nudges reach no device (U9) |
| PR.21 | **One retention constant per tier** (`RetentionPolicy.days`) referenced by the tombstone sweep, "N days left" copy, orphan sweep, account purge and import purge; server value asserted equal to the `SECURITY.md` number at startup | Five definitions of one written promise; env can silently change what the app tells the user (§6) |
| PR.22 | **Shared limits stated once**: batch 200 / page 500 / PDF 10 MB / envelope 4 MB / image 25 MB / import 8 MB in `API.md`, parity test on both tiers; client pre-checks with an error naming the number; **reconcile the two LLM quota models** so the client displays what the server enforces | Server lowered by env -> every push 413s and the client cannot say why; the client can show "50 left" while the server says 0 (§6) |
| PR.23 | **Bundled config as one fixture** consumed by the SwiftPM resource and `ConfigBaselineSeeder`, with a byte-parity test | Three hand-kept copies already differ (§6) |
| PR.24 | **`ExtractionTuning`**: name the ~15 OCR geometry and heuristic literals, dedupe the CHECK 3 tolerance and the 0.012 baseline band, pin the struct in the corpus gate; **decide `ocrConfidenceThreshold`** - wire it or delete the remote key and the `CONFIG.md` row | The values the corpus will move are anonymous; a live remote knob does nothing (§6) |

**Hardening - good practice, not promised**

| Id | Deliverable |
|---|---|
| PR.25 | `Idempotency-Key` on `POST /import/parse`, `/auth/session` device registration and `/extract` metering; server replays the stored response within the retention window |
| PR.26 | `-frozenNow <ISO8601>` feeding one injected clock (seeds, config, relative labels, monthly summary; screenshots pass it) and `-loadArchive <path>` (DEBUG) running `Repository+ArchiveImport` before first draw |
| PR.27 | Slow-query log: Npgsql command timing above a named threshold at WARN, route + duration + command name, never parameters |
| PR.28 | `design/screenshots/manifest.json` with runtime, device and commit per PNG; CI fails a PNG without an entry |
| PR.29 | Signed-out import device id moved from `UserDefaults` to a `ThisDeviceOnly` Keychain item and listed in `SECURITY.md` |
| PR.30 | Reminder fire hours (9:00, 10:00) become a user setting per `NOTIFICATIONS.md`; the windows (7 d, 12 d, 500 km) stay compiled |
| PR.31 | `freeTierLimit` served by config with a per-account floor so "no retroactive limit changes" is enforceable |
| PR.32 | Stale prose on live controls: `HostAllowlist.swift:25-36` placeholder comment, `PumpPhotoGate.swift:22-29` numbers, `CONFIG.md:134` throttle claim and `:242` validity wording, the 24 h clock clamp written into `SYNC.md`, the P0.11 footnote |
| PR.33 | Name the remaining literals: `TrendsStats` 90-day window referencing the engine's constant, `paceLimitKmPerDay` once, duplicate rule 30 min / 5 %, two-digit-year pivot, `WireFormat` for `en_US_POSIX` and `yyyy-MM-dd`, motion durations as `DESIGN.md` tokens |
| PR.34 | Server refuses to start outside Development with the `change-me` hash salt or an empty config signing key |
