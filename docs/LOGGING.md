# Tankbook – Logging & Observability

*What both tiers log, what they must never log, and how a single user problem is traced end to end. Companion to `ERRORS.md` (what the user sees), `API.md` (the wire contract), `SYNC.md` (the privacy stance), `SCHEMA.md` (entity names).*

The governing tension: we promise **"no analytics on your data"** and a server that never interprets domain content. Logging must therefore be rich enough to debug a failed sync at 2am and poor enough that a leaked log file reveals nothing about where someone drove, what they paid, or what their car is. Every rule below serves that line.

## 1 · Privacy classification (applies to both tiers)

Every value is one of three classes. When in doubt, downgrade.

| Class | Examples | Rule |
|---|---|---|
| **Safe** | entity ids (UUIDs), entityType, schemaVersion, SCN, counts, byte sizes, durations, HTTP status, error codes, JSON pointers, sha256 hashes, device/app version, platform | Log freely, at any level |

**Testing the Never rule: do not sweep the clock.** The tests that prove a domain value never
reached a log line do it by substring search over the rendered output, and two Safe fields are
**free-running numbers that can spell the value being searched for**: `timestamp` renders seconds
as `SS.mmm`, so `...:42.317Z` contains `42.3`; and `DurationMs` is `TimeSpan.TotalMilliseconds`,
so a 9.87-second request renders `9876.5432` and contains `9876.54`. Both are real needles in the
current suite, and the timestamp one has already produced a red run. Sweep through
`WithoutMachineFields()` (`LoggingTestHelpers`), which blanks exactly those two - never by
loosening the assertion, and never by changing the needle, because the next needle would have the
same problem. **Identifiers stay in the sweep on purpose**: `traceId`, `deviceId` and
`accountHash` are also machine-generated, but leaving them means a domain value wrongly routed
into one is still caught.
| **Sensitive** | station and vendor names, notes, plate, monetary amounts, volumes, odometer, coordinates, filenames, email | **Never logged in production.** Debug builds may log them behind an explicit opt-in flag; they are never written to a file that leaves the device |
| **Never** | payload bodies (`records.payload`), blob bytes, images, OCR text, auth tokens, refresh tokens, presigned URLs, API keys, passwords | Never logged at any level, in any build. Redact at the logger, not at the call site |

Two structural helps: the server *cannot* accidentally log domain fields because it never parses `payload` – the rule is simply **never log `payload`**; and on iOS, OSLog interpolation is `.private` by default, so a field only becomes visible if someone deliberately marks it `.public`.

**Email** is logged as a stable salted hash (`acct_9f2c…`), never plaintext – enough to correlate a support request, useless in a leak.

## 2 · Correlation: one thread through both tiers

- The **client generates a `traceId`** (UUIDv7) per API request and sends it as `X-Tankbook-Trace`.
- The **server echoes it** in every log line for that request, in the `X-Tankbook-Trace` response header on success, and in the `problem+json` body of any error. Known behaviour: on an unhandled 500 the framework's exception handler calls `Response.Clear()`, which wipes the response header – so on that path the body is the only carrier. Clients must read the traceId from the body when a request fails.
- A **`syncSessionId`** groups one pull→merge→push cycle across many requests.
- The user-visible surface: when an error is shown from a failed request, the diagnostics bundle (§5) carries its traceId. A support message therefore maps to exact server lines without the user describing anything.

Every log line on both tiers carries: `timestamp, level, event, traceId?, accountHash?, deviceId?, appVersion, platform`.

## 3 · Backend (ASP.NET Core, structured JSON to stdout)

Serilog (or `Microsoft.Extensions.Logging` with a JSON formatter) writing **one JSON object per line**. Human-readable console only in Development.

### Always, per request (one line)
`method, path (route template, not the raw URL – ids stay out of paths in logs), status, durationMs, traceId, accountHash, deviceId, appVersion, schemaVersion, requestBytes, responseBytes`

### Per operation – the "who / what / changed / outcome" record

| Event | Fields (all Safe class) |
|---|---|
| `auth.session` | provider (apple/google), outcome (created/matched/rejected), failureReason (invalid_signature / expired / clock_skew / revoked), accountHash on success. **Never the token.** |
| `auth.refresh` | outcome, rotation id, `reuse_detected: true` when a rotated token is replayed – this one is a **security event**, log at WARN and include deviceId |
| `sync.push` | batchSize, accepted, conflicts, rejected, `assignedScnRange: [from,to]`, durationMs; and a compact per-item array of `{id, entityType, schemaVersion, outcome, errorCode?, pointer?}` – **ids and outcomes, never values** |
| `sync.pull` | sinceScn, returned, nextSince, more, durationMs |
| `sync.nudge` | accountId, candidates, delivered, invalidToken, transient, throttled, config, durationMs – counts and outcome only; **never the push token** (a Never credential) |
| `blob.begin` / `blob.commit` | sha256, sizeBytes, contentType, `dedupe: hit\|miss`, quotaUsedPct |
| `blob.get` | sha256, `presignTtlSec` – never the signed URL |
| `llm.extract` | kind, quotaBefore/After, model, durationMs, outcome. **Never the image, never the extracted values.** |
| `migration.ddl` | version, direction, durationMs |
| `migration.payload` | entityType, fromVersion→toVersion, rowsScanned, rowsRewritten, batches, durationMs |
| `account.delete` | accountHash, recordsPurged, blobsPurged, graceEndsAt |

