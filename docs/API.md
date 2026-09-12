# Tankbook – Backend API Contract

*The complete HTTP surface of the C#/ASP.NET Core backend. Shapes reference `SCHEMA.md` (payloads) and `SYNC.md` (protocol semantics). This document is the contract both the iOS client and the backend implement against – changes here are breaking-change reviews, not refactors.*

Conventions: JSON bodies, ISO-8601 UTC dates, UUIDs as strings. Errors use RFC 7807 problem+json: `{ type, title, status, detail, traceId, code }` – `traceId` and `code` are extension members (see "Error envelope" below). All endpoints are TLS-only. Rate limits return `429` with `Retry-After`; oversize bodies return `413` with the `traceId` (see "Rate limits and request body caps").

## Error envelope

Every error response is RFC 7807 problem+json carrying **two extension members on every error**, plus one additive member on the blob-quota 429:

- `traceId` – the request's correlation id (docs/LOGGING.md §2), so a support report maps to exact server lines.
- `code` – a **stable, snake_case error code**, the same value the server logs as `errorCode` (docs/LOGGING.md §3 Errors). It is the client's key: what the user sees and what they can do next is decided from it (docs/ERRORS.md), never from the status alone. **Every problem+json carries a non-empty `code`** – the code is a required parameter of the server's problem factory, so an endpoint added without one does not compile (PR.9). A `detail` that names a next step or a user value is a bug: `detail` carries only shape (which field, which limit), never domain content (hard rule 12).
- `quotaUsedPercent` – **additive, only on the `blob_quota_exceeded` 429** (RV.253). The account's attachment-storage usage as an integer 0–100, from the same metered `SUM(size_bytes)` the quota check uses. The client renders it on the Settings quota card instead of a fixed placeholder; a client that does not know the member ignores it (the additive-member compatibility rule below). It is a count, never a domain value (hard rule 12).

Codes are grouped by **what the client must do differently**, not by call site – a code per endpoint is noise, a code per distinct next step is a contract. A client that meets a code it has never seen **falls back to its status-based handling** – never a blank, never a raw identifier – so a newer server can add a code without breaking an older client, and an older server (no `code`) is read exactly as today.

| Code | Status | The client's reading |
|---|---|---|
| `internal_error` | 500 | The server had an unhandled failure; retry, nothing is lost (S7) |
| `payload_invalid` | 400/415/422* | The request could not be processed as offered (a shape failure, never a business rule – hard rule 9) |
| `payload_too_large` | 413 | A body or attachment exceeds its cap; shrink the upload |
| `rate_limited` | 429 | A wait, named by `Retry-After` – never an error to retry immediately |
| `upgrade_required` | 426 | The client's schema version is below the server's minimum; pull still works |
| `tier_refused` | 402 | A server-side capability this client does not have |
| `upstream_unavailable` | 502 | An upstream service (the LLM provider) failed; the on-device result stands (F4) |
| `not_found` | 404 | The route does not exist on this server |
| `token_invalid` | 401 | The presented token was rejected – an auth event, never a gate |
| `refresh_reused` | 401 | A rotated refresh token was replayed; the whole chain is revoked (theft signal) |
| `clock_skew` | 401 | The identity token was rejected because the device clock is off – fix the date, don't retry |
| `provider_unsupported` | 400 | The sign-in provider is not offered |
| `device_revoked` | 410 | The device is revoked or the account deleted – re-onboard |
| `account_device_not_found` | 404 | The device id does not belong to this account |
| `blob_not_found` | 404 | No attachment with this sha256 exists for this account |
| `blob_conflict` | 409 | The begin/upload/commit protocol was violated; re-begin |
| `blob_quota_exceeded` | 429 | The account's attachment storage quota is exhausted |
| `import_format_unsupported` | 415 | The declared source format is not offered |
| `import_mismatch` | 422 | The file does not look like the format the user declared |
| `import_not_found` | 404 | No stored parse has this id |
| `config_unavailable` | 503 | The server has no published config document / signing key; the client keeps bundled defaults |

\* `payload_invalid` also names a per-item sync `rejected` outcome (docs/SYNC.md) alongside `payload_schema_violation` and `schema_version_unsupported`, which are per-item codes and never appear on the envelope.

