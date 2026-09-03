# Tankbook – Backend API Contract

*The complete HTTP surface of the C#/ASP.NET Core backend. Shapes reference `SCHEMA.md` (payloads) and `SYNC.md` (protocol semantics). This document is the contract both the iOS client and the backend implement against – changes here are breaking-change reviews, not refactors.*

Conventions: JSON bodies, ISO-8601 UTC dates, UUIDs as strings. Errors use RFC 7807 problem+json: `{ type, title, status, detail }`. All endpoints are TLS-only. Rate limits return `429` with `Retry-After`; oversize bodies return `413` with the `traceId` (see "Rate limits and request body caps").

## Request headers (every request, PR.8)

Every request from the native app carries these; the server puts them into the log scope (docs/LOGGING.md §2):

| Header | Value | Notes |
|---|---|---|
| `X-Tankbook-Trace` | a UUIDv7, fresh per logical request | Correlates a support report to exact server lines; echoed in the response header and in the `problem+json` body of any error. Absent → the server generates one. |
| `X-Tankbook-App` | `<version>+<build>` (e.g. `1.0.0+1`) | Marketing version + `CFBundleVersion`. |
| `X-Tankbook-Platform` | `ios` | The client platform. |
| `X-Tankbook-Schema-Version` | the client's payload contract version (int) | Logged as `schemaVersion`. |

On a **non-2xx** response the client reads `traceId` from the problem+json body onto the thrown error, so an error handler always has the correlation id even when the response header was lost (the unhandled-500 path).

## Auth

| Endpoint | Auth | Purpose |
|---|---|---|
| `POST /auth/session` | identity token | Exchange a Sign in with Apple / Google ID token for a session. Body: `{ provider: "apple"\|"google", idToken, device: { name, platform } }` → `{ accessToken (JWT, ~1h), refreshToken, accountId, deviceId }`. Creates the account on first sign-in (email from the verified token; Apple private relay respected) – there is no separate registration endpoint. **No account linking in v1**: Apple and Google identities are distinct accounts; the client handles the wrong-provider case in UX (JOURNEYS J11a), the API just returns whichever account the token maps to. Registers/updates the device row. |
| `POST /auth/refresh` | refresh token | `{ refreshToken }` → new token pair. Refresh tokens rotate; reuse of a rotated token revokes the chain (theft signal). |
| `DELETE /auth/session` | bearer | Sign out this device (revokes its refresh chain; local data stays local). |

**The identity token is checked for who it was minted FOR, not only for who signed it.** `aud` must
be in the provider's configured audience allowlist and `iss` must be one of the provider's issuers,
both checked before any other claim is read; an unconfigured allowlist refuses every token rather
than accepting any (`docs/SECURITY.md` → "A verified signature is not a verified identity"). A
token minted for another OAuth client is a `401` like any other verification failure – the client
cannot tell, and must not be able to.

Failure statuses (all `problem+json`, reason in `detail`): a session exchange whose `idToken` does not verify (garbage, expired, bad signature, unverified email, wrong audience, wrong issuer) returns `401`; an unsupported `provider` or a malformed body returns `400`. A refresh with an unknown, expired, or reused-rotated token returns `401` (reuse additionally revokes the chain). Sign-out returns `204`, or `401` without a valid bearer token.

**The client's half of the token lifecycle (PR.1/PR.2).** A `401` on any bearer endpoint is an
auth event, never a gate from a newer server: the client refreshes **once** through a single shared
`SessionRefresher` actor (concurrent `401`s await the one in-flight refresh, because a reuse of a
rotated refresh token revokes the chain), persists the rotated pair, and replays the original
request with the new bearer. A refresh that itself answers `401` clears the session locally and
surfaces "sign in again" - the honest next step, never "update the app". Sign-out calls
`DELETE /auth/session` best-effort and clears the Keychain even when that call fails, so offline
sign-out still signs out locally.

