# Tankbook – Remote Configuration

*How settings reach a device without an App Store release, and why it cannot brick the app. Companion to `API.md` (the endpoint), `SECURITY.md` (signing, allowlist), `NOTIFICATIONS.md` (the nudge channel), `ERRORS.md` (silent failure behaviour), `SYNC.md` (`minSchemaVersion`).*

## The bootstrap paradox – and the rule that resolves it

Remote config may change the API base URL. But config is fetched *from* the API. A wrong URL therefore removes the only channel capable of correcting it, and every installed app is stranded until users manually update from the App Store – which many never do.

**Rule: the app must always be able to reach a working backend using only what is compiled into the binary.**

Three layers, in strict precedence, and the app is fully functional with only the first:

| Layer | Source | Survives |
|---|---|---|
| **1 · Bundled defaults** | Compiled into the app (`Config.default.json` in the bundle) | Everything. Changed only by an App Store release |
| **2 · Cached config** | Last successfully fetched + validated payload, stored locally | Restarts, offline, backend outage |
| **3 · Live config** | `GET /v1/config` on the current base URL | Until the next fetch |

A layer is used only if it validates. An invalid layer falls back to the one beneath it, never to nothing.

## What may be configured remotely

| Setting | Why remote |
|---|---|
| `apiBaseUrl` | Domain or region migration without an App Store release – **most dangerous, most guarded** (below) |
| Capture tier kill switches (`tier2OnDeviceLLM`, `tier3CloudFallback`) | Turn off cloud extraction instantly if the provider has an outage or costs spike. The single most valuable entry here |
| `llmQuota` per tier, rate-limit hints | Tune economics without shipping |
| OCR confidence thresholds | Retune the dimming/fallback boundary as the corpus grows |
| `minSchemaVersion`, reference-pack versions (rates, catalog) | Coordinate rollouts; also echoed by `/sync/pull` |
| Maintenance notice (text + severity + optional link) | Tell users about planned downtime honestly |
| `rolloutSalt` + per-flag rollout percentage | Stage a flag to 10% before everyone |

**Never remote-configurable:** anything security-critical (Keychain accessibility classes, TLS policy, the config signing key itself), UI layout, business rules, or consumption math. If a change alters what a number *means*, it ships through the App Store where it can be reviewed and tested.

## Guardrails on `apiBaseUrl` – the dangerous one

1. **HTTPS only**, and the host must match a **compiled-in allowlist** of domain suffixes. A config naming any other host is rejected outright and the previous value stands.
2. **Health gate before adoption:** a newly received base URL is *candidate* only. The client probes `GET /health` against it; the value is promoted to active only after a success. A candidate that fails is discarded and logged.
3. **Auto-revert on sustained failure:** if the active URL produces N consecutive transport failures (default 5, across at least two app sessions), the client reverts to the **bundled default** and re-probes. This is what makes a bad push survivable without user action.
4. **Signed payload:** the config document is signed (Ed25519) with a key whose public half is bundled; an unsigned or badly-signed document is rejected even over valid TLS. TLS authenticates the *connection*; the signature authenticates the *document*, so a compromised CDN or a misissued certificate still cannot redirect our clients. Because config can move the API, this is proportionate rather than paranoid.
5. **Version monotonicity:** each document carries an increasing `version`; a client never applies a document older than the one it holds (rollback protection).

## Delivery

**Pull is the mechanism; push is only a hint.**

- `GET /v1/config` — **public, no auth** (guests and signed-out users need it too), `ETag`/`If-None-Match`, so an unchanged config costs a `304`. Checked on app foreground, throttled to **once per 6 hours** unless a nudge or a failure forces it. Config changes are rare; polling is nearly free and needs no infrastructure.
- **Push nudge (optional accelerator):** the existing silent APNs channel (`NOTIFICATIONS.md`) gains a `config: true` hint so an urgent change – a kill switch during an incident – propagates in minutes rather than hours. Silent pushes need no user permission, but they are unreliable and only reach registered devices, so **the system must be correct with push disabled entirely**. Never make a nudge the only path.
- **Never at launch-blocking time.** Config fetch is background and asynchronous; the UI never waits on it. A cold start with no cached config uses bundled defaults immediately.

## Failure behaviour (extends `ERRORS.md`)

Config problems are invisible to the user, because there is nothing they can do about them:

| Situation | Behaviour |
|---|---|
| Fetch fails (offline, 5xx, timeout) | Silent. Keep cached config; retry with backoff |
| Payload malformed, unsigned, or version older than cached | Reject the whole document (never partially apply), keep cached, log at WARN |
| One unknown key in an otherwise valid document | Ignore that key, apply the rest – forward compatibility, same principle as payload records |
| Candidate `apiBaseUrl` fails its health probe | Discard candidate, keep current, log |
| Active `apiBaseUrl` fails repeatedly | Auto-revert to bundled default, log at WARN |
| Maintenance notice present | The one user-visible case: a quiet informational banner, dismissible, never blocking |

## Client implementation

### Where it is stored

Cached config is **not a secret**, so it does not belong in the Keychain. It is a JSON file in the app container:

```
Application Support/Tankbook/config.cache.json
  { document: <raw config document, verbatim>, signature, etag, fetchedAt,
    activeBaseURL, consecutiveFailures }
```

- File protection `completeUntilFirstUserAuthentication`, same class as the database.
- Written **atomically** (write temp → rename), so a crash mid-write can never leave a truncated document that fails validation on next launch.
- Deliberately a file and not the GRDB database: it must be readable **before** the database opens, since the sync client needs a base URL to start, and it must survive a failed database migration.
- The **raw document is cached verbatim**, not just the fields this build understands. A future app version then immediately understands previously-unknown keys from the existing cache, with no refetch required.

### How it is resolved – the override rule

Two different rules operate at two different levels, and conflating them is the classic bug:

- **Document level: all or nothing.** A document that is malformed, unsigned, badly signed, or older than the cached `version` is rejected *entirely*. Never partially applied.
- **Key level: sparse override.** Once a document is valid, each key it contains overrides the layer beneath it, per key. A document that sets only `tier3CloudFallback` changes exactly that – it does not blank every other setting.

Precedence, highest first:

| Layer | Present in | Purpose |
|---|---|---|
| 1 · Debug override | DEBUG builds only (launch argument or a hidden settings row) | QA forces a flag without a server round trip. Compiled out of Release |
| 2 · Remote (live, else cached) | Any build | The document above |
| 3 · Bundled default | Any build | `Config.default.json` in the bundle – always complete, always valid |

Unknown keys are ignored for resolution but retained in the cache (above). Missing keys simply fall through to the next layer.

### How code consumes it

Typed, injected, and **snapshot-based** – never a stringly-typed global lookup:

```swift
public struct AppConfig: Sendable, Equatable {
    public let apiBaseURL: URL
    public let tier2OnDeviceLLM: Bool
    public let tier3CloudFallback: Bool
    public let ocrConfidenceThreshold: Double
    public let minSchemaVersion: Int
    public let maintenance: MaintenanceNotice?
    public let version: Int              // the applied document's version, for logging
}

@Observable public final class ConfigStore {
    public private(set) var current: AppConfig   // resolved snapshot, drives SwiftUI
    public func snapshot() -> AppConfig          // take once at the start of an operation
    public func isEnabled(_ flag: Flag) -> Bool  // applies rollout % via rolloutSalt + device hash
    public func refresh() async                  // foreground / nudge / failure-triggered
}
```

Three rules that make this safe:

1. **Take a snapshot at the start of an operation and use it throughout.** A capture flow must not observe `tier3CloudFallback` flipping halfway through; a sync cycle must not change base URL mid-batch. Live-reading per call site is how you get races that reproduce once a month.
2. **Typed fields, not string keys.** `config.tier3CloudFallback`, never `config.bool("tier3_cloud_fallback")` – so a renamed key is a compile error, and a coverage test can assert every documented remote key maps to a field.
3. **Injected, not a singleton.** `ConfigStore` is passed in, so tests construct one over fabricated layers with no file, no network, and no `#if DEBUG` gymnastics – per the standing rule in `TESTING.md`.

`minSchemaVersion` also arrives on `/sync/pull` (`schemaPolicy`); that per-response value is authoritative for that exchange, while the config value is the general default used before the first pull.

## Threat: the cache file is tampered with

The cached document is the most valuable tampering target in the app, because it can move `apiBaseUrl` – **and the auth token follows the base URL**. A successful swap yields token theft, full data exfiltration, and a channel to poison local state. It is worth being precise about who can actually write that file.