The code set is deliberately small and stable: **adding a code is a client-visible contract change** (the client's mapping table and docs/ERRORS.md must grow in the same change), so a code is minted only for a distinct next step, never for a new call site.



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
| `POST /auth/session` | identity token | Exchange a Sign in with Apple / Google ID token for a session. Body: `{ provider: "apple"\|"google", idToken, device: { name, platform, deviceId? } }` → `{ accessToken (JWT, ~1h), refreshToken, accountId, deviceId, email }`. Creates the account on first sign-in (email from the verified token; Apple private relay respected) – there is no separate registration endpoint. **No account linking in v1**: Apple and Google identities are distinct accounts; the client handles the wrong-provider case in UX (JOURNEYS J11a), the API just returns whichever account the token maps to. Registers/updates the device row. |
| `POST /auth/refresh` | refresh token | `{ refreshToken }` → new token pair. Refresh tokens rotate; reuse of a rotated token revokes the chain (theft signal). |
| `DELETE /auth/session` | bearer | Sign out this device (revokes its refresh chain; local data stays local). |

**The identity token is checked for who it was minted FOR, not only for who signed it.** `aud` must
be in the provider's configured audience allowlist and `iss` must be one of the provider's issuers,
both checked before any other claim is read; an unconfigured allowlist refuses every token rather
than accepting any (`docs/SECURITY.md` → "A verified signature is not a verified identity"). A
token minted for another OAuth client is a `401` like any other verification failure – the client
cannot tell, and must not be able to.

Failure statuses (all `problem+json`, reason in `detail`, condition in `code` – see "Error envelope"): a session exchange whose `idToken` does not verify (garbage, expired, bad signature, unverified email, wrong audience, wrong issuer) returns `401` with `token_invalid`; a rejection for **clock skew** (the device date is off – a retry will not fix it) returns `401` with `clock_skew`, so the client can offer the date-settings fix instead of another attempt; an unsupported `provider` returns `400` with `provider_unsupported`; a malformed body returns `400` with `payload_invalid`. A refresh with an unknown or expired token returns `401` with `token_invalid`; **reuse of a rotated token returns `401` with `refresh_reused`** and revokes the chain (theft signal). Sign-out returns `204`, or `401` with `token_invalid` without a valid bearer token.

**The session response carries the account email (RV.39).** `POST /auth/session` returns the
account's **stored** email (`accounts.email`, set once at creation from the verified id token's
`email` claim). The client prefers it over the Apple credential's email, which Apple populates only
on the first authorization for a given Apple ID + app pair - so a client that depends on the
credential shows "Apple ID" from the second sign-in on. The stored email is **never refreshed**
after creation (the insert is `ON CONFLICT DO NOTHING`): the verifier already requires a verified
email, so a fresh account always has one, and a later token must not silently rewrite a Hide My
Email user's stored address. A genuine no-email account (email null in the response) renders the
provider name - the private-relay fallback stays intact.