All endpoints below marked **bearer** take `Authorization: Bearer <accessToken>`. **public** = no auth.

## Sync (the core – "latest data" and "changes")

Full semantics: `SYNC.md`. Both endpoints are idempotent.

### `GET /sync/pull` – bearer
Fetch changes since a cursor. **Fetching the latest data IS pulling from 0** – fresh install/restore and incremental catch-up are the same call.

```
GET /sync/pull?since=<SCN>&limit=500        // since=0 → full dataset
→ 200 { records: [ { id, entityType, schemaVersion, scn, payload, clientUpdatedAt, deleted } ],
        nextSince: <SCN>, more: bool,
        schemaPolicy: { minSupported: int, current: int } }   // clients upcast to `current` on read
→ 410 device revoked / account deleted → client re-onboards or detaches
```
Strictly SCN-ordered, paginated; the client persists `nextSince` per device only after applying the page.

### `POST /sync/push` – bearer
```
{ changes: [ { id, entityType, schemaVersion, baseScn,   // baseScn 0 for new records
               payload, clientUpdatedAt, deleted } ] }   // ≤ 200 changes/batch
→ 200 { results: [ { id, status: "accepted", newScn }
                 | { id, status: "conflict", current: <record> }
                 | { id, status: "rejected", error: <code>, pointer: <json-pointer> } ] }
→ 426 upgrade_required   // whole batch: client schemaVersion < server minSupported.
                         // PULL still works – never lock a user out of their own data.
```
Per-item outcomes; `conflict` returns the server's current record for client-side LWW merge + re-push (SYNC.md S1/S6). Payloads with `clientUpdatedAt` >24h in the future are clamped to server time and the accepted result carries `"clamped": true` so the client can warn.

**Payload validation** (per-item `rejected` codes, full contract in `SYNC.md` → "Payload contract and versioning"): `payload_invalid` (not an object, >256 KB, bad entityType), `schema_version_unsupported` (newer than the server knows – the *server* needs updating, and the message says so), `payload_schema_violation` (fails the registered JSON Schema; `pointer` names the offending field). A **known** entityType is strictly validated; an **unknown** one with a well-formed envelope is accepted unvalidated, which is what keeps the entity set open for older servers.

## Attachments (blob pipeline – `SYNC.md`)

| Endpoint | Auth | Contract |
|---|---|---|
| `POST /blobs/begin` | bearer | `{ sha256, size, contentType }` → `{ status: "exists" }` \| `{ status: "upload", url: <presigned PUT>, expiresAt }` \| `413` size cap (images 25 MB, PDFs 10 MB per `SYNC.md`) \| `429` quota. |
| `POST /blobs/commit` | bearer | `{ sha256 }` → `204` after server verifies object + size. Referencing records must push only after commit. |
| `GET /blobs/{sha256}` | bearer | `302` → short-lived presigned GET (~10 min, single object). `404` if not owned by this account. |

`begin` refuses a malformed body with `400` (a `sha256` that is not 64 lowercase hex digits, or a
missing/negative `size`) and a content type outside the allow-list with `415`; it answers `413` per
type (images 25 MB, PDFs 10 MB) and `429` when the account's metered storage quota (default 5 GB,
configurable) would be exceeded. `commit` verifies the stored object against the size declared at
`begin` (the server remembers it between the two calls) - a commit with no preceding `begin`, no
uploaded object, or a size mismatch answers `409` and creates no row; it is idempotent (`204` on
replay). A revoked device or deleted account gets `410` on all three. A presigned URL is never
minted for a blob this account does not own, and never appears in a log (`LOGGING.md`).

## Reference data (public, CDN-cacheable)

