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

**Email** is Sensitive and never logged plaintext. If one reaches the pipeline with no account context – a stray `Email` property on a logged object – the redactor masks it as a **salted `emailHash`** (`acct_9f2c…`) under its *own* key. That mask is deliberately **not** the account identifier: the redactor has no account id to hash, only the address, so an email-derived value can never join a support lookup. It is therefore never written under `accountHash`, which means the salted hash of the **account id** (§2). Before RV.63 an email hash and an account-id hash both answered to `accountHash`, so two lines about one account did not join – one log field carried two values that could not be compared.

## 2 · Correlation: one thread through both tiers

- The **client generates a `traceId`** (UUIDv7) per API request and sends it as `X-Tankbook-Trace`. One id per **logical** request: redirect hops and a 401-refresh replay keep the same id, two calls never share one. The client stamps the header (and the app headers below) at the single chokepoint inside `TankbookHTTPClient`, so no owner can miss it.
- Every request also carries **`X-Tankbook-App: <version>+<build>`** (marketing version + `CFBundleVersion`, `1.0.0+1` today), **`X-Tankbook-Platform`** (`ios`) and **`X-Tankbook-Schema-Version`** (the client's payload contract version). A support report therefore says which build produced the line.
- The **server echoes the traceId** in every log line for that request, in the `X-Tankbook-Trace` response header on success, and in the `problem+json` body of any error. Known behaviour: on an unhandled 500 the framework's exception handler calls `Response.Clear()`, which wipes the response header – so on that path the body is the only carrier. **On a non-2xx the client reads the `traceId` from the body onto the thrown error**, so the error handler (and the diagnostics bundle) always has it. The server's own fallback when the header is absent is also a UUIDv7.
- The server **pushes `clientVersion`, `clientPlatform`, `accountHash`, `deviceId`, `schemaVersion` into the log scope** for every request (PR.8): `clientVersion`/`clientPlatform`/`schemaVersion` come from the headers above, `deviceId` from the bearer token. **`accountHash` is the salted hash of the account id – and it is the one identifier for one account everywhere an account is resolved (RV.63).** The JWT carries the account id, not the email, so the scope hash is over that; `auth.session` and `account.delete` hash the **same account id** now that the account is resolved at the point they log. One account therefore logs one value under `accountHash` on every line that names it, and any two lines about the same account join – the `auth.session` of a sign-in and the `sync.push` that follows it included. (Before RV.63 the session line hashed the email instead, so the same device logged two hashes of one account and a support lookup could not join them.) Public routes carry the client fields and leave `accountHash`/`deviceId` null; an email that reaches a payload with no account context is masked under the distinct `emailHash` key, never `accountHash` (§1).
- The server's own version field is **`serverVersion`**, and its platform is `server` – distinct from the client's `clientVersion`/`clientPlatform`, so a line says both who served it and what called it.
- A **`syncSessionId`** groups one pull→merge→push cycle across many requests.
- The user-visible surface: when an error is shown from a failed request, the diagnostics bundle (§5) carries its traceId. A support message therefore maps to exact server lines without the user describing anything.

Every log line on both tiers carries: `timestamp, level, event, traceId?, accountHash?, deviceId?, clientVersion?, clientPlatform?, serverVersion, schemaVersion?, platform`.

## 3 · Backend (ASP.NET Core, structured JSON to stdout)

`Microsoft.Extensions.Logging` through `LogRenderer`, which emits either **one JSON object per line** or a human-readable line, selected by `Tankbook:Logging:Format` (`json` | `text`). The default is `text` in Development and `json` elsewhere.

**The per-request line is levelled by OUTCOME (changed 2026-09-02).** §3's rule was one
`http.request` line at Information for every request. In production that buried the lines that say
what actually *happened* - `auth.session`, `sync.push`, `blob.commit`, `llm.extract` - under one
`http.request` per call, several per screen; a log nobody can read is not observability. So a
**successful** request is `Debug`, a **4xx** is `Information`, and a **5xx** is `Warning`. `/health`
stays `Debug` as before.

**`auth.refresh` carries `ChainId`, not `RotationId` (renamed 2026-09-03, RV.27).** The value is the refresh-token **family** id and is deliberately **stable across every rotation of the same chain** - that is what lets a replayed token be traced back to the chain it came from, which is the whole mechanism behind `ReuseDetected`. Under the old name, three refreshes hours apart logging one value read as "the rotation id is not rotating", i.e. as a broken security control, when it was the correct one working. A stable `ChainId` across rotations is the expected reading; a **changing** one would be the anomaly.

**An UNMATCHED route is `Debug`, whatever its 4xx (added 2026-09-03, RV.16).** The rule above is
right for a client getting a *real* endpoint wrong; it was wrong for "no endpoint exists", which on
a public IP is not a client at all. Measured in production: **~250 Information lines in 90 seconds**,
sustained - `POST` bodies of 5 KB and 67 KB to routes this app has never had, `accountHash`,
`deviceId` and `clientVersion` all null on every one. Internet scanning, answered correctly in
0.08 ms, and it buried `sync.push`, `blob.commit` and `llm.extract` for the whole window - the same
failure this section's first rule exists to prevent, arriving from a direction that rule did not
cover. At ~260k lines a day it is also a real cost on a host that has OOM-killed its runner once.

The distinction is **the route, not the status**: `TraceCorrelationMiddleware.UnmatchedRoute` is
already what the line carries when nothing matched. A 404 from a **matched** endpoint - a blob that
is not there, an account that does not exist - stays `Information`, because that is a client of ours
getting an answer it may need help with. Three tests hold the pair apart (unmatched 404 *and* 405 at
`Debug`, matched 404 at `Information`, unmatched 5xx still `Warning` - that last one pins the ORDER
of the arms). Mutation-checked: deleting the unmatched arm fails exactly the first two.

**The OUTBOUND `HttpClient` lines are `Warning` (added 2026-09-03, RV.13).** The same noise from the
other direction: `System.Net.Http.HttpClient` was in no `Logging:LogLevel` entry, so it fell through
to `Default: Information` and every outbound call emitted **four** lines - `RequestPipelineStart` and
`RequestPipelineEnd` from the `...LogicalHandler` category, `RequestStart` and `RequestEnd` from
`...ClientHandler`. One `/extract` cost eight, on top of the inbound line for the request that
triggered it. They also read as a broken logger: `{Uri}` printed as a literal placeholder and
`HttpMethod` as `{"Method":"GET"}`.

**`{Uri}` not rendering is correct, and stays that way.** An outbound URI is a domain value - the
rate-feed and LLM-gateway hosts say which provider a user's receipt went to - so hard rule 12 forbids
logging it "at any level, in any build", and the redactor drops it. The fix is therefore to stop
emitting the lines, never to supply the value.

**What is deliberately still loud.** The category also narrates a *failed* call
(`RequestFailed`/`RequestPipelineFailed`, with the exception) - and does so at Information, so raising
the category to Warning takes those with it. That was checked before the change, caller by caller,
and every outbound caller logs its own outcome: the rate job logs `Rate feed {Source} failed ...` at
Warning, `LlmService` logs `llm.extract` with `provider_failed` at Error, an APNs failure is counted
onto `sync.nudge` (with a Warning if the client throws at all), and a JWKS fetch that throws
propagates to the global handler as `error.unhandled` at Error. Not one of them depended on an
HttpClient line to be visible. `Logging:LogLevel:System.Net.Http.HttpClient=Information` brings the
narration back for a debugging session.

The entry lives in the committed **templates** (`appsettings.template.json` and
`appsettings.Development.template.json`); `appsettings.json` is gitignored and generated from them,
so editing the generated file would change nothing that ships. The base template also covers the
`Testing` environment, which has no settings file of its own. Two L2 tests pin both halves against
that shipped template - a 200 emits no HttpClient line while `rates.fetch` still appears, and a
refused connection still surfaces the caller's Warning - and both go red when the entry is removed.

**Re-levelled, not removed.** `Logging:LogLevel:Default=Debug` brings every request back with its
correlation fields intact, and a test pins that the successful line is still emitted there - so
"quieter" cannot quietly become "gone". The line also carries a human summary now
(`GET /v1/sync/pull -> 200 in 693ms`) alongside the unchanged structured fields, because the bare
event name made every request line identical.

**The deployed server runs `text` (changed 2026-09-02, product owner).** The original rule here was JSON everywhere outside Development, and it is the right default *once logs are shipped somewhere that parses them*. Today they are read by eye with `docker logs` on the deploy host, where one JSON object per line is markedly harder to scan than the same fields on a labelled line - and a format nobody can read is not observability. `backend/scripts/deploy-blue-green.sh` sets `Tankbook__Logging__Format`, defaulting to `text` and overridable with `TANKBOOK_LOG_FORMAT=json`.

**Switch it back to `json` the day a log aggregator exists.** Nothing else changes - the same fields, the same redaction, the same `traceId`; only the rendering differs, and `RenderText`/`RenderJson` share one field-ordering path so neither can carry a value the other does not.

### Always, per request (one line)
`method, path (route template, not the raw URL – ids stay out of paths in logs), status, durationMs, traceId, accountHash, deviceId, clientVersion, clientPlatform, serverVersion, schemaVersion, requestBytes, responseBytes`

### Per operation – the "who / what / changed / outcome" record

| Event | Fields (all Safe class) |
|---|---|
| `auth.session` | provider (apple/google), outcome (created/matched/rejected), failureReason (invalid_signature / expired / clock_skew / revoked), accountHash on success – the salted hash of the **account id**, the same value the follow-up request scope logs (RV.63). A rejected exchange logs no accountHash (no account was resolved – null is honest). **Never the token.** |
| `auth.refresh` | outcome, rotation id, `reuse_detected: true` when a rotated token is replayed – this one is a **security event**, log at WARN and include deviceId |
| `sync.push` | batchSize, accepted, conflicts, rejected, `assignedScnRange: [from,to]`, durationMs; and a compact per-item array of `{id, entityType, schemaVersion, outcome, errorCode?, pointer?}` – **ids and outcomes, never values** |
| `sync.pull` | sinceScn, returned, nextSince, more, durationMs |
| `sync.nudge` | accountId, candidates, delivered, invalidToken, transient, throttled, config, durationMs – counts and outcome only; **never the push token** (a Never credential) |
| `blob.begin` / `blob.commit` | sha256, sizeBytes, contentType, `dedupe: hit\|miss`, quotaUsedPct |
| `blob.get` | sha256, `presignTtlSec` – never the signed URL |
| `llm.extract` | kind, requestsUsedBefore/After, model, durationMs, outcome. The two `requestsUsed*` fields count the period's metered requests USED before and after the call - a usage counter going up (RV.60 renamed them from `quotaBefore/After`, which read as a quota increasing). **Never the image, never the extracted values.** |
| `llm.rendition_failed` | accountId, outcome (Warning) – the ledger's prompt rendition could not be written to blob storage; the row still recorded the call WITHOUT it (RV.53, handled degradation) |
| `llm.call_queued` | accountId, outcome (Warning) – the ledger row insert failed and the row was queued for a bounded retry (`llm_ledger_pending`, RV.53) |
| `llm.call_unrecorded` | accountId, outcome (Error) – a paid call's ledger row could not be written anywhere (insert AND queue write both failed); the spend record is lost |
| `llm.call_retry_dropped` | accountId, outcome, attempts (Warning) – a queued ledger row exhausted its retry bound and was dropped; the defined give-up outcome (RV.53) |
| `llm.call_retry_landed` | landed (a count) – the retry pass wrote queued ledger rows into `llm_calls` |
| `llm.pending_purge` | purged (a count) – the retention pass dropped pending rows past the 30-day cutoff |
| `migration.ddl` | version, direction, durationMs |
| `migration.payload` | entityType, fromVersion→toVersion, rowsScanned, rowsRewritten, batches, durationMs |
| `feedback.accepted` | id, category, **textLength**, hasReplyTo, hasDeviceModel, hasAccount – shape only. **Never the text, never `replyTo`, never `deviceModel`**: the user wrote that text and `replyTo` is contact data, so all three are Never-class (hard rule 12). Pinned by a `RedactionTests` case - the mutation that proves it logs the text and watches the sweep fail naming the leaked value |
| `account.delete` | accountHash (the salted hash of the account id, RV.63), recordsPurged, blobsPurged, graceEndsAt |
| `catalog.publish` | version, entries (a count), outcome (published/rejected), reason (schema_validation_failed / version_not_monotonic / invalid_document) – **never the pack's contents**: the curation feedback loop records model strings as counts only, and that discipline holds here too |

**What changed** is expressed as identity + outcome (`id`, `entityType`, `schema_version`, old→new `scn`), never as a value diff. A record's history is already in the stream; the log's job is to say *that* it changed and whether it succeeded.

### Errors
Every ERROR line carries: `errorCode` (the stable code from API.md), `exceptionType`, `message`, `stackTrace`, `traceId`, plus **safe reproduction context**: which endpoint, which entity id, which schemaVersion, payload *size*, and for validation failures the **JSON pointer** to the offending field (the pointer names the field, never its value). That is the set that lets an engineer reproduce without seeing the data. `exceptionType` and `errorCode` are stable codes and pass through; the exception `message` and `stackTrace` are free text that can embed a statement's arguments or a domain value, so both go through the redactor and are masked (`***`) in every build - never raw (hard rule 12, `RedactionTests.SensitiveValueInsideAnExceptionMessage_IsMasked`).

Level discipline: `ERROR` = the request failed or data integrity is at risk. `WARN` = handled degradation (retry, conflict, quota exceeded, refresh-reuse). `INFO` = the per-request and per-operation lines above. `DEBUG` = development only, never enabled in production.

Health, readiness and metrics endpoints log at DEBUG only – they would otherwise drown the stream.

## 4 · iOS (OSLog / `Logger`)

Subsystem `live.belyaev.tankbook`; categories: `sync`, `persistence`, `capture`, `notifications`, `ui`, `auth` (plus `config`, the iOS-only addition). OSLog gives level-based persistence, redaction by default, and Console.app/`log collect` access without shipping a logging SDK. The app logs **only through the `TankbookLog` facade** (`AppLog` in the app target, built from `TankbookLog.makeDefault`): a raw `os.Logger` under any other subsystem is invisible to the diagnostics export (§5), so the SwiftLint rule `no_raw_os_logger` makes constructing one outside `Logging/` an error.

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

### Feedback (PJ.20)
`feedback.queue` / `feedback.send` / `feedback.fail` carry **shape only**: `category` (the
stable code), `textLength` (a count), `hasReplyTo` / `hasDeviceModel` (field *presence*, never the
values), and on failure `errorCode` + `durationMs`. **Never the feedback text, never a replyTo
address, never the device-model string, never a file's contents** (hard rule 12). The payload's
domain values have no route into these events by construction - the same discipline as
`capture.pipeline`.

### Errors
Every failure logs the typed error, its `underlyingError`, the operation in flight, the entity id, and the traceId when it came from a request. App-layer failures emit the typed events `app.error` (`operation`, `errorType` - both Safe - plus `errorDescription`, which is **Sensitive** because `localizedDescription` on a GRDB error can carry its statement's arguments: station names, notes, amounts) and `app.warning` (`operation`, `reason` - both Safe, for handled degradations). A view never interpolates `error.localizedDescription` with `.public`; what stays loggable is the type and a stable code, never the rendered message (hard rule 12). iOS additionally records a **breadcrumb ring** (last ~50 events, in memory), which reaches the
**diagnostics export**. It does NOT reach crash reports, and saying so was fiction: there is no
crash-reporting SDK in the app (GRDB is the only dependency), so crashes arrive only through
Apple's own pipeline - Xcode Organizer and App Store Connect - which carries a stack trace and
nothing of ours. Two consequences worth knowing rather than discovering: those reports come only
from users who enabled *Share With App Developers*, so they are a sample rather than a census;
and a crash's breadcrumbs are lost unless the user sends a diagnostics export by hand.

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