**The device id is a client-supplied, unverified claim (RV.41).** `device.deviceId` is the
client's stored per-install identifier (Keychain, `AfterFirstUnlockThisDeviceOnly` - hard rule 11).
The server **reuses** that device row when it already belongs to the account authenticated by the
verified id token, and mints a fresh row otherwise. **It never adopts another account's row**: the
reuse is bound to the account id, so a device id belonging to a different account is ignored,
exactly as a foreign device id is indistinguishable from absence on the account endpoints. A
**revoked** row whose device returns is **re-attached** (`revoked_at` cleared) - the owner proved
the account again by presenting a valid id token, and re-attach is what makes a revoke →
re-sign-in cycle on one phone a single row rather than two (`docs/SECURITY.md` -> "Device
identity").

**The client's half of the token lifecycle (PR.1/PR.2).** A `401` on any bearer endpoint is an
auth event, never a gate from a newer server: the client refreshes **once** through a single shared
`SessionRefresher` actor (concurrent `401`s await the one in-flight refresh, because a reuse of a
rotated refresh token revokes the chain), persists the rotated pair, and replays the original
request with the new bearer. **The replay happens only when the bearer actually changed (RV.65).**
The whole request – body included – is re-sent on a replay, and for `/extract` or `/blobs` that body
is a large upload; if the refresher hands back the same token value the server has already rejected
exactly that bearer, so the client treats the `401` as final rather than re-uploading for a
guaranteed second refusal. A refresh that itself answers `401` clears the session locally and
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
→ 410 device revoked / account deleted (`device_revoked`) → client ends the cycle, drops the session, routes to sign-in
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

**The 410 contract on push (answered for RV.58 - written down, not coded around).** A revoked device
answers `410` on `pull` today because the pull endpoint checks the `devices` row; `push` (and the
blob endpoints) authenticate only the bearer token, and an access token stays valid for up to ~1 h
after a revoke, so those endpoints still accept a revoked device's writes in that window. **The
answer: no - push should not accept a revoked device's writes.** Revocation means access is gone
(`docs/SYNC.md`), and a token that outlives the revoke is still a bearer the server never asked to
revoke; the "a revoked device or deleted account gets `410` on all three" line in the Attachments
section is the intended norm. This is filed as a
backend change (the server should answer `410` to `sync/push` for a revoked device row, in the same
place `pull` checks it) and is deliberately **not** done in RV.58, which is client-only. It is also
defence in depth rather than the primary stop: RV.58 makes the client treat the FIRST `410` it sees
as terminal - the cycle stops, the session's tokens are discarded, and the revoked device routes to
sign-in - so a compliant client issues no second request for the server to refuse. The client change
is what ends the ~3-minute post-410 traffic tail seen in production (14:53:10 -> 14:56:04).

**Payload validation** (per-item `rejected` codes, full contract in `SYNC.md` → "Payload contract and versioning"): `payload_invalid` (not an object, >256 KB, bad entityType), `schema_version_unsupported` (newer than the server knows – the *server* needs updating, and the message says so), `payload_schema_violation` (fails the registered JSON Schema; `pointer` names the offending field). A **known** entityType is strictly validated; an **unknown** one with a well-formed envelope is accepted unvalidated, which is what keeps the entity set open for older servers.

## Attachments (blob pipeline – `SYNC.md`)

| Endpoint | Auth | Contract |
|---|---|---|
| `POST /blobs/begin` | bearer | `{ sha256, size, contentType }` → `{ status: "exists" }` \| `{ status: "upload", url: <presigned PUT>, expiresAt }` \| `413` size cap (images 25 MB, PDFs 10 MB per `SYNC.md`) \| `429` quota, carrying `quotaUsedPercent` (see "Error envelope"). |
| `POST /blobs/commit` | bearer | `{ sha256 }` → `204` after server verifies object + size. Referencing records must push only after commit. |
| `GET /blobs/{sha256}` | bearer | `302` → short-lived presigned GET (~10 min, single object). `404` if not owned by this account. |

`begin` refuses a malformed body with `400` (a `sha256` that is not 64 lowercase hex digits, or a
missing/negative `size`) and a content type outside the allow-list with `415`; it answers `413` per
type (images 25 MB, PDFs 10 MB) and `429` when the account's metered storage quota (default 5 GB,
configurable) would be exceeded. `commit` verifies the stored object against the size declared at
`begin` (the server remembers it between the two calls) - a commit with no preceding `begin`, no
uploaded object, or a size mismatch answers `409` and creates no row; it is idempotent (`204` on
replay). A revoked device or deleted account gets `410` (`device_revoked`) on all three. A presigned URL is never
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
{ "from": "2026-08-01", "to": "2026-08-31", "base": "EUR",
  "coverageFloor": "1999-01-04",
  "rates": [
  { "date": "2026-08-01", "quote": "USD", "rate": 1.0800, "source": "ecb" } ] }
