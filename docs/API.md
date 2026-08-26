# Tankbook – Backend API Contract

*The complete HTTP surface of the C#/ASP.NET Core backend. Shapes reference `SCHEMA.md` (payloads) and `SYNC.md` (protocol semantics). This document is the contract both the iOS client and the backend implement against – changes here are breaking-change reviews, not refactors.*

Conventions: JSON bodies, ISO-8601 UTC dates, UUIDs as strings. Errors use RFC 7807 problem+json: `{ type, title, status, detail }`. All endpoints are TLS-only. Rate limits return `429` with `Retry-After`.

## Auth

| Endpoint | Auth | Purpose |
|---|---|---|
| `POST /auth/session` | identity token | Exchange a Sign in with Apple / Google ID token for a session. Body: `{ provider: "apple"\|"google", idToken, device: { name, platform } }` → `{ accessToken (JWT, ~1h), refreshToken, accountId, deviceId }`. Creates the account on first sign-in (email from the verified token; Apple private relay respected) – there is no separate registration endpoint. **No account linking in v1**: Apple and Google identities are distinct accounts; the client handles the wrong-provider case in UX (JOURNEYS J11a), the API just returns whichever account the token maps to. Registers/updates the device row. |
| `POST /auth/refresh` | refresh token | `{ refreshToken }` → new token pair. Refresh tokens rotate; reuse of a rotated token revokes the chain (theft signal). |
| `DELETE /auth/session` | bearer | Sign out this device (revokes its refresh chain; local data stays local). |

Failure statuses (all `problem+json`, reason in `detail`): a session exchange whose `idToken` does not verify (garbage, expired, bad signature, unverified email) returns `401`; an unsupported `provider` or a malformed body returns `400`. A refresh with an unknown, expired, or reused-rotated token returns `401` (reuse additionally revokes the chain). Sign-out returns `204`, or `401` without a valid bearer token.

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
| `GET /catalog?since_version=` | public | Vehicle catalog delta or full pack + `packVersion`. ETag'd. |

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
unbounded span.


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

## Feedback

### `POST /feedback` – public (bearer optional)
```
{ category: "feature" | "problem" | "other", text,
  appVersion, deviceModel?, replyTo? }        // deviceModel only with the user's toggle
→ 202
```
Account id attached when a bearer token is present; rate-limited per device/IP; `text` ≤ 4 KB. No log content, ever.

## LLM gateway (Pro)

### `POST /extract` – bearer
`{ kind: "receipt" | "pump" | "chargeScreenshot" | "invoice", image: <base64 ≤ 4 MB>, hints: { currency?, locale?, vehicleFuelKinds? } }` → `{ fields: { <FieldRef>: { value, confidence } }, pipeline }` per SCHEMA.md `ExtractionMeta`. `402` when the tier lacks quota, `429` per-period quota spent (client falls back to on-device result – JOURNEYS F4; **never an upsell mid-capture**). Images processed transiently – never stored, per the signed-off stance.

Status codes: `400` unknown `kind` or missing/undecodable `image`; `413` base64 image over the 4 MB cap (enforced at the envelope, before the provider is called); `502` provider failure (not metered – a failed call never bills, and the client falls back to the on-device result). A low-confidence field is returned as a value plus a low confidence – never dropped, which would silently turn "uncertain" into "absent".

#### The device's side of `/extract` (normative)

The endpoint is only half the contract. Two device-side rules are part of it, because the server
cannot enforce either and the user experience depends on both.

**1 · The image is downscaled and compressed before upload.** A full-resolution iPhone capture is
several megabytes; uploading one over a forecourt's cell signal is the slowest step in the whole
flow by an order of magnitude, and the 4 MB envelope cap is a ceiling, not a target. The device
therefore sends a **long-edge-bounded, JPEG-compressed** rendition (start at long edge 1600 px,
quality 0.7, and tune down only against the corpus, below).

**Compression is a measurable trade, not a free one.** Fuel receipts are thermal print: the
digits that matter are small, and over-compression eats exactly them. So the compression settings
are **gated on the corpus** - re-score the receipt fixtures through the compression step with the
existing scorer (`AccuracyRatchetTests`), and if hits fall, the settings are too aggressive. This
is what stops "make the upload faster" from quietly becoming "read the receipt worse".

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

## Explicitly not in the API

No domain queries (server never interprets records – no `/entries?vehicle=` endpoints, ever), no server-side search or stats, no photo transforms. If a feature seems to need one of these, the answer is a client-side computation over the synced data – see SCHEMA.md principle 2.
