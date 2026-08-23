# Tankbook – Backend API Contract

*The complete HTTP surface of the C#/ASP.NET Core backend. Shapes reference `SCHEMA.md` (payloads) and `SYNC.md` (protocol semantics). This document is the contract both the iOS client and the backend implement against – changes here are breaking-change reviews, not refactors.*

Conventions: JSON bodies, ISO-8601 UTC dates, UUIDs as strings. Errors use RFC 7807 problem+json: `{ type, title, status, detail }`. All endpoints are TLS-only. Rate limits return `429` with `Retry-After`.

## Auth

| Endpoint | Auth | Purpose |
|---|---|---|
| `POST /auth/session` | identity token | Exchange a Sign in with Apple / Google ID token for a session. Body: `{ provider: "apple"\|"google", idToken, device: { name, platform } }` → `{ accessToken (JWT, ~1h), refreshToken, accountId, deviceId }`. Creates the account on first sign-in (email from the verified token; Apple private relay respected) – there is no separate registration endpoint. **No account linking in v1**: Apple and Google identities are distinct accounts; the client handles the wrong-provider case in UX (JOURNEYS J11a), the API just returns whichever account the token maps to. Registers/updates the device row. |
| `POST /auth/refresh` | refresh token | `{ refreshToken }` → new token pair. Refresh tokens rotate; reuse of a rotated token revokes the chain (theft signal). |
| `DELETE /auth/session` | bearer | Sign out this device (revokes its refresh chain; local data stays local). |

All endpoints below marked **bearer** take `Authorization: Bearer <accessToken>`. **public** = no auth.

## Sync (the core – "latest data" and "changes")

Full semantics: `SYNC.md`. Both endpoints are idempotent.

### `GET /sync/pull` — bearer
Fetch changes since a cursor. **Fetching the latest data IS pulling from 0** – fresh install/restore and incremental catch-up are the same call.

```
GET /sync/pull?since=<SCN>&limit=500        // since=0 → full dataset
→ 200 { records: [ { id, entityType, scn, payload, clientUpdatedAt, deleted } ],
        nextSince: <SCN>, more: bool }
→ 410 device revoked / account deleted → client re-onboards or detaches
```
Strictly SCN-ordered, paginated; the client persists `nextSince` per device only after applying the page.

### `POST /sync/push` — bearer
```
{ changes: [ { id, entityType, baseScn,     // 0 for new records
               payload, clientUpdatedAt, deleted } ] }   // ≤ 200 changes/batch
→ 200 { results: [ { id, status: "accepted", newScn }
                 | { id, status: "conflict", current: <record> } ] }
```
Per-item outcomes; `conflict` returns the server's current record for client-side LWW merge + re-push (SYNC.md S1/S6). Payloads with `clientUpdatedAt` >24h in the future are clamped and flagged in the result.

## Attachments (blob pipeline – `SYNC.md`)

| Endpoint | Auth | Contract |
|---|---|---|
| `POST /blobs/begin` | bearer | `{ sha256, size, contentType }` → `{ status: "exists" }` \| `{ status: "upload", url: <presigned PUT>, expiresAt }` \| `413` size cap (images 25 MB, PDFs 10 MB per `SYNC.md`) \| `429` quota. |
| `POST /blobs/commit` | bearer | `{ sha256 }` → `204` after server verifies object + size. Referencing records must push only after commit. |
| `GET /blobs/{sha256}` | bearer | `302` → short-lived presigned GET (~10 min, single object). `404` if not owned by this account. |

## Reference data (public, CDN-cacheable)

| Endpoint | Auth | Contract |
|---|---|---|
| `GET /rates?date=&base=` | public | All quotes for one date. Past dates: `Cache-Control: immutable`. |
| `GET /rates/pack?from=&to=&base=` | public | Bulk range for device cache / seed refresh. |
| `GET /catalog?since_version=` | public | Vehicle catalog delta or full pack + `packVersion`. ETag'd. |

## Feedback

### `POST /feedback` — public (bearer optional)
```
{ category: "feature" | "problem" | "other", text,
  appVersion, deviceModel?, replyTo? }        // deviceModel only with the user's toggle
→ 202
```
Account id attached when a bearer token is present; rate-limited per device/IP; `text` ≤ 4 KB. No log content, ever.

## LLM gateway (Pro)

### `POST /extract` — bearer
`{ kind: "receipt" | "pump" | "chargeScreenshot" | "invoice", image: <base64 ≤ 4 MB>, hints: { currency?, locale?, vehicleFuelKinds? } }` → `{ fields: { <FieldRef>: { value, confidence } }, pipeline }` per SCHEMA.md `ExtractionMeta`. `402` when the tier lacks quota, `429` per-period quota spent (client falls back to on-device result – JOURNEYS F4; **never an upsell mid-capture**). Images processed transiently – never stored, per the signed-off stance.

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