| Endpoint | Auth | Contract |
|---|---|---|
| `GET /config` | public | Remote configuration document + Ed25519 signature, `ETag`/`If-None-Match` (`304` when unchanged). No auth – guests need it too. Full client contract, guardrails and failure behaviour: `CONFIG.md`. |
| `GET /rates?date=&base=` | public | All quotes for one date. Past dates: `Cache-Control: immutable`. |
| `GET /rates/pack?from=&to=&base=` | public | Bulk range for device cache / seed refresh. |
| `GET /catalog?since_version=` | public | Vehicle catalog delta or full pack + `packVersion` + `kind` (`"full"`/`"delta"`). ETag'd. |

### Exchange rates (`GET /rates`, `GET /rates/pack`)

Both public, no auth. `base` is a three-letter ISO 4217 code (missing or malformed → `400`);
`date`/`from`/`to` are ISO-8601 `yyyy-MM-dd` (missing or malformed → `400`). Rates are served
as `1 base = rate quote units` (the `Money` original-per-home direction, `SCHEMA.md`).

```json
// GET /rates?date=2026-08-21&base=EUR
{ "date": "2026-08-21", "base": "EUR", "quotes": [
  { "quote": "USD", "rate": 1.0856, "source": "ecb" },
  { "quote": "RUB", "rate": 90.1234, "source": "cis:carried-forward" } ] }

// GET /rates/pack?from=2026-08-01&to=2026-08-31&base=EUR
{ "from": "2026-08-01", "to": "2026-08-31", "base": "EUR", "rates": [
  { "date": "2026-08-01", "quote": "USD", "rate": 1.0800, "source": "ecb" } ] }
```

`source` distinguishes a published quote (`ecb`, `cis`) from one carried forward across a
non-publishing day (`ecb:carried-forward`). A **past** date's quotes never change, so they are
served `Cache-Control: immutable` and `ETag`/`If-None-Match` (304 when unchanged); **today's**
can still change (a late publish or a correction), so it is served revalidatable, never
immutable. A date with no data answers `200` with an empty `quotes` array - never a
neighbouring date's value (carry-forward is a stored row with its own date, `SCHEMA.md`).
`/rates/pack` rejects a range wider than the server's bound (`400`) rather than streaming an
unbounded span. `/rates/pack` is also the **backfill trigger** (`SCHEMA.md` → Exchange rates):
a request for a range queues any date in it that has no rate yet, and a background job fetches
those dates so the device's next refresh gets them; the response itself returns only what is
already stored, so it never waits on an upstream fetch. This is a side effect on a read
endpoint, but it is an idempotent queue write and the only way the server learns what a device
actually needs - the backfill horizon is the demand, not a fixed window.


### `GET /reference/fuel-price-bands`

Coarse plausible price-per-litre ranges, used client-side to decide which operand on a
receipt is the price and which is the volume (`SCHEMA.md` → Fuel price bands). Public,
unauthenticated, ETag + `Cache-Control` like the other reference data; `If-None-Match` → 304.

```json
{ "version": 3, "bands": [
  { "country": "RU", "currency": "RUB", "fuelKind": "petrol95",
    "periodStart": "2026-01-01", "low": 60.0, "high": 460.0 },
  { "country": "RU", "currency": "RUB", "fuelKind": "lpg",
    "periodStart": "2026-01-01", "low": 15.0, "high": 40.0 },
  { "country": "EE", "currency": "EUR", "fuelKind": "petrol95",
    "periodStart": "2026-01-01", "low": 1.2, "high": 2.5 }
] }
```

Server-side this is static curated data - **no domain logic, no query parameters that make
the server interpret meaning** (hard rule 9). The client downloads the pack and does the
matching itself; the endpoint only serves rows.

### `GET /catalog` (vehicle catalog)

`GET /catalog` is **public** - no auth, no account - because a signed-out user's Add-car
autocomplete needs the dictionary too (docs/SYNC.md → Reference data). The server is the
**master copy**; the client consumes one-way, and nothing here has an SCN, a tombstone or a
conflict state.