**What changed** is expressed as identity + outcome (`id`, `entityType`, `schema_version`, old→new `scn`), never as a value diff. A record's history is already in the stream; the log's job is to say *that* it changed and whether it succeeded.

### Errors
Every ERROR line carries: `errorCode` (the stable code from API.md), `exceptionType`, `message`, `stackTrace`, `traceId`, plus **safe reproduction context**: which endpoint, which entity id, which schemaVersion, payload *size*, and for validation failures the **JSON pointer** to the offending field (the pointer names the field, never its value). That is the set that lets an engineer reproduce without seeing the data.

Level discipline: `ERROR` = the request failed or data integrity is at risk. `WARN` = handled degradation (retry, conflict, quota exceeded, refresh-reuse). `INFO` = the per-request and per-operation lines above. `DEBUG` = development only, never enabled in production.

Health, readiness and metrics endpoints log at DEBUG only – they would otherwise drown the stream.

## 4 · iOS (OSLog / `Logger`)

Subsystem `live.belyaev.tankbook`; categories: `sync`, `persistence`, `capture`, `notifications`, `ui`, `auth`. OSLog gives level-based persistence, redaction by default, and Console.app/`log collect` access without shipping a logging SDK.

### Requests and their results (mirrors the backend)
`net.request` – endpoint (route template), method, traceId, attempt number; `net.response` – status, durationMs, retryAfter, and on failure the `errorCode` + whether it will be retried. Backoff decisions are logged so a "sync seems stuck" report is explicable.

### Local mutations – the "attempt → outcome" pair the user asked for
Every create / update / delete logs **twice**: an intent and an outcome, so a crash between them is itself diagnostic.

| Event | Fields |
|---|---|
| `data.mutate.begin` | op (create/update/delete/restore), entityType, entityId, source (capture/manual/import/sync-merge/reminder) |
| `data.mutate.ok` | same + durationMs, `fieldsChanged: ["odometer","volumeL"]` – **field *names* only, never values** |
| `data.mutate.fail` | same + errorCode, errorDomain, underlyingError, and whether the write was rolled back |
| `data.validate` | entityId, result (ok / flagged), conflictKind (order/pace), crossCheck (verified/mismatch + which field) |
| `data.recompute` | vehicleId, segmentsBefore/After, durationMs – catches the "stats look wrong" class of bug |

### Sync client
`sync.cycle.begin/end` (syncSessionId, trigger: foreground/write/nudge), `sync.merge` (records applied, conflicts by **scenario** – `S1`…`S8` from SYNC.md, which makes conflict behaviour directly observable in the field), `sync.queue` (dirty count, oldest dirty age – the number behind Settings' "Waiting to sync · N changes").

### Capture / OCR
`capture.pipeline` – pipeline id (`vision+rules v3` / `fiscal-qr` / `cloud-fallback v1`), durationMs, per-field **confidence values and field names, never the extracted values**, crossCheck outcome, whether the user corrected a field afterwards. This is the feed for the L5 accuracy ratchet in `TESTING.md` – and it is aggregate-safe by construction.

### Errors
Every failure logs the typed error, its `underlyingError`, the operation in flight, the entity id, and the traceId when it came from a request. iOS additionally records a **breadcrumb ring** (last ~50 events, in memory) attached to crash reports and to diagnostics exports.

## 5 · Diagnostics the user can send

`ERRORS.md`/About already offers "attach app version and device model (no log data)" on the feedback form. This spec adds one more explicit, opt-in step: **"Attach diagnostics"** collects the last 24h of `INFO`+ OSLog entries for our subsystem, runs them through the redactor, and shows the user a **preview of exactly what will be sent** before sending. Never silent, never automatic, never on by default. The bundle carries traceIds, so support can find the matching server lines.

## 6 · Retention, access, and what we do not build

- Server logs: 30 days hot, then dropped. No log warehouse, no per-user analytics store, no third-party analytics SDK in the app.
- Crash reporting: Sentry is acceptable for crashes and errors **with payload/PII scrubbing configured before first use**; breadcrumbs follow the same three classes.
- Access to production logs is limited and audited; a support lookup is by `accountHash` or `traceId`, never by browsing content.
- **We never log to reconstruct behaviour.** Counting how often capture succeeds is legitimate; recording where someone fuels is not. If a proposed log line would still be interesting to someone who wanted to profile the user, it does not ship.

## 7 · Test the rules, don't just state them

- **Redaction test (both tiers):** feed a fully populated entity through the log path and assert that no Sensitive/Never value appears in the output. This is the regression that keeps the promise true as code grows.
- **Correlation test:** a client request's traceId appears in the server's request line, its operation line, and the problem+json error body.
- **Mutation-pair test:** every mutation path emits both `begin` and a terminal `ok`/`fail`; a deliberately failing write produces `fail` with a populated errorCode.
- **Level discipline test:** no `INFO`+ logging inside per-row loops (assert log count is O(1) per sync batch, not O(n) per record).