```

`coverageFloor` is an **additive** field (RV.158): the oldest date the feeds can
serve for the requested base, or `null` when no feed states a bound. A device
walking a multi-year span reads it to stop asking for dates below the floor,
which no feed can ever answer; a range inside coverage that happens to be empty
is a legitimate gap and is NOT a reason to stop. It does not change the
`rates` array, the status, the cache headers or the backfill trigger, so an
older client that ignores the field behaves exactly as before.

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


### `GET /reference/station-brands` **[planned, RV.115]**

The station **brand** vocabulary, so four spellings of one chain group as one. Same contract as
`GET /catalog`: **public** (no auth - a signed-out user importing a file still needs it), ETag +
`Cache-Control`, a versioned pack the client replaces wholesale, `since_version` for a delta. It is
reference data, not a domain query, so hard rule 9 holds and no new exception is needed.

**Brands, never individual forecourts.** A global list of every petrol station is a maintenance and
privacy problem; a list of brands with their alias spellings (`Газпром` / `Газпромнефть` /
`Gazpromneft` / `G-Drive`) is small, stable, and enough to answer "what do I spend at this chain".
Individual stations stay per-account `Station` entities that sync with the user's own data.

A matched brand is a **default the user can change** (hard rule 13), and a name the user typed or
corrected is theirs permanently - no later pack may rewrite it, the same rule `SYNC.md` states for
the vehicle catalog. A name matching no brand is a first-class state: the user's own station, no
brand, not an error.

**Relevance is ordered on the DEVICE, and the pack carries `country` per brand** (decided
2026-09-07 with the product owner, who raised it as "order by the user's IP country, and fall back
to previous entries when a VPN lies"). The goal is right and the placement is inverted, for four
reasons:

1. **The user's own history beats IP in every case, not only under a VPN.** Which brands they
   actually fuel at is the strongest signal there is, and only the device has it (hard rule 1:
   local-first, and hard rule 9: the server must never read the user's entries to find out).
2. **Geo-IP would make a public, ETag'd pack uncacheable** - the response would have to `Vary` by a
   country the CDN derives per request, which fragments the cache and turns a static artefact into
   a per-request computation.
3. **It is the pattern this file already uses.** `GET /reference/fuel-price-bands` carries
   `country` on every row and the section below states it takes "no query parameters that make it a
   query". Station brands follow that exactly.
4. A brand-new user with no history still gets a sensible order from the **device region** (and, if
   they are travelling, from the first station they log) - without the server learning anything.

So the endpoint stays a static, country-tagged, fully cacheable pack, and the client orders it:
**brands the user has already used, then brands of the device's region, then the rest.** No geo-IP
dependency, no VPN failure mode, no per-user server behaviour.

**A captured receipt outranks all of it** (product owner, 2026-09-07). If the user is capturing,
they are standing at the station, and the slip already names it: the extraction reads the station
string, and the **currency, the VAT rate, the script and the phone format** together imply the
country - `receipt-051` in the corpus is Cyrillic, RUB, a Russian fiscal block; `receipt-049` and
`-050` are Estonian, EUR, "24% KM". That is a local, present-tense signal no IP can beat, and it
costs nothing: the OCR has already run. So the ordering is **the receipt in hand, then the user's
history, then the device region, then `detectedCountry`.** It also closes the loop with the matcher:
the station string the receipt yields is exactly what needs brand-matching, and once matched that
fill joins the history that orders every later list.

**`detectedCountry`: the cold-start hint (product owner, 2026-09-07).** The one case the ordering
above serves poorly is a brand-new user whose device region does not match where they are and who
has logged nothing yet. The server already sees the connection's IP on every request, so it may
return a coarse country as a **hint** - and the rule that keeps this from undoing everything above
is where it may ride:

> **Only a per-request, uncacheable response may carry `detectedCountry`. No cacheable one ever
> may.** `POST /auth/session`, `GET|POST /sync/*`, `POST /import/parse` and `POST /extract` qualify.
> `GET /catalog`, `GET /config`, `GET /rates*` and `GET /reference/*` are ETag'd artefacts and must
> not - that is exactly the `Vary` fragmentation this design avoided.

`POST /import/parse` matters most: it is the one uncacheable call a **signed-out** user makes, and
importing a foreign file is precisely when the brand list is needed.

Three bounds, so this stays a hint and not a new thing we know about people:

- **It is derived per request from the connection IP and never stored** - not on the account, not in
  a log line beyond shape (hard rule 12), not in the four places that hold user content
  (`CLAUDE.md` rule 9). A country that is computed, returned and forgotten adds no fifth place.
- **It is a DEFAULT INPUT, never a fact** (hard rule 13): it breaks ties in the client's ordering and
  is outranked by the user's own history and by anything the user has chosen. It never rewrites a
  station, a currency or a car's settings.
- **It is advisory and absent-able.** A client that gets no `detectedCountry` (offline, an older
  server, a proxy that hides it) orders by history and device region exactly as before, so nothing
  depends on it.

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
  years      = [firstYear, lastYear] inclusive, or null. A line still in production
               carries a null lastYear - [2021, null] - never a bare null, which
               would throw its start year away
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

> **Breaking change (2026-09-04):** `years` gained a **nullable last year**.
> A model line still in production used to serialize as `years: null` - the
> endpoint emitted the pair only when BOTH bounds were present - which threw
> away a start year the database held and the seed pack could express. The
> client's `yearsStart` then read `0` and Add-car autocomplete rendered "0-".
> It now emits `[2021, null]`, and `null` means only "no range at all". The
> publish path accepts the same shape, so a pack can express an open-ended
> line. The only consumer is this repo's own iOS client, changed in the same
> commit; nothing has shipped against the old shape.

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
`[ { id, displayName, fileKinds, helpUrl?, addedInPackVersion, unsupportedColumns } ]`, ETag'd like the other reference
data. Today it lists two formats: `{ id: "mfm", displayName: "My Fuel Manager", fileKinds: ["csv"], helpUrl: "https://tankbook.live/import-guide/", addedInPackVersion: 1, unsupportedColumns: ["Vehicle price", "Initial tank status", "LPG tank volume", "Initial LPG tank status", "Color"] }` and `{ id: "drivvo", displayName: "Drivvo", fileKinds: ["csv"], helpUrl: "https://tankbook.live/import-guide/", addedInPackVersion: 1, unsupportedColumns: ["Second fuel", "Third fuel", "Charge type", "Charge start %", "Charge end %", "Charge duration", "Driver", "Expense type", "Payment method", "Discount", "Local cost"] }`.

**`unsupportedColumns` is the format's complement, declared here and nowhere else (RV.116).** Every
foreign format carries columns Tankbook has no home for - Drivvo's `Водитель` (driver), payment
method, discount, the second/third fuel blocks and the EV columns; MFM's unmapped vehicle fields.
The parser reads what it understands and the rest used to evaporate silently: a fleet user importing
a driver-per-row history discovered only later that the column they cared about was gone. This is
**not** hard rule 8 (nothing is deleted - the source file is untouched and the rows the app keeps are
complete); it is a **completeness promise**, so the review gate says what is not coming in. The
**names** live here because they are static per parser and a new importer must not be able to forget
them; the **count of rows that carried a value** cannot live here - only `POST /import/parse` has
read the user's file. The client renders whatever names the server declares, so a column this build
has never heard of still renders (nothing is keyed on a known name). A column empty in every row is
omitted from the parse response: a notice about nothing buries the column that matters.

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
   ambiguities: [ { kind: "dateFormat" | "currency" | "units" | "outOfScope", options, rowCount } ],  // `units` reserved, no v1 parser emits it
   vehicleGroups: [ { name, sourceRows } ]?, unsupported: { <column name>: <row count> }? }`

- **The response gained `unsupported` on 2026-09-10 (RV.116) - a contract change, additive only.**
  It maps each of the format's `unsupportedColumns` that **carried a value in at least one row** of
  this file to that row count, so the review gate can say *"Driver, payment method and discount are
  not imported (250 rows carry a driver)"* before anything is written (F6a). Only a **count** and a
  **column name** cross the wire; no cell content does (hard rule 12). The field is **new**: an older
  client that never heard of it decodes the rest of the response exactly as before, and a stored
  parse that predates the field omits it - the device then shows no notice, never an error. The
  counts sum across the files of a whole-export pick, exactly as the ambiguities' row counts do.

- **The response gained `vehicleGroups` on 2026-09-06 (RV.86) - a contract change, additive
  only.** A file can hold several cars (the real MFM export has five), and before RV.86 the parser
  silently ignored the file's vehicle-name column, so every row landed on one car. `vehicleGroups`
  is the parse grouped by that column: one `{ name, sourceRows }` per distinct vehicle in **first
  appearance order**, `sourceRows` being the 1-based data-row numbers of the group's candidates.
  The field is **new**: an older client that never heard of it decodes `candidates` exactly as
  before (it ignores the extra key), and a stored parse that predates the field omits it - the
  device re-derives the same groups from each candidate's `vehicleName`. A format whose rows carry
  no vehicle name emits a single group. Grouping never guesses a mapping: the **device** asks the
  user which groups to bring in and where each lands, and the server never sees the answer
  (the endpoint still commits nothing).

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
- **Ambiguity is returned, never guessed** - the F6 once-per-file questions, applied client-side.
  The date order is a property of the WHOLE file, not of any one row (RV.85): one export has one
  format, so the parser reads every row before deciding whether to ask:
  - `dateFormat` (`M/D/YYYY` vs `D/M/YYYY`): emitted **only when the file's own rows cannot settle
    the order** - every date has both components ≤ 12, so no row proves which reading the file uses.
    `options` names both readings and `rowCount` is the number of genuinely ambiguous rows (both
    components ≤ 12, so the same string would parse either way). The candidates carry the format's
    M/D convention; if the user answers D/M, the client flips exactly the counted rows. A file any
    row settles is **resolved, not asked**: a row only M/D can read (a day > 12 in the second slot,
    e.g. `05/13`) proves M/D, a row only D/M can read (a day > 12 in the first slot, e.g. `13/05`)
    proves D/M, and the parser applies the proven order to **every** row - including the
    individually ambiguous ones - and returns no `dateFormat` ambiguity. **A file whose rows prove
    BOTH orders is not an ambiguity: it is an inconsistent file** (below, the `import_inconsistent_dates`
    422) - no single answer exists for the user to pick, so it errors rather than asks.
  - `currency`: for a file that declares one, `options` is the single currency it declares on every
    row (the real MFM export reads `USD` regardless of where fuel was bought) - a **default the
    user corrects** (hard rule 13), never a fact. For a file with **no currency column** (Drivvo),
    `options` is **empty** and `rowCount` is the number of money-carrying rows: there is no answer
    on disk to declare, so the client asks the currency question once, defaulting to the
    **destination car's home currency** (hard rule 3 - money is a pair, so nothing is guessed).
    Candidates' `money.currency` is the empty string in this case, never a hardcoded default.
  - `units`: **reserved and not emitted by any v1 parser** - both shipped importers (MFM, Drivvo)
    are metric. The kind stays on the wire so the first imperial importer (P5.4b) needs no contract
    change; until then no `units` ambiguity can arrive, and none is expected client-side.
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
- `413` oversize (`payload_too_large`), `415` unrecognised format id (`import_format_unsupported`),
  `422` **the file does not look like the format the
  user declared** (`import_mismatch`) - the client says so specifically ("this does not look like a My Fuel Manager
  export") and offers the picker again, never a generic failure (F7 forbids "something went wrong").
  `422` `import_inconsistent_dates` (RV.85): the file IS the declared format, but its dates mix two
  orders - some rows only parse `M/D/YYYY`, others only `D/M/YYYY` - and one export has one format,
  so no single reading fits. Not the `dateFormat` question (a file with no single answer cannot be
  answered correctly), the whole file is refused and the client shows the inconsistent-file message
  with its next step (correct the dates in the export), never the mismatch card and never the
  date-format question.
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
Status codes: `400` unknown `kind` or missing/undecodable `image` (`payload_invalid`); `413` base64 image over the 4 MB cap (`payload_too_large`, enforced at the envelope, before the provider is called); `502` provider failure (`upstream_unavailable` – not metered, a failed call never bills, and the client falls back to the on-device result). A low-confidence field is returned as a value plus a low confidence – never dropped, which would silently turn "uncertain" into "absent".

**The audit write is off the critical path of the answer (amended 2026-09-04, RV.53).** A
storage outage must not destroy a recognition the user already paid for. The ledger row is
written synchronously and a failure to write it can no longer fail the request: the rendition
blob is best-effort (a blob-store outage drops the rendition, records the row without it, and
the request still returns the extraction), and a row whose insert fails is queued
(`llm_ledger_pending`, `docs/SECURITY.md` "The ledger write queue") for a bounded retry instead
of thrown. The provider-failure `502` is unaffected and is never masked by a coincident storage
outage. A queue holds ledger rows, never images.

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