```
GET /catalog[?since_version=<n>]
→ 200 { packVersion: <current>, kind: "full" | "delta", entries: [ <entry> ] }
→ 304 when If-None-Match matches the current representation

<entry> = { id, make, model, generation?, years?, powertrain, fuelKinds, tankCapacityL?, batteryCapacityKwh? }
  years      = [firstYear, lastYear] inclusive, or null
  fuelKinds  = the model line's OFFER SET (petrol95/diesel/lpg/...), never one car's fuel (docs/SCHEMA.md)
```

- **`kind` is present on every response** and is how a client tells "here is
  everything" from "here is what changed" - never inferred from an entry count
  or from the absence of `since_version`. **`kind: "full"`** means `entries`
  ARE the whole catalog: the client **replaces** its held set with them, so an
  entry absent from the pack is withdrawn by curation and stops being offered.
  **`kind: "delta"`** means `entries` are only what changed since the client's
  version and are **overlaid**, never removing an entry the server did not
  mention (docs/SYNC.md "Applying an update").
- **`since_version`**: the `packVersion` the client holds. **Missing** = full pack (the
  documented default: a fresh client or a seed refresh asks for the whole catalog, and
  400-ing first contact would make the simplest client call fail). Malformed (not a
  non-negative integer) = `400` problem+json. **At or above the current version** = an
  **empty delta** carrying the current `packVersion` - a truthful answer, never a
  fabricated entry and never a full pack pretending to be a delta.
- **Delta vs full pack** (a stated rule, not an accident): the server answers with the
  entries changed since `since_version`, **unless** more than `Catalog:MaxDeltaEntries`
  (**default 50**) entries changed - then the client is too far behind and the full pack
  is served instead. Either way the body is the same `{ packVersion, kind, entries }`
  envelope; the client applies the entries per `kind` and holds `packVersion` from then on.
- **`packVersion` is monotonic** (docs/SYNC.md rollback protection): a response is always
  at the current version, and the publish path refuses to go backwards.
- **ETag / If-None-Match**: a strong ETag over the exact body; an unchanged catalog costs
  a `304`. `Cache-Control: public, max-age=300, must-revalidate` (curation is rare but
  does happen, so the full pack is revalidatable, never immutable).

> **Breaking change (P6.12):** the response shape grew a `kind` field -
> `{ packVersion, entries }` → `{ packVersion, kind, entries }`. The only
> consumer is this repo's own iOS client, changed in the same commit. A client
> built before this change ignores the unknown field and keeps overlaying every
> pack - exactly the behaviour that preceded the marker, which is the current
> bug (a withdrawn entry can survive a full pack) and not something worse.
> Backward tolerance is therefore deliberate: an older client degrades to the
> status quo, never to data loss.

**There is no publish endpoint.** `POST /catalog/publish` was removed on 2026-09-01 (product
owner): catalog packs are written **directly to the database**, so the catalog has no write surface
on the API at all and the `Catalog:AdminToken` secret it was gated on is gone. `GET /catalog` is the
whole contract.

What the removed endpoint enforced still applies, because it lived in `CatalogPublishService` rather
than in the route, and that service is still the in-process write path: a pack is validated against
`catalog.schema.json` **whole or not at all**, and a `packVersion` not greater than the current one
is refused (`<=` is a rollback). **A write that bypasses that service bypasses both guarantees** –
a hand-written `INSERT` can publish a malformed entry or roll the version backwards, and nothing
will stop it. **`removedIds`** withdraws catalog rows: those ids are **deleted**, so the subsequent
full pack lacks them - this is how a removal becomes expressible on the wire (docs/SYNC.md
"Applying an update"). A withdrawal is a physical delete, never a tombstone, so the server never
remembers what it withdrew.

Curating server-owned reference data was never a hard-rule-9 violation; that question is now moot,
since the server exposes no endpoint that reads what a catalog field means.

## Feedback

