# Tankbook – Synchronization Design

*How one account's data stays consistent across devices (and later platforms). Companion to `SCHEMA.md` (entity shapes) and `VISION.md` (principles). The backend is C#/ASP.NET Core + PostgreSQL.*

## Model in one paragraph

Local-first with a server hub. Every device owns a complete local database and works fully offline; the backend keeps the account's authoritative change history. Devices **push** local changes and **pull** others' changes through a per-account monotonic sequence (SCN – server change number). Conflicts are resolved record-level last-writer-wins on the client – **except `Vehicle`, which merges field-level** so a stale device cannot revert a setting the user deliberately changed (S9, hard rule 13) – then re-validated by the domain rules (the odometer timeline check catches what LWW can't). No account = no sync, everything else works – sign-in is the moment multi-device turns on.

**What this replaces:** CloudKit as the sync engine. One sync system, ours, serving iOS now and Android later with identical semantics. (CloudKit would give iOS free sync but nothing to Android, and running both would double every consistency bug.) The account session lives in the **device-local Keychain only** (`…ThisDeviceOnly`, never iCloud Keychain – a synced session would silently defeat per-device revocation; see `SECURITY.md`); the OS photo library and files are untouched.

## Server data model

The server stores *records*, not domain tables – it never interprets entries, so the domain schema evolves without server deployments:

```sql
accounts   (id uuid pk, apple_sub text unique, google_sub text unique, email text not null,
            created_at timestamptz, deleted_at timestamptz,
            llm_tier text not null default 'free')             -- cloud-extraction entitlement, API.md "LLM gateway (Pro)"
devices    (id uuid pk, account_id fk, name text, platform text, last_pull_scn bigint,
            last_seen_at timestamptz, push_token text null,   -- APNs/FCM token, NOTIFICATIONS.md
            last_nudged_at timestamptz null,                  -- sync-nudge throttle, NOTIFICATIONS.md
            revoked_at timestamptz null)                       -- set by revoke-device; next pull gets 410
records    (account_id fk, id uuid, entity_type text,        -- "vehicle" | "fillup" | …
            schema_version int not null,                     -- payload contract version (see below)
            scn bigint,                                      -- per-account monotonic, assigned on write
            payload jsonb,                                   -- the entity, validated against the registered schema
            client_updated_at timestamptz,                   -- device clock, for LWW
            deleted boolean default false,                   -- tombstone
            origin_device uuid,
            primary key (account_id, id))
payload_schemas    (entity_type, schema_version, json_schema jsonb, primary key (entity_type, schema_version))
payload_migrations (entity_type, from_version, to_version, transform jsonb, primary key (entity_type, from_version))
account_seq(account_id pk, next_scn bigint)                  -- SCN allocator, bumped in the write tx
blobs      (account_id fk, sha256 text, size_bytes bigint, storage_ref text,
            created_at timestamptz, primary key (account_id, sha256))
llm_usage  (account_id fk, period date, requests int, tokens bigint)
```

- `records.scn` has a per-account index; pull is `WHERE account_id = ? AND scn > ? ORDER BY scn LIMIT n`.
- **Forward compatibility of entity types:** `entity_type` is an open set (adding `tireset` or any future entity needs zero server changes). Clients MUST preserve records whose `entity_type` or payload fields they don't understand – store opaquely, sync back unchanged, never drop. An older app version syncing against newer data keeps everything intact; it just doesn't render the new type until updated. (Same rule as backup's additive-evolution: unknown ≠ invalid.) This rule is not a promise, it is a **tested invariant** – see the round-trip test in "Payload contract".

## Payload contract and versioning

Opaque does not mean unchecked. A payload nobody validates is a payload any buggy client can poison, and a schema nobody versions is one that can never evolve. The contract below gives the payload a defined, enforced shape **without** the server learning domain meaning.

### The envelope

`records` carries the version as a **column**, not buried in JSON, so the server can filter and migrate without parsing domain content:

```sql
records (account_id, id, entity_type text, schema_version int not null, payload jsonb, …)
```

`payload` is always a JSON **object** holding exactly the entity's fields as `docs/SCHEMA.md` defines them for that `schema_version`.

### What the server enforces (structure, never meaning)

On every push, per change:

| Check | Failure |
|---|---|
| `payload` is a JSON object, ≤ 256 KB | `422 payload_invalid` |
| `entity_type` non-empty, ≤ 64 chars | `422 payload_invalid` |
| `schema_version` is an int in `[minSupported, maxKnown]` | `409 schema_version_unsupported` (too new: the *server* needs updating – say so) |
| Client's `schema_version` < server's `minSupported` | `426 upgrade_required` – **push refused, pull still allowed** so the user is never locked out of their own data, only prevented from writing stale shapes |
| Payload validates against the **registered JSON Schema** for (`entity_type`, `schema_version`) | `422 payload_schema_violation`, naming the failing JSON pointer |

Unknown `entity_type` with a well-formed envelope is **accepted unvalidated** – that is what keeps the open set open (a future `tireset` from a newer client must survive an older server). Known types are strictly validated.

### The schema registry lives in the database, not in code

```sql
payload_schemas (entity_type text, schema_version int, json_schema jsonb,
                 PRIMARY KEY (entity_type, schema_version))
```

Schemas are seeded by ordinary SQL migrations. **Adding or evolving an entity is therefore a data change, not a backend deploy** – which is the property the original "opaque payload" decision was really protecting. The canonical schema files live in `docs/schemas/v<N>/<entityType>.schema.json`, are generated from the domain model, and are the single artifact both the iOS client and the C# server validate against.

### Migrating payloads (the part a DDL migration does not cover)

Two layers, because neither alone is sufficient:

**1 · Client-side upcasting – the primary mechanism.** Every client carries ordered upcasters (v1→v2→v3…). Any record pulled at a lower version is upcast in memory before use; every write emits the current version. This works offline, needs no server, and is what makes a local-first app survive its own evolution.

**2 · Server-side backfill – for convergence.** Client upcasting alone never finishes: an entry nobody edits stays at v1 forever, so `minSupported` can never advance and clients carry upcasters indefinitely. So each schema version ships an optional **declarative transform** – an ordered list of mechanical operations (`rename`, `addDefault`, `wrap`, `removeDeprecated`) stored beside its schema:

```sql
payload_migrations (entity_type, from_version, to_version, transform jsonb, PRIMARY KEY (entity_type, from_version))
```

A batched, idempotent, resumable job applies pending transforms across `records`. It is mechanical JSON surgery – the server still never learns what a litre is. **Backfill does not allocate new SCNs** (it is not a user edit; bumping SCNs would fake a change on every device and stampede the pull stream); it rewrites payload and schema_version in place. Clients therefore must treat schema_version as advisory-on-read: always upcast to current before use, whatever the record claims.

Anything not expressible as a declarative transform is client-only migration, and `minSupported` simply waits longer. That constraint is a feature: it keeps domain logic out of the server by construction.

**RV.48 is the easy end of this mechanism: no transform at all.** It adds one optional
property – `Attachment.extractionMeta` (an `ExtractionMeta?`) and the optional
`FieldExtraction.value` inside it. Both are **additive and optional**, so this is a data
change (a schema update, seeded by SQL), never a backend deploy. The ordered-operation list
(`rename`, `addDefault`, `wrap`, `removeDeprecated`) has nothing to express here:

- **An older client reading a newer payload** decodes `extractionMeta` as absent (the key is
  unknown) and re-emits it unchanged via the round-trip preservation rule – the assignment is
  never dropped, only unrendered. `FieldExtraction.value` unknown tags decode to nil the same
  way (`FieldExtraction.init(from:)` uses `try?`), and the codec's unknown-key preservation
  re-emits the raw `value` bytes.
- **A newer client reading an older payload** finds no `extractionMeta` and decodes it to
  nil – the recognised page falls back to the raw-text disclosure, exactly the pre-RV.48
  behaviour. No `addDefault` is needed because nil already means "nothing was assigned".

The registered JSON Schema for `attachment` gains the `extractionMeta` property and the
`fieldValue` definition (both optional), so validation stays strict on structure while the
absence of either is a valid, well-formed payload.

### How this is assured (tests, not promises)

- **Schema coverage**: every `entityType` in SCHEMA.md has a registered schema at the current version. A new entity without its contract fails the build.
- **Fixture corpus**: `docs/fixtures/payloads/v<N>/<entityType>.json` holds representative payloads per version. Every fixture validates against its own version's schema.
- **Upcast completeness**: every v<N> fixture upcasts cleanly to current and validates against the current schema.
- **Cross-implementation parity** – the important one: the Swift upcaster and the server's declarative transform must produce **byte-identical** output for every fixture. This is what stops the two implementations silently drifting apart, and it is why the transforms are data rather than code in two languages.
- **Round-trip preservation**: a record with unknown fields and an unknown entity_type survives decode → encode unchanged (the forward-compatibility rule above, made executable).
- Attachments are content-addressed blobs in S3-compatible storage; `payload` references them by sha256. Upload before push, download lazily after pull.
- Backups (the F7 restore path and user-held export) become a *byproduct*: a server-side snapshot of `records` at an SCN, in the SCHEMA.md backup format. No separate backup pipeline to maintain.

## Protocol

Two endpoints, both idempotent:

```
POST /sync/push   { changes: [{ id, entityType, baseScn, payload, clientUpdatedAt, deleted }] }
  → { results: [{ id, status: accepted(newScn) | conflict(currentRecord) }] }

GET  /sync/pull?since=SCN&limit=500
  → { records: [...], nextSince: SCN, more: bool }
```

Device identity is carried by the bearer token (assigned at `POST /auth/session` – `API.md` is authoritative for the HTTP surface); no explicit deviceId parameters.

**Sign out (RV.40).** The Settings "Sign out" control revokes this device's refresh chain
server-side (`DELETE /auth/session`, **best-effort** - a handed-over phone must not keep a 90-day
chain valid) and clears the local session, in that order, with the clear unconditional (offline
sign-out still signs out locally, hard rule 1). It is **not** a device revoke: the `devices` row
survives with `revoked_at` NULL, so a later sign-in reuses the same row (`API.md` -> "The device id
is a client-supplied, unverified claim"). It is **not** account deletion: the local log is
completely untouched, and unsynced changes are never silently dropped - the confirmation names the
dirty count and that the changes are kept, and the user decides (hard rules 7 and 8). The distinct
`DELETE /account/devices/{id}` (Revoke, on the Account & devices screen) is the one that marks the
row revoked; ordinary sign-out is the milder control that sits between "keep syncing" and it.

- **Push:** for each change, if `baseScn` matches the server's current SCN for that id (or the record is new), the server writes it and assigns the next SCN. Otherwise → `conflict` with the current server record; the client merges and re-pushes with the new base. First-writer-wins at the transport level; the *merge* decides content. **Idempotent replay:** a `baseScn` of 0 against an id the server already holds (a new-record push whose response the client never received) returns the same accepted outcome with the record's existing SCN - it never writes a second row or allocates a second SCN. This is what makes the endpoints idempotent "by id + baseScn".
- **Pull:** strictly ordered by SCN, paginated, cursor stored per device (`last_pull_scn`). A device that was offline for a year just replays the stream. Fresh install + sign-in = pull from 0 (this IS restore).
- Sync cycle: pull → merge → push, triggered on app foreground, after every local write (debounced), and by push notification nudge (silent APNs "there's news" – no content in the push).

## Client state & merge

Each local row carries `syncState: synced(scn) | dirty | pushing`, plus the SCHEMA.md envelope (`updatedAt` = `clientUpdatedAt`).

**Merge rule (v1): record-level LWW by `clientUpdatedAt`**, deterministic tiebreak by device id. Rationale: entries are small and edited rarely, almost never concurrently on two devices within seconds; field-level merge is a v2 refinement if real conflicts show up in telemetry counts.

**Exception – `Vehicle` merges field-level** (decided 2026-08-23). Every other entity stays record-level. `Vehicle` is the one record where record-level LWW breaks hard rule 13 ("the app suggests, the user decides – a user's edit is theirs permanently"), because it differs from an entry in all three ways the rationale above depends on:

- **It is long-lived and rarely touched**, so a device can hold a stale copy for *weeks*, not seconds. The concurrency window is not small.
- **Its fields are independent** – tank capacity, name, home currency, units, `archived` – and are edited at different times for unrelated reasons. An entry's fields describe one event; a vehicle's describe a dozen unrelated settings.
- **Its values feed maths, silently.** Reverting `tankCapacityL` does not look like a lost edit; it looks like partial-fill numbers quietly going wrong (S9 below).

So `Vehicle` carries per-field `updatedAt` (or an equivalent changed-field set on push) and merges field by field, newest write per field. Entries keep record-level LWW – S1 is unchanged, and its documented "the iPhone's odometer edit is lost" outcome still stands for entries.

**Client implementation notes (P4.5, landed with the sync client):**

- **The base SCN survives local edits.** The `syncScn` column is the *base* the next push names for conflict detection (S6). A local edit marks the row `dirty` but **preserves** `syncScn`; only a first-ever record has none (`baseScn = 0`). Nulling it on edit would turn a stale push into an idempotent replay that silently loses the conflict.
- **The merge is a pure value type** (`RecordMerge` in `TankbookCore/Sync/`): record-level LWW for everything, field-level for `Vehicle`, over plain `SyncRecord` values with no `URLSession` or database – that is what makes the S1–S9 suite deterministic and mutation-checkable.
- **A `Vehicle` field merge reports whether it changed anything** (RV.14). `mergeVehicle` compares the merged result against the two inputs at the decoded level – the `Vehicle` plus its per-field versions, never raw payload bytes, which do not converge across a lossy re-encode. It returns `.remote` when the result equals the remote (nothing local to push → applied as synced at the remote's SCN), `.local` when it equals the local (already correct → the SCN is recorded, no dirty), and `.fieldMerge` only when the merge genuinely produced a new write (→ dirty, push). Without this, a byte-identical vehicle pulled back after a push re-merges to `.fieldMerge`, is re-stored dirty, and pushes itself back forever.
- **Record-level LWW's `.local` arm compares decoded values, not bytes** (RV.35). When a synced record wins LWW against a pulled copy (clock skew), `applyPull` re-dirties it only if the record actually differs: `RecordMerge.recordsEqual` decodes both sides to the typed entity and compares those, falling back to payload bytes only when the type cannot be decoded. A lossy round-trip – a normalised number token (`1.0` vs `1`), a decimal string with a dropped trailing zero (`289.50` vs `289.5`), a date re-serialised without fractional seconds – changes the bytes without changing the record, and re-dirtying on those bytes pushed the record back forever (the preferences echo, 2026-09-03). A genuine decoded divergence, or a differing `deleted` flag, still re-dirties and pushes, so nothing is lost silently (hard rule 8).
- **`Vehicle` field versions travel in the payload** under the reserved key `fieldVersions` (a map of field name to ISO-8601 timestamp). A pushing device writes it by diffing the current payload against its last-synced payload; a pulling device reads it for the merge. The domain `Vehicle` type is unchanged – the key is opaque to the codec and preserved as forward-compatibility data.
- **The last-synced payload is a device-local table** (`syncPayloadMemory`), written on every successful push or pull and read when a dirty `Vehicle` is diffed (SCHEMA.md). It is bookkeeping like the sync cursor, never synced. Persisting it is what makes S9 survive a relaunch: in-memory, the baseline dies with the process, the first sync of the session diffs against nothing and stamps every field changed, and a stale device can then revert another device's newer edit (hard rule 13).
- **The losing version's undo log is a device-local table** (`syncOverwrite`), written when a merge overwrites a locally-authored (`.dirty`/`.pushing`) edit (S1/S4). It is bookkeeping like the sync cursor, never synced, and is what the Recently deleted "Overwritten by sync" section reads.

**Domain validation after merge, not during:** LWW can produce a timeline that violates the odometer invariant (two drivers logging the same car offline – JOURNEYS J12/F9a). The sync layer doesn't care; after every merge batch, validation re-runs locally and flags entries with the amber `ConflictState` – the *user-visible* conflict system and the *transport* conflict system stay decoupled. Nothing is ever dropped silently.

**Clock skew:** `clientUpdatedAt` is device-clock; the server stamps `received_at` and rejects timestamps > 24h in the future (clamps to server time, marks the record so the client can warn). Good enough for LWW between a person's own devices.

## Encryption stance

**Decided (signed off Aug 23, 2026): TLS in transit + at-rest encryption on server storage, no end-to-end encryption in v1.**

Honest reasoning: E2E with multi-device + multi-platform + account recovery requires user-held key material (recovery codes) – the exact UX that loses non-technical users their data, which is this category's cardinal sin (F7). The server-side payload is fuel logs, not messages; the privacy promise we keep is *minimal collection, no analytics on content, delete-account-deletes-everything*, stated plainly. E2E stays on the roadmap as an opt-in for the paranoid tier once account recovery UX is solved. **This is a deliberate trade – flag for explicit sign-off.**

## Attachments: the blob pipeline

Photos (receipts, invoices, car photos) and PDFs don't ride the record stream – they're too big and immutable. They go through a content-addressed blob path.

### Where they're stored

**Private S3-compatible object storage** (decided over Postgres bytea – sync traffic and size make the DB the wrong home). Provider is an ops choice behind the S3 API: Cloudflare R2 (no egress fees – attractive since every new device re-downloads a garage's photos), Backblaze B2, or self-hosted MinIO; nothing in the design binds to one. Layout: one private bucket, keys `{account_id}/{sha256}` – content-addressed, so identical files dedupe per account and a key never changes. Postgres `blobs` table (already in the schema) holds the index: sha256, size, storage_ref, created_at.

**What gets uploaded – the size policy (resolves SCHEMA open question 3):** a *sync rendition* – JPEG, long edge ≤ 2048 px, quality ~80 (≈ 200–600 KB) – which is fully readable for receipts, invoices, and expense reports. The full-resolution original stays on the capturing device (and in that device's local export); it is never needed for OCR (which already ran) or cross-device viewing. PDFs pass through unmodified, capped at 10 MB. A tiny thumbnail (~120 px, ≈ 5 KB, base64) travels *inside* the Attachment record payload itself, so lists render photo chips instantly with zero blob fetches.

### Upload (device → storage, never through the API server)

```
1. Client computes sha256 of the rendition.
2. POST /blobs/begin { sha256, size, contentType }   (authenticated)
   → { status: exists }                              // dedupe: another device already uploaded it
   → { status: upload, url: presigned PUT, expires: 15 min }
   → 413 / 429                                       // size cap (25 MB) or storage quota exceeded
3. Client PUTs the bytes directly to the presigned URL (resumable retry: just re-begin).
4. POST /blobs/commit { sha256 } → server verifies object existence + size, inserts the blobs row.
5. Only THEN does the entry referencing it push – records never point at blobs the server can't serve.
```

Presigned upload means the ASP.NET server never proxies file bytes – it stays a small metadata API regardless of photo volume. Uploads queue offline like everything else (S7): the entry syncs text-first with the blob pending, and other devices show the thumbnail (from the payload) with a "photo syncing" shimmer until the blob lands.

### Delivery (storage → other devices)

- After a pull, the client fetches missing blobs **lazily**: thumbnails are already in payloads; the full rendition downloads when the user opens the entry (or eagerly on Wi-Fi, a setting).
- **Opening the attachment viewer (RV.9) is the second lazy trigger.** It reads the content-addressed cache first (synchronous, network-free), and only a miss goes through the same `LazyBlobFetcher` with its verify-on-download – unverified bytes are never cached and never displayed. A signed-out device has no fetcher at all: the viewer then shows the payload's inline thumbnail and names the next step (`docs/ERRORS.md` → Edit entry) rather than blocking or failing silently. Nothing about the viewer gates the entry (hard rule 1).
- **Share from the viewer (RV.17) is the third consumer of that on-demand fetch, not a second download path.** The viewer already fetches the full rendition on open; the Share affordance is offered only once that fetch has landed, so the bytes handed to the share sheet are always the verified full rendition – never the 44 pt payload thumbnail. When the fetch failed (offline, or the bytes did not verify), the share affordance is withheld, never a dead button (`docs/ERRORS.md` → Edit entry). The share itself exports a domain value by the user's deliberate act, which is fine; it is logged shape-only (that it happened and its outcome, never what was shared, its hash or its size – hard rule 12).
- **Deleting a receipt (RV.37) is a tombstone, never a file quietly unlinked.** The attachment record carries `deletedAt` and syncs like every other entity, and the entry is unlinked from the id in the same write transaction. Because attachments are content-addressed and shared (a mixed receipt's fill-up and expenses reference the SAME id), the tombstone is written only once no other live entry references it – deleting from one entry never blanks a sibling's receipt. The blob itself is left untouched: reclamation is the orphan sweep's job (below), which protects a blob while a tombstoned record is still inside the 30-day undo window.
- `GET /blobs/{sha256}` (authenticated) → `302` redirect to a short-lived presigned GET (TTL ~10 min, single object). The device caches the file locally forever after – content addressing means no revalidation, ever.
- New-device restore: text records first (the garage is usable in seconds), blobs trickle in background by recency. Restore never blocks on photos.

### Protection

- **Bucket is fully private** – no public ACLs, no listing; the only access path is a presigned URL minted after account auth, scoped to one object, expiring in minutes. Account isolation is structural: keys are prefixed by `account_id` and the API only ever signs within the caller's prefix.
- **At rest:** storage-side encryption (SSE) per the signed-off encryption stance; TLS in transit everywhere, presigned URLs included.
- **Integrity:** sha256 IS the identity – a corrupted or tampered object fails the client-side hash check on download and is re-fetched.
- **Hygiene:** contentType allow-list (JPEG/PNG/HEIC/PDF), server-verified size on commit, per-account storage quota (generous free tier, metered like LLM usage), orphan sweep (blobs unreferenced by any live record + grace period → deleted), and account deletion purges the whole prefix.
- **Not in scope deliberately:** server-side thumbnailing or image processing (the client ships both renditions – the server never opens user images), and virus scanning (nothing is ever served to anyone but the owning account's authenticated devices).

The **orphan sweep** is per-account and deletes a blob from both the index and storage when it was
committed longer ago than the grace period and no *protecting* record references it. A record
protects a blob when it is live (`deleted = false`) or was tombstoned within the grace period
(`deleted = true` with `client_updated_at` inside the window) and its payload carries the blob's
sha256. The grace period defaults to the 30-day undo window (hard rule 8), so a blob whose record
can still be restored is never swept out from under it. The reference check is a content-address
containment check - a sha256 is an identifier (Safe class, `LOGGING.md`), not a domain value - so
the server still never reads what a field means (hard rule 9). The per-account storage quota
defaults to 5 GB, is configurable, is enforced at `begin`, and is metered from the blob index
(`SUM(size_bytes)`), never from a stored counter that could drift.

## Reference data: server-curated packs (vehicle catalog, rates)

The vehicle catalog is **curated on the server**, and the server is the **master copy**. The app ships a
bundled seed pack, downloads updated packs into a cache, and **where the two overlap the server's values
win**. Same mechanism for exchange-rate packs (`P5`).

This is a *different channel from user-data sync*, and conflating the two is the mistake to avoid. Nothing
here has an SCN, a tombstone, a dirty queue or a conflict state, because the flow is **one-way and
read-only**: the server publishes, the device consumes, and the local copy is disposable – deleting the
cache costs a refetch and nothing else. None of S1–S9 apply.

### Three layers, in strict precedence

| Layer | Source | Survives |
|---|---|---|
| **1 · Bundled seed pack** | Compiled into the app bundle | Everything. Changed only by an App Store release |
| **2 · Cached pack** | Last successfully fetched + validated pack | Restarts, offline, backend outage |
| **3 · Server pack** | `GET /catalog?since_version=<n>` → delta or full pack, each naming its `kind`, + `packVersion` | Until the next fetch |

Deliberately the same shape as the remote-config layering (`CONFIG.md`), for the same reason: **the app
must be fully functional using only what is compiled into the binary.** Add-car autocomplete works on day
one, offline, with no account – so this is never a network dependency (hard rule 1).

### The master rule, and its one important limit

**On overlap, the server wins.** A cached entry with the same identity as a server entry is replaced, not
merged: curation exists precisely to correct wrong figures, and a device that clung to a stale tank
capacity would keep miscomputing partial fills. Entries the server no longer publishes are dropped on a
full pack (see "Applying an update" - the full pack is authoritative and replaces the client's held set).

**But this never touches user data.** Catalog values are *suggestions copied into the `Vehicle` row at
Add-car time*, and **no `Vehicle` ever references a catalog entry by id** (`SCHEMA.md` → Vehicle catalog).
So a corrected pack changes what the *next* car pre-fills and **never rewrites a car already in someone's
garage** – including a value the user typed over. "Server is master" governs the catalog, not the garage.
A user's override is theirs permanently.

### Applying an update

- **Delta by default**: the client sends the `packVersion` it holds; the server answers with the entries
  changed since, or a full pack when the delta would be larger or the client is too far behind. `ETag` /
  `If-None-Match`, so an unchanged catalog costs a `304`. The concrete threshold (how far behind is "too
  far") is a server rule - `Catalog:MaxDeltaEntries`, default 50 - stated and tested in `API.md`.
- **The response names its kind, and the kind decides how it is applied.** Every response carries
  `kind: "full" | "delta"` (P6.12) - a client never infers it from an entry count or from whether
  `since_version` was sent. A **full** pack is authoritative: the client **replaces** its held set with
  the pack's entries, so an entry absent from the pack was withdrawn and stops being offered. A **delta**
  **overlays** only the entries it mentions by identity and never removes anything. The bundled seed stays
  layer 1 underneath both, so Add-car suggestions work with no cache and no network (hard rule 1).
- **Removals travel in full packs.** A withdrawal is a physical delete at publish time - the operator
  names the dropped ids in `removedIds` on the catalog write (`API.md`; the publish endpoint was removed
  2026-09-01 and packs go straight to the database), the rows are deleted (never
  tombstoned - the server does not remember what it withdrew), and the subsequent full pack simply lacks
  them. A delta cannot express a removal; a client close behind the server that never pulls a full pack
  may retain a withdrawn entry until it does, which is exactly the trade the "dropped on a full pack"
  sentence in the master rule states.
- **Validated before it is applied, whole or not at all.** A pack that fails its schema is rejected
  entirely and the previous cache stands – the same all-or-nothing document rule as config. A partially
  applied pack is worse than a stale one.
- **`packVersion` is monotonic**: the client applies a pack only when its `packVersion` is **greater**
  than the one held. An older pack is ignored (rollback protection), and so is an **equal** one - an
  honest empty delta at the held version (or a `304`) means "nothing changed", not "re-publish", so the
  client's guard is `packVersion > held`, never `>=` (P5.7).
- **Overlap identity is the model line** - make/model/generation/powertrain - not the server row `id`:
  the bundled seed entries carry no server ids, so overlap must be decidable across all three layers
  without one. Two powertrain variants of one model line are distinct catalog rows and never replace
  each other (P5.7).
- **Atomic write** to the cache: temp file then rename, so a crash mid-write cannot leave a truncated pack
  that fails validation on next launch. The cache is regenerable, so it is **excluded from backups**.
- **Never at launch-blocking time.** Checked in the background, throttled; a cold start uses whatever is
  already there. Resolution is bundled-then-cache, so a device with no cache is simply a device on the
  seed pack.

### Where the cache lives

`Application Support/Tankbook/catalog.cache.json`, alongside the config cache and under the same file
protection class as the database. Kept as a plain file rather than in GRDB for the same reason config is:
it must be readable early, and it must survive a failed database migration. It is **not** user data, so it
is never part of a backup export.

### Curation feedback loop

"Model not found" search misses are logged **as counts only, never the typed text** (`SCHEMA.md`,
`LOGGING.md` – hard rule 12). Those counts are the curation roadmap: they say which models to add next
without recording what any individual searched for.

## Conflict resolution, scenario by scenario

Two layers, deliberately decoupled: **transport** (who wins the record – automatic, invisible, never loses the newer edit) and **domain** (does the merged timeline make sense – surfaced to the user via the existing amber `ConflictState`, F9a). The UX law across all scenarios: *conflicts surface where the data lives – a badge on the entry, a footnote on the stat – never as a modal, never as a "sync error" at sync time.*

### S1 · Same entry edited on two devices
iPhone edits the Shell fill-up's odometer at 14:02; iPad edits its note at 14:05; both were offline, both push later.
- **Transport:** record-level LWW → iPad's version (newer `clientUpdatedAt`) wins whole; the iPhone's odometer edit is lost.
- **Domain:** nothing to flag.
- **Screens:** nothing. The iPhone user may notice their edit reverted.
- **Verdict:** acceptable for v1 (one person editing the same entry on two devices within minutes is rare); the losing device keeps the overwritten version in a local 30-day undo log ("Entry changed by sync – restore my version") reachable from the entry's edit screen. Telemetry counts these; if real, field-group merge is the v2 fix.

### S2 · Duplicate capture of one physical fill-up
Both spouses (v2 sharing) – or one person with phone and CarPlay flow – log the same fill-up. Two records, different UUIDs: transport sees no conflict at all.
- **Transport:** both records sync everywhere.
- **Domain:** duplicate heuristic – same vehicle, dates within 30 min, volume within 5% – flags the pair.
- **Screens:** the Log shows one combined card: "Possible duplicate – Shell, 42.3 L logged twice" with *Keep both* / *Merge* (merge keeps the richer one: the one with an attachment wins, fields union). Until resolved, only ONE of the pair counts in consumption and totals, so stats never double.
- **The counted one is deterministic** (the entry a Merge would keep: the one with an attachment when exactly one has one, else the earlier-created, else the lower id) so the same data always produces the same numbers on every device, and consumption is continuous across a Merge – the survivor was already the one counting.
- **"Keep both" is a persisted user decision** – without it, the derived heuristic would re-flag the pair on every recompute. The resolution is a device-local `duplicateResolution` row (SCHEMA.md); syncing resolutions across devices is P4 work.

### S3 · Out-of-order odometers after merge (two drivers, both offline)
Driver A logs odo 119 486 on Saturday; driver B, offline in the countryside, logs odo 119 210 on Sunday (drove first, synced later).
- **Transport:** both records accepted – no conflict, different ids.
- **Domain:** merged timeline violates *date-sorted odometer increases* → B's entry gets the amber `ConflictState`; its segment is excluded from the headline.
- **Screens:** amber badge on the entry in the Log; Trends tile footnote "1 entry excluded"; opening the entry shows F9a's inline discrepancy with ranked fixes ("this entry belongs earlier" preselected – the dates, not the odometers, are usually what's wrong here). If a receipt is attached, its printed timestamp wins the date side, per the F9a priority rule.

### S4 · Edit vs delete
iPad deletes a mistaken entry; iPhone, offline, edits the same entry's price.
- **Transport:** LWW between the tombstone and the edit by `clientUpdatedAt`. Edit newer → the record resurrects with the edit (data loss beats ghost data – resurrect is the safe direction). Delete newer → it stays deleted; the iPhone's edit lands in the same local undo log as S1.
- **Screens:** on resurrection, nothing (the entry is simply there); on deletion winning, nothing – with undo reachable from the Log's "Recently deleted" (30 days).

### S5 · Vehicle deleted while entries still arrive
Device A deletes the sold Volvo entirely; device B, offline, logs one last fill-up to it.
- **Prevention first:** in UI, "delete vehicle" is really *archive* (J13); hard delete demands typed confirmation and cascades tombstones over its entries.
- **Transport:** B's new fill-up references a tombstoned vehicle → the vehicle resurrects as **archived**, entry attached.
- **Screens:** quiet notice card in the Garage: "Volvo V60 came back from another device with 1 new entry – it stays archived. Delete again?" One tap re-deletes; nothing is lost silently.

### S6 · Transport conflict on push (the invisible one)
Device pushes an edit with a stale `baseScn` because another device pushed first.
- **Transport:** server answers `conflict(currentRecord)`; the client re-merges (S1 rules) and re-pushes. Fully automatic, bounded retries.
- **Screens:** nothing, ever. This is plumbing.

### S8 · Currency conversion backfill across devices
A fill-up saved offline in Poland has `Money{289.50 PLN, homeAmount: nil}` (rate pending – F9). It syncs to the iPad, which has the rate feed cached.
- **Rule:** conversion backfill is **fill-blanks-only** (same principle as F5's QR enrichment): any device may write `homeAmount`/`rate` when they are nil, and no device ever recomputes an existing snapshot. Both devices backfilling concurrently write identical values (same feed, same `rateDate` = entry date), so the LWW winner is byte-equivalent – no user-visible effect.
- **Divergence case:** one device backfills from the feed while the user manually edits the rate on the other → LWW picks the newer; a losing *manual* rate (rateSource: .manual) lands in the S1 undo log, feed values don't (they're reproducible).
- **The rate cache itself never syncs** – each device fetches its own feed; only `Money` snapshots inside entries travel. A device with no feed access simply leaves entries pending; stats exclude them from home-currency sums with the F9 footnote until any device fills them.
- **Screens:** the foreign-currency confirm shows the conversion line ("≈ 67.79 € · 4.2706 zł/€ · ECB, Aug 21") or a soft "converts when online" chip; when backfill lands via sync, the entry's home amount simply appears – no toast, nothing was wrong.

### S9 · A stale device reverts a car setting (the rule-13 case)

The user corrects the Volvo's tank capacity 71 → 60 L on the iPhone on Monday. The iPad has not synced for a week and still holds 71. On Friday the iPad renames the car "Volvo" → "V60" – an unrelated field – and pushes.

- **Transport:** field-level merge on `Vehicle`. The iPad's write covers `name` only; `tankCapacityL` keeps the iPhone's newer value. Merged result: `name = "V60"`, `tankCapacityL = 60`. **Under record-level LWW the iPad's whole row would win and the correction would silently revert to 71.**
- **Domain:** nothing to flag. Both writes were legitimate and both survive.
- **Screens:** nothing – and that is the point. There is no conflict to surface, because nothing was lost.

**Why this one gets its own scenario:** the failure it prevents is invisible. A reverted tank capacity produces no badge, no toast and no wrong-looking number – just partial-fill maths that is quietly wrong from then on, and a user who "already fixed that". Contrast S1, where a lost note edit is at least noticeable to the person who made it.

The same reasoning covers `initialOdometer`, `homeCurrency`, `units` and `paceLimitKmPerDay`: all user decisions, all feeding calculations, all edited independently.

### S7 · Server unavailable – during everything above
The backend is down for a day; both devices keep logging, editing, deleting.
- **Behavior:** every write lands locally and queues as `dirty`; capture, stats, reminders, export – all unaffected (F3/F4). No banners, no toasts. The only surface is a passive row in Settings/Garage: "Waiting to sync · 5 changes" with a relative timestamp, turning to "Synced just now" on recovery.

### Low Power Mode – background work defers, the user's own taps never do

When iOS Low Power Mode is on, the app **postpones background and opportunistic work** and keeps
everything else exactly as it was. This is the same principle as S7: the queue waits, nothing is
lost, and no screen is gated.

**The load-bearing distinction is background vs user-initiated.** A deferral policy that cannot
tell them apart will postpone a restore or a "sync now" tap, and a user staring at a spinner that
was silently cancelled has no next step (hard rule 7) and reads as a hang.

| Defers while Low Power Mode is on | Never defers |
|---|---|
| Opportunistic sync cycles (launch, foreground) | Any **save** – always local, always immediate (hard rule 1) |
| Attachment/blob **upload** – the heaviest work there is; **prefetch** *(policy present, call site not wired)* | A sync, restore, export or retry the **user asked for** |
| Rate pack refresh (`RateStore.refresh`) | Capture, OCR and the confirm sheet the user is standing in |
| Vehicle catalog pack fetch *(policy present, call site not wired)* | An already-scheduled local notification |
| Any repeating timer job *(policy present, call site not wired)* | Reading, editing and deleting – the whole local app |

**Wired vs policy-only (P6.20).** Three of the rules above are *policy present, call site
not wired*: the `PowerWorkKind` case exists and `LowPowerPolicy.defers` covers it, but no
production code consults it today, so nothing enforces the deferral yet. They are **blob
prefetch** (there is no prefetch path), the **vehicle catalog pack fetch**
(`VehicleCatalogUpdater` consults the policy but is never instantiated in the app), and any
**repeating timer job** (no timer cycle exists - the same fiction the "launch, foreground and
timer cycles" phrasing once hid). The rules stay - they are what a future call site must obey -
but the enum and this table must not claim coverage they do not have. `LowPowerModeTests` pins
the split with a source-scan guard that fails when a case moves between the wired and unwired
sets without this doc moving with it.

**What the OS already does, and what it does not.** iOS disables Background App Refresh in Low
Power Mode and deprioritises discretionary `URLSession` work, so the app must neither duplicate
that nor rely on it: the gap the app closes is **foreground opportunistic** work – the sync it
starts on launch, the prefetch it starts on a WiFi change, the refresh it starts on a timer.

**Resume on the state change, not on the next launch.** `NSProcessInfoPowerStateDidChange` is the
trigger; a policy that only re-checks at launch leaves a device that left Low Power Mode hours ago
still holding its queue. The resumer lives in core (`LowPowerResumer`, injected `PowerStateProvider`
+ `NotificationCenter`): the app registers the deferred work - a background sync, the rate pack
refresh, the catalog fetch - as closures, and the resumer drains them when the mode ends.

**Blob upload defers even inside a user-asked sync.** "The heaviest work there is" waits while the
mode is on, full stop: a user-initiated sync pushes text and defers its blobs - the record stays
dirty and the entry syncs text-first with the blob pending, exactly as it does when the blob
transport is down (S7, upload step 5: a record never points at a blob the server can't serve). The
sync the user asked for runs; the heaviest network work still waits for power.

**Surface: the existing passive status row, and nothing else.** S7's row gains a reason, not a
severity – "Waiting to sync · 5 changes · Low Power Mode is on". It is **reassurance, never a
warning**: no amber, no badge, no toast, no modal (hard rule 8 – conflicts and waits surface where
the data lives, never as a modal at sync time), and it disappears when the mode ends. A user who
turned Low Power Mode on chose this; the app agreeing with them is not an error state. When the
reason shows, one companion line rides under the row, shaped exactly like the offline hint (P6.8):
"Low Power Mode is on – background sync and photo uploads wait, then resume automatically." It names
what is deferred and that the app resumes it by itself – the same reassurance the offline hint gives,
in the same `inkSoft`, never amber. It shows only while the mode is on AND a queue is waiting (the
reason, never the mode alone), and it vanishes with the reason the moment the mode ends.

**The power state is an injected value, never `ProcessInfo` read inline.** Same reason
`TabBarMetrics` and `PumpPhotoGate` are values in core: a policy that reads the device directly
cannot be tested, and this one's whole content is *when it says no*.

### The Settings sync surface (normative)

Three things live there, and the split between them is what keeps hard rule 8 intact.

1. **Status, always present when signed in.** A relative timestamp on the account card:
   "Synced just now", "Synced 3 hours ago", or "Waiting to sync · 5 changes" with
   "Will sync when you're back online" when there is no connection. It is **reassurance, never a
   warning**: it does not turn amber with age, and a long queue is not an error state, because a
   week offline is the same as an hour (S7). A status row that nags is a status row that teaches
   the user to babysit a queue the app is supposed to drain by itself.

   The signed-in reassurance line also carries the account's device count – "Synced just now ·
   1 device" (docs/JOURNEYS.md J11a -> Confirm). **The count is fetched from `GET
   /account/devices` once per membership, not once per appearance (RV.6).** It is a reassurance
   detail that changes on **events** – a sign-in, a sign-out, a revoke, an account delete – never
   on a clock, so it is cached across every surface refresh (Settings re-appearing after a pop
   back from Account & devices, a Low Power toggle, the end of a sync cycle) and re-fetched only
   when an event cleared it or it is still unknown (a guest, offline, or a fetch failure, which
   the next appearance retries). The decision is core (`DeviceCountCache`), so a second
   fetch-on-every-refresh cannot silently return; the Account & devices screen clears the cache
   the moment a revoke succeeds, and the Settings refresh clears it whenever there is no session.
   Deliberately **not** a time interval: an interval would make the count *sometimes* stale for
   reasons the user cannot see, while event invalidation keeps it correct on exactly the moments
   the user can act on. The Account & devices screen itself always reads the full list on each
   visit (didLoad-guarded per push) – this cache governs only the Settings card's suffix.

2. **"Sync now" - a manual trigger, never a requirement.** Sync is automatic; this exists because
   a user who has just edited something on another device wants to *pull now* rather than wonder.
   Constraints: it is **idempotent** (inert while a sync is in flight, so a repeated tap is never
   a second push); offline it is **not an error** - the row simply settles back to "Will sync when
   you're back online"; on a server failure it names its next step (hard rule 7) and the automatic
   retry continues regardless. **It may never be the only path to a synced state** (hard rule 1);
   removing the button must change nothing about whether data eventually arrives.

3. **Issues - but only the two kinds that belong here.** The distinction is load-bearing:

   | Class | Example | Where it belongs |
   |---|---|---|
   | **Transport** - the connection itself, and the user can act | 410 device revoked, auth expired, blob quota 429, server down | **Settings**, as a card with its next step. This is about the account, not about any record |
   | **Domain** - a merge flagged specific records (S1-S5) | out-of-order odometer, duplicate pair, entry changed by sync | **Where the data lives**, as a badge (hard rule 8). Settings shows a **count and a link** - "2 entries need a look" tapping through to the Log filtered to flagged entries - and **never resolves anything itself** |

   The count is **derived, never stored**: it is the number of records carrying a `ConflictState`,
   recomputed like every other statistic. A stored counter drifts out of agreement with the badges
   and then the two surfaces disagree about the same data.

   Putting a resolution UI in Settings would be the exact failure hard rule 8 exists to prevent -
   conflicts torn out of the context that makes them decidable, so the user is asked to adjudicate
   an odometer discrepancy without the entry in front of them.
- **On recovery:** the queues drain (pull → merge → push per device); *only then* do S1–S5 outcomes materialize. This is why domain conflicts must never be modal: they can arrive in a batch, hours after the user did anything – a stack of interrupting dialogs about yesterday would be hostile. Badges absorb a batch gracefully; a single unobtrusive summary toast covers the rest: "Synced. 2 entries need a look" → tapping filters the Log to flagged entries.
- **Extended outage:** nothing degrades further – a week offline is the same as an hour, just a longer queue. The sin this design refuses to repeat is Мой Авто's "servers disabled; app freezes at login": Tankbook has no sync-gated screen at all.

### The sync state chip (RV.22, normative)

The one-row tab-root header (`docs/DESIGN.md` -> "The tab-root header is ONE row") carries a small
chip beside the Settings gear, so a user can see at a glance whether their data is in the cloud.
It is **presentation over the same state model**: the chip reads `SyncSurfaceState` and resolves its
state through `SyncSurface.chipState(_:)` - it builds no second state machine beside the one the
Settings surface already uses.

The chip is ONE object changing state: one SF Symbols family (`icloud.*`), and every state has a
distinct silhouette, so colour makes it findable but never carries the meaning alone (the
accessibility floor - colour is never the only channel). Precedence, first match wins, in
`SyncChipState`:

| # | Condition | Glyph | Colour | Label EN / RU | Tap |
|---|---|---|---|---|---|
| 1 | `!isSignedIn` | `icloud.slash` | `inkSoft` | "Not signed in" / "Не выполнен вход" | Sign in |
| 2 | `deviceRevoked` / `authExpired` / `quota >= 95` | `exclamationmark.icloud` | `warn` | "Device signed out" / "Устройство отключено" · "Sign in again" / "Войдите снова" · "Storage full" / "Хранилище заполнено" | Settings, scrolled to the card naming the fix |
| 3 | `isSyncing` | system `ProgressView(.circular)` | `action` | "Syncing…" / "Синхронизация…" | Settings |
| 4 | `dirtyCount > 0` | `icloud.and.arrow.up` | `inkSoft` | "Waiting to sync · N changes" | Settings |
| 5 | otherwise | `checkmark.icloud` | `ok` | "Synced" / "Синхронизировано" | Settings |

The decisions inside that table, not just preferences:

- **State 1 is deliberately colourless.** Staying local is legitimate (hard rule 1); a hue would
  read as a fault. It is also the only state whose tap destination is not Settings.
- **State 2 is the only amber the chip can ever show** (hard rule 5: amber is attention only).
- **State 4 is never amber**, because a week of queue looks exactly like an hour of queue.
- **`offline` is NOT a state.** Offline with nothing to push is the ordinary synced reassurance
  ("offline is never an error"), and a 5xx is a label variant of state 4 - never a promotion to
  warning. Offline is not promoted to make the chip tidier.
- **`flaggedCount > 0` is not a sixth state.** A `warn` dot rides the chip's corner over whatever
  state is showing and taps to the Log filtered to flagged entries (`docs/ERRORS.md` -> Settings) -
  never Settings. Hard rule 8 keeps conflict badges where the data lives; a global "sync issues"
  screen is what that rule forbids.
- **The `headlight` correction stands (2026-09-03).** An earlier revision coloured states 3 and 4
  `headlight`; that is wrong and settled as `action` / `inkSoft`. `docs/DESIGN.md` P6.7 reserves
  `headlight` for genuinely electric things only (enforced by `PaletteAccentGuardTests`' allowlist).
  No sync-chip entry was added to that allowlist; do not "fix" the chip back to `headlight`.

**The `isSignedIn` gap, resolved.** `SyncSurface.status()` - the Settings-surface verdict - never
consults `isSignedIn`, so a signed-out device computes `.synced` today. That is correct *for
Settings* (the status row only ever renders when signed in), but the chip needs state 1. The chip
therefore resolves sign-in with its own function, `SyncSurface.chipState(_:)`, rather than growing
a `signedOut` case on `SyncStatus`. Two consequences of that choice are deliberate and pinned by
tests:

- `status()` is untouched: its callers (Settings) keep their exhaustive switches and never see a
  `signedOut` verdict they have no card for.
- `chipState` evaluates the attention conditions **before** `!isSignedIn`, because an expired
  session *clears the Keychain* (so `isSignedIn` reads false too) but is still an account issue the
  user must act on - "Sign in again", never the colourless "Not signed in". This is the precedence
  the mutation check below guards.

## Offline & failure behavior (ties to JOURNEYS)

- Every feature works with sync unreachable (F3/F4 unchanged); `dirty` records queue indefinitely.
- A failed cycle retries by itself (PR.7), so the Settings 429 notice's "Retrying in N minutes" is a
  promise the app keeps. The schedule lives in `SyncRetryPolicy` (core), is driven by a fake clock in
  the tests, and is: **jittered exponential backoff** - base 1 s, doubling per consecutive failure,
  capped at 5 min, with equal jitter so the delay lands uniformly in [half, full] (a fleet retrying in
  lockstep after an outage is a self-inflicted second outage, `PRACTICES.md` U7). The server's
  `Retry-After` **wins over the curve, exactly** - retrying earlier would just be refused again. Only
  the transient class retries (offline, 5xx, a 429 wait); the refusal classes are never retried -
  `401` (authExpired, PR.1's refresher owns it), `402`, `410`, `426` and an unknown 4xx name a next
  step that is not "try again". Partial batch acceptance is fine (idempotent by id + baseScn); only
  idempotent calls are retried at all.
- A device deleted server-side (user revokes it) gets `410` on its cursor → re-onboards via full pull.
- Account deletion: tombstone the account (`accounts.deleted_at`), purge `records`/`blobs` after the grace period; devices get `410` → local data stays local (the user keeps their log; it just stops syncing). The grace period defaults to the 30-day undo window (hard rule 8) and is configurable (`Account:DeletionGraceDays`); it must never be shorter than the undo window, so a tombstoned account stays fully recoverable for the whole window before the purge job deletes anything.
- Restore-on-new-device shows the F7 verification stats from the pull stream before finishing (entries count, date range, last odometer).

## Phasing

1. **v1.0 (no account):** local database only. Sync code ships dark.
2. **v1.x (sign-in):** push/pull live; backups become snapshots; multi-device.
3. **v2:** vehicle sharing (household) – a `vehicle_shares(account_id, vehicle_id, member_account_id, role)` table scoping another account into a vehicle's record stream; Android client speaks the same protocol.

## Open questions

1. ~~Push nudges vs poll~~ – decided: **silent APNs nudges ship at v1.x**, throttled server-side, with foreground polling as the permanent fallback (nudges are an optimization, never a dependency). Full notification design: `NOTIFICATIONS.md`.
2. ~~Blob store~~ – **decided (Aug 23, 2026): S3-compatible object storage, provider-agnostic** – all code targets the S3 API (presigned upload/download, see "Attachments: the blob pipeline"); the concrete provider is a deployment-time ops choice, swappable via config. Local dev runs MinIO in a container.