| Vector | Reachable? | Answer |
|---|---|---|
| Another app on the device | **No** | The iOS sandbox is the boundary. We add no App Group, no `UIFileSharingEnabled`, no shared container for this file |
| **Backup tamper**: edit an unencrypted Finder/iTunes backup, restore it | **Yes, realistically** – the app container is in backups while the app binary is not | The real non-jailbreak vector. Closed by the two rules below |
| Jailbroken / compromised device | Yes, trivially | Out of threat model (`SECURITY.md`). Root can patch out any check we write; anti-jailbreak theatre would not change that |
| MDM / developer tooling with physical access | Yes | Same category as the above |

### The two rules that close the realistic vector

1. **Verify the signature on every load from cache – not only on fetch.** This is the whole game. If we validate at fetch time and then trust the cache, tampering bypasses signing entirely and all our guardrails with it. Verifying on read makes editing the cache equivalent to forging an Ed25519 signature, and the public key lives in the app binary, which a backup restore cannot modify (backups carry the container, not the executable). Verification costs microseconds; do it at every read, including the read on cold start.
2. **Exclude the cache from backups** (`URLResourceValues.isExcludedFromBackup = true`). It is a cache – it refetches. This removes the backup vector outright rather than merely defeating it, which is the better kind of fix.

### Defence in depth – assume the config lied anyway

Signature verification is the wall; these are the checks behind it, each independently sufficient to prevent the worst outcome:

- **The host allowlist is enforced in the HTTP client at request time, not only when config is applied.** Two independent checkpoints, so a bypass of config validation still cannot reach an attacker's host.
- **`Authorization` is attached only for allowlisted hosts.** Even a successful redirect harvests no token: the request simply goes out unauthenticated. This is the single most important consequence of the whole analysis – tokens must be bound to hosts, never to "whatever base URL is current".
- **Rollback floor in the Keychain.** Version monotonicity alone fails if the attacker *deletes* the cache, since a fresh client accepts any version. Store the highest-seen config version as a Keychain item (`…ThisDeviceOnly`, therefore absent from backups and unaffected by container tampering) and refuse any document below it. A fresh install has no floor, which is correct.
- **Documents expire.** Each carries `issuedAt` and a validity window (default 90 days). An expired cached document is discarded in favour of bundled defaults, so an attacker cannot pin a device to a stale-but-validly-signed config forever.
- **The maintenance notice is inert.** Plain text only – no HTML, no markup, no arbitrary URLs, and it may never prompt for credentials or re-authentication. A signed-but-attacker-authored notice would otherwise be an in-app phishing surface, and "tap here to sign in again" is exactly the kind of message users obey.
- **Config can never disable a security control** (TLS policy, Keychain classes, signature verification, the allowlist itself). Those live in the binary by design.

### Tests for this specifically

- Tamper the cached document's bytes → assert it is rejected on read and the app falls back to bundled defaults.
- Tamper the signature → same.
- Present a validly-signed document with a version below the Keychain floor → rejected.
- Delete the cache, present an old validly-signed document → rejected by the floor.
- Present an expired document → rejected, bundled defaults used.
- Point `apiBaseUrl` at a non-allowlisted host and force it past config validation → assert the HTTP client refuses the request, and assert **no `Authorization` header was ever constructed** for that host.

## Logging (per `LOGGING.md`)

Config is our data, not the user's, so it is Safe class: log `config.fetch` (status, etag, durationMs), `config.apply` (version, changed keys **by name**, source: live/cache/bundled), `config.reject` (reason), `config.baseurl.promote` / `.revert` (with the failure count). Log the version and the changed key names, not the whole document – a full dump every 6 hours is noise, not observability.

## Tests

- **Bootstrap test:** with no cached config and no network, the app starts, resolves the bundled base URL, and is fully usable.
- **Brick-proof test** (the important one): feed a config naming an unreachable `apiBaseUrl`, simulate N failures, assert the client auto-reverts to the bundled default and recovers.
- **Allowlist test:** a config naming a non-allowlisted host is rejected and the previous value stands.
- **Signature test:** a valid document with a broken signature is rejected even over a trusted connection.
- **Rollback test:** a document with a lower `version` than cached is ignored.
- **Partial-unknown test:** an unknown key does not prevent the rest of the document applying.
- **Kill-switch test:** flipping `tier3CloudFallback` off makes the capture pipeline stop attempting cloud extraction, with no user-visible error (it degrades exactly as F4).