### `POST /feedback` – public (bearer optional)
```
{ category: "feature" | "problem" | "other", text,
  appVersion, deviceModel?, replyTo? }        // deviceModel only with the user's toggle
→ 202
```
Account id attached when a bearer token is present; rate-limited per device/IP; `text` ≤ **4 000 characters**. No log content, ever.

**Characters, not bytes (corrected 2026-08-31, PJ.20a).** This line read "≤ 4 KB" until the server half was built against the client that had already shipped: `FeedbackPayload.maxTextLength` is 4 000 **characters**, and 4 000 Cyrillic characters is roughly 8 KB of UTF-8. A byte cap of 4 KB would have rejected a legitimate Russian report with a `413` - in an app that ships EN and RU from day one. The body cap is sized to the client's real maximum instead (see the caps table below).

## Import parsing (hard rule 9's named exception)

`POST /import/parse` - **the one endpoint that reads what a field means**, amended into hard rule 9
on 2026-08-27. It exists so a single parser serves every client and a mapping bug is fixed by a
deploy rather than an App Store release.

**`GET /import/formats`** - the supported-source list, **server-driven and public**. Returns
`[ { id, displayName, fileKinds, helpUrl?, addedInPackVersion } ]`, ETag'd like the other reference
data. Today it lists one format: `{ id: "mfm", displayName: "My Fuel Manager", fileKinds: ["csv"], helpUrl: "https://tankbook.live/import-guide/", addedInPackVersion: 1 }`.

**`helpUrl` points at the site's per-source export guide** (J2's "their UIs hide export"; PJ.33).
The client renders a "How to export" link on the format row and inside the 422 / not-listed
messages. The page must exist before the URL ships - a link that 404s is worse than no link (hard
rule 7) - so `helpUrl` and the `site/content/import-guide*.md` page land in the same change.

**This endpoint is what makes server-side parsing pay off, and hardcoding the list in the app would
throw that away.** Moving the parser to the server buys two things: fixing a mapping without an App
Store release, and *adding a format* without one. Only the first survives if the picker's list ships
in the binary - a new parser nobody can select is a parser that does not exist. So the client
renders whatever the server lists, and an older client simply shows fewer options.

**The user declares the format; the server does not sniff it.** The import UI asks *which app this
file came from* and offers the list above (`docs/ERRORS.md` -> Import). Two vendors' CSVs can look
nearly identical, and a confident mis-mapping is worse than a question - hard rule 13, the same
reasoning as the currency chip on Confirm.

`multipart` upload of a third-party export (`format: "mfm" | ...` **as declared by the user**, file <= 8 MB) ->
`{ importId, format, scope: "vehicle", candidates: [ <entity payload> ], unparsed: [ { row, reason } ],
   ambiguities: [ { kind: "dateFormat" | "currency" | "units" | "outOfScope", options, rowCount } ] }`

- **It commits nothing.** `candidates` are *proposals*; the device reviews, edits and writes them
  (hard rule 13). The server holds no user data beyond the stored file and its parse result, and
  changes no account state.
- **Works signed out.** No bearer required; stored under the device identity when there is no
  account. Import must not require an account (hard rule 1's exception covers the network, not a
  sign-in). A signed-out parse is attributed to the `X-Device-Id` header (the client's existing
  `deviceId`); without it, and without a bearer, `POST` answers `400`. With a bearer the parse is
  stored under the account, not the device.
- **`GET /import/{importId}`** re-reads a stored parse so a review can be resumed on another device
  or after a crash. An account-owned parse answers `404` to anyone but its owner; a device-owned
  parse is governed by the importId itself (the id is the capability). **`DELETE /import/{importId}`**
  drops it early, **idempotently** (`204` whether or not it existed); otherwise it is **purged after
  30 days** (`docs/SECURITY.md` -> Import files at rest).
- **Ambiguity is returned, never guessed** - the F6 once-per-file questions, applied client-side:
  - `dateFormat` (`M/D/YYYY` vs `D/M/YYYY`, the real MFM export contains genuinely ambiguous dates):
    `options` names both readings and `rowCount` is the number of rows whose day is also ≤ 12, so
    the same string would parse either way. The candidates carry the format's M/D reading; if the
    user answers D/M, the client flips exactly the counted rows.
  - `currency`: `options` is the single currency the file declares on every row (the real export
    reads `USD` regardless of where fuel was bought) - a **default the user corrects** (hard rule
    13), never a fact.
  - `units`: emitted by formats that carry an ambiguous unit; MFM is metric, so it emits none.
  - `outOfScope`: a recognised file whose rows are deliberately unmapped (`income`, `reminder`) -
    `rowCount` is the number of rows skipped, so the client can say "this file has N income rows;
    income isn't imported in v1" instead of silently showing nothing.
- **Candidates are entity payloads the client can commit** (id/createdAt/updatedAt/vehicleId/
  attachments/conflict are added at commit), carrying two extra proposal-only fields: `sourceRow`
  (the 1-based data-row number in the file, for the review list) and, where the file carries one,
  `vehicleName` (which car the row belongs to). `provenance = { tag: "import", source: <format> }`
  on every row (`docs/SCHEMA.md` import rules). `unparsed[].row` is the same 1-based data-row
  numbering and `reason` is a stable code (`invalid_date`, `invalid_number`, `missing_required`,
  `unknown_fuel_code`, `unknown_finance_category`, `wrong_column_count`).
- **Unparseable rows do not fail the file**: they come back in `unparsed` with a reason and land on
  the review list, so a partial import is the normal outcome rather than an error (F6, hard rule 8).
- `413` oversize, `415` unrecognised format id, `422` **the file does not look like the format the
  user declared** - the client says so specifically ("this does not look like a My Fuel Manager
  export") and offers the picker again, never a generic failure (F7 forbids "something went wrong").
- **Logs carry shape only**: format, file kind, row counts, error counts. Never a station, note,
  amount or coordinate (hard rule 12). `POST` is a public native-app endpoint with no browser
  cookies, so the anti-forgery metadata that multipart binding would otherwise attach is disabled.

## LLM gateway (Pro)

### `POST /extract` – bearer
`{ kind: "receipt" | "pump" | "chargeScreenshot" | "invoice", image: <base64 ≤ 4 MB>, hints: { currency?, locale?, vehicleFuelKinds? } }` → `{ fields: { <FieldRef>: { value, confidence } }, pipeline }` per SCHEMA.md `ExtractionMeta`. `402` when the tier lacks quota, `429` per-period quota spent (client falls back to on-device result – JOURNEYS F4; **never an upsell mid-capture**).

**The model is data, not compiled config (amended 2026-09-03, RV.34).** Which model serves which
kind, and what that model costs, live in two tables written by direct DB write (no admin
endpoint, the same decision as the vehicle catalog): `llm_settings` keys a model per kind
(receipt vs pump display are different problems), and `llm_models` is the model dictionary -
vendor, per-token input/output price, currency, context window, and whether thinking is
supported, with an `effective_from` date so a price correction is a new row, never an edit. A
missing or unknown setting falls back to the compiled default and logs the fallback at Warning;
it never 500s. No API key lives in either table (hard rule 11).

**Every call is recorded (amended 2026-09-03, RV.33).** Each call to the gateway writes one row
to the call ledger: caller, model, vendor, outcome, a success/error category, token counts,
whether thinking was enabled and its response, the cost (a snapshot of the dictionary price it
paid, so a later price change never rewrites it), and the prompt and response. The prompt for
`/extract` is the image, stored in blob storage and referenced by `sha256` from the row - never
in a column. The row's content is purged on `DELETE /account` and after 30 days; the row itself
(the spend ledger, including `accountId`) survives. There is no endpoint that reads the ledger.
Status codes: `400` unknown `kind` or missing/undecodable `image`; `413` base64 image over the 4 MB cap (enforced at the envelope, before the provider is called); `502` provider failure (not metered – a failed call never bills, and the client falls back to the on-device result). A low-confidence field is returned as a value plus a low confidence – never dropped, which would silently turn "uncertain" into "absent".

#### The device's side of `/extract` (normative)

The endpoint is only half the contract. Two device-side rules are part of it, because the server
cannot enforce either and the user experience depends on both.

**1 · The image is downscaled and compressed before upload.** A full-resolution iPhone capture is
several megabytes; uploading one over a forecourt's cell signal is the slowest step in the whole
flow by an order of magnitude, and the 4 MB envelope cap is a ceiling, not a target. The device
therefore sends a **long-edge-bounded, JPEG-compressed** rendition.

**Compression is a measurable trade, not a free one.** Fuel receipts are thermal print: the
digits that matter are small, and over-compression eats exactly them. So the compression settings
are **gated on the corpus** - re-score the receipt fixtures through the compression step with the
existing scorer (`CorpusCompressionTests`), and if hits fall, the settings are too aggressive. This
is what stops "make the upload faster" from quietly becoming "read the receipt worse".

**The corpus answered, and it changed the starting point.** The 1600 px / quality 0.7 start from
this section was measured against the receipt corpus and scored **82/175** - six hits below the
recorded 88/175, so those settings were too aggressive (the exact miss class the gate exists for).
The shipped values are now **long edge 1800 px, quality 0.9**, which re-scores **89/175** at a
median ~360 KB base64 rendition (max ~830 KB across the receipt corpus) - comfortably under the
4 MB ceiling and with accuracy intact. Tune again the same way: re-score, and any setting that
drops hits below the recorded mark is rejected.

**2 · The device waits 3 seconds per attempt, then stops making the user wait.** The on-device
result is already on screen (F4: the app never waits on the gateway to show the card). When the
budget expires the user is told, in a message that names the next step (hard rule 7), that they
can carry on with what was read locally.

The budget is about **the user's next step, not about aborting the work** - and the arithmetic
says it has to be. At a realistic 1 Mbit/s upstream, even a 250 KB rendition takes ~2 s to upload
before the model has seen a pixel, so a hard 3 s abort would cancel almost every request on a
mobile link and make the whole tier useless where it is needed most. So: at 3 s the **UI** moves
on; the request itself may finish in the background.

A late answer is bound by hard rule 13 and by F4:

- it may fill **only fields that are still blank and untouched**, and it renders as a suggestion
  the user can reject, exactly as any other extracted value;
- it may **never** overwrite a field the user has typed in or confirmed;
- and once the entry is **saved, nothing arrives at all** - a saved entry is corrected by its
  owner alone (`JOURNEYS.md` F4).

Retries are the device's business, not the user's: one silent retry at most, never a dialog, and
never a second 3 s wait imposed on someone who has already moved on.

### `POST /extract` delivery, and the outbox when it fails (RV.44)

`POST /extract` answers only when the client is still there. When the client vanishes mid-request
- production shows nginx `499` after 33 s - the model call **still completes and is still paid
for**, but the answer would be lost. So when the gateway cannot hand the result back, it enqueues
the result into a small **per-device outbox** and the device drains it on next launch. The request
body gains an optional `captureId` (the device's own correlation token, e.g. the entry id it is
about to save); the gateway echoes it opaquely into the queued payload, never reading its meaning.

**This is not a read endpoint over the call ledger.** RV.33's amendment says the ledger is
"written by the gateway and read by no endpoint"; the outbox keeps it that way - it is opaque
bytes addressed to a device, the same shape as `GET /blobs/{sha256}` (retrieve-what-you-are-
entitled-to), and the server never reads a field, never queries by meaning, and offers no search
or stats over it (hard rule 9, `docs/SECURITY.md` "The delivery outbox").

| Endpoint | Auth | Contract |
|---|---|---|
| `GET /outbox` | bearer | Drain this device's pending rows, oldest first: `200 { items: [ { id, payload } ] }`. `payload` is the queued result, base64-encoded, never decoded server-side. Read-only - it does **not** delete. |
| `DELETE /outbox/{id}` | bearer | Ack one collected row, idempotently (`204`). Scoped to the caller's own device, so a foreign id deletes nothing (no existence leak). |

The ack is a separate call on purpose: a device that dies between read and ack drains the same
rows again on its next launch (at-least-once), dedupes by row id, and then acks them. Retention is
30 days (the one number shared with the tombstone/undo window, `/import/parse` and the ledger);
`DELETE /account` purges the outbox with the account.

## Account & devices

| Endpoint | Auth | Contract |
|---|---|---|
| `GET /account` | bearer | `{ accountId, email, createdAt, storage: { usedBytes, quota }, llm: { used, quota, period } }` |
| `GET /account/devices` | bearer | Registered devices with `lastSeenAt` – the "manage devices" screen. |
| `PUT /account/devices/{id}/push-token` | bearer | `{ apnsToken }` (or `{ fcmToken }` for Android later) → `204`. Enables silent sync nudges (`NOTIFICATIONS.md`); APNs invalidation clears the row and the device falls back to polling. |
| `DELETE /account/devices/{id}` | bearer | Revoke a device: its next pull gets `410`. |
| `DELETE /account` | bearer | Tombstone account; purge records + blob prefix after grace period (SYNC.md). Devices get `410`; local data stays local. |

## Ops

`GET /health` – liveness (public, unversioned). Everything else is versioned under `/v1/…` from day one; additive evolution within v1 (new optional fields, new endpoints), breaking changes = `/v2`.

## Rate limits and request body caps

Every limit here is a flood guard, chosen so a real user can never hit it – a `429` means an attacker or a bug, not a busy human. A rate-limited request is a `429` problem+json carrying `Retry-After` (seconds until the window resets); the client decodes and displays that header, so the user always knows when to retry (hard rule 7). The limits are operational and bind from the `RateLimit` configuration section (`RateLimit__AuthSessionPerMinute` etc.).

**Rate limits** (requests per one-minute fixed window):

| Endpoint | Key | Default |
|---|---|---|
| `POST /auth/session` | client IP | 30/min |
| `POST /auth/refresh` | client IP | 60/min |
| `POST /import/parse` | client IP | 20/min |
| `POST /extract` | device | 30/min |
| `POST /sync/push` | device | 120/min |
| `POST /blobs/begin` | device | 120/min |
| `POST /feedback` | device | 10/min |

Per-device limits key on the authenticated device id (the bearer token's `device_id`), falling back to the `X-Device-Id` header, then the IP.

**Request body caps** (enforced at the envelope, before any byte is read; an oversize body is a `413` problem+json carrying its `traceId`, never a bare connection reset):

| Endpoint | Cap |
|---|---|
| `POST /sync/push` | 200 × 256 KB payloads + envelope (~52 MB) – the maximal legal batch |
| `POST /extract` | 6 MB (4 MB base64 image + envelope) |
| `POST /import/parse` | 8 MB file + multipart envelope |
| `POST /feedback` | 17 KB (4 000 characters at 4 bytes worst case + 1 KB envelope) |
| everything else (auth, blobs begin/commit, account push-token) | 64 KB |

The push cap references the same constants the payload validator and sync service enforce, so the transport can never reject a batch the server would otherwise accept (`PRACTICES.md` – a number in two places is a bug).

## Explicitly not in the API

No domain queries (server never interprets records – no `/entries?vehicle=` endpoints, ever), no server-side search or stats, no photo transforms. If a feature seems to need one of these, the answer is a client-side computation over the synced data – see SCHEMA.md principle 2.
