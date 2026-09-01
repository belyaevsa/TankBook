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
| `appUpdate` (`minSupportedVersion`, `latestVersion`) | Tell a build it is out of date, and withdraw the server-backed features from one the server no longer supports, without an App Store release. Its own section below |
| `rolloutSalt` + per-flag rollout percentage | Stage a flag to 10% before everyone |

**Never remote-configurable:** anything security-critical (Keychain accessibility classes, TLS policy, the config signing key itself), UI layout, business rules, or consumption math. If a change alters what a number *means*, it ships through the App Store where it can be reviewed and tested.

## Guardrails on `apiBaseUrl` – the dangerous one

1. **HTTPS only**, and the host must match a **compiled-in allowlist** of domain suffixes. A config naming any other host is rejected outright and the previous value stands.
   - **CLOSED 2026-08-28: the domain is registered.** `tankbook.live` was purchased, and
     `HostAllowlist.allowedDomain` and `Config.default.json`'s `apiBaseUrl` now name it
     (`https://api.tankbook.live`). This was a real hole while it was open, not a formality: both
     files previously carried `tankbook.app` as a placeholder for a domain **nobody owned**, and an
     allowlist naming an unowned domain is worse than no allowlist, because anyone could register it
     and inherit every guardrail's trust. Mutation-checked - reverting `allowedDomain` to the old
     value fails 8 of the 15 allowlist assertions. **DNS does not resolve yet**, which is fine: the
     allowlist is a string-matching guard and does not require resolution, and a base URL that fails
     to answer falls back through the layers above exactly as designed.
2. **Health gate before adoption:** a newly received base URL is *candidate* only. The client probes `GET /health` against it; the value is promoted to active only after a success. A candidate that fails is discarded and logged.
3. **Auto-revert on sustained failure:** if the active URL produces N consecutive transport failures (default 5, across at least two app sessions), the client reverts to the **bundled default** and re-probes. This is what makes a bad push survivable without user action.
4. **Signed payload:** the config document is signed (Ed25519) with a key whose public half is bundled; an unsigned or badly-signed document is rejected even over valid TLS. TLS authenticates the *connection*; the signature authenticates the *document*, so a compromised CDN or a misissued certificate still cannot redirect our clients. Because config can move the API, this is proportionate rather than paranoid.
5. **Version monotonicity:** each document carries an increasing `version`; a client never applies a document older than the one it holds (rollback protection).

## App version and the update notice

The second user-visible config surface, and the answer to "this build is too old". It is delivered as
a key in the signed document rather than as its own endpoint, so it inherits the signature, the
version monotonicity, the `ETag`/`304`, the offline cache and the bundled fallback without a single
one of them being specified twice.

```json
"appUpdate": { "minSupportedVersion": "1.2.0", "latestVersion": "1.4.0" }
```

**The server states facts; the client derives the requirement.** Two thresholds and one derived
value - deliberately *not* a `severity` string, because a document could then declare `"required"`
while naming a `minSupportedVersion` the running build already satisfies, and there is no correct
way to resolve that contradiction. With thresholds the hard/soft sign is computed, and cannot
disagree with itself:

| The running build | Requirement | What the user sees | What is withheld |
|---|---|---|---|
| `>= latestVersion` | `.none` | nothing | nothing |
| `>= minSupportedVersion`, `< latestVersion` | `.recommended` (**soft**) | a dismissible row in Settings -> About | nothing |
| `< minSupportedVersion` | `.required` (**hard**) | a non-dismissible notice on the server-backed surfaces, naming its next step | sync, cloud extract, import parse |

**A hard requirement never blocks the app** (hard rule 1). Below `minSupportedVersion` the user can
still log, edit, view, compute and export every entry, offline and indefinitely; what stops is the
set of things that talk to a server which has stopped supporting this build - the same set that
`426 upgrade_required` already withholds on `/sync/push` (`API.md`), which is why the surface is
shared with P6.11 rather than invented twice. A build that cannot sync is degraded; a build that
cannot record a fill-up at a filling station is broken, and no version policy is worth that.

**The notice is inert, like the maintenance notice, and for a sharper reason.** The server supplies
**no text and no URL** - only the two version strings. The copy comes from the String Catalog (hard
rule 10, so it is localised, and hard rule 7, so it names its next step) and the destination is the
App Store page built from a compiled-in app id. *"Your app is out of date, tap here to update"* is
close to the most obeyed sentence anyone could put on a screen, so it is not a sentence the server
is given the ability to write.

**An unparseable version fails open.** A `minSupportedVersion`, a `latestVersion` or a running
`CFBundleShortVersionString` that does not parse as dotted numerics yields `.none`, logged at WARN.
Comparison is numeric per component, never lexicographic - `1.10.0` is newer than `1.9.0`, and a
string compare says the opposite. Failing *closed* here would let one malformed string withdraw sync
from every install at once, which is the config equivalent of bricking, and the bootstrap rule says
that outcome is never acceptable.

`appUpdate` is **optional**, and `Config.default.json` never carries one: absent means `.none`, so a
device that has never reached the network is never told it is out of date.

### The surface (P6.18b)

The app derives the requirement once, at launch and on foreground, from the **held snapshot**
(`ConfigStore.current` - live, else cache, else bundled) - never from a fetch in flight, and no
screen ever waits on a response to decide what to draw. The three shapes:

- `.recommended`: a **dismissible** row in Settings -> About ("A newer version of Tankbook is
  available."). Quiet information; nothing is withheld.
- `.required`: a **non-dismissible** notice on the server-backed surfaces only - sync (Settings),
  cloud extract (the Confirm sheet when a scan carries a photo), import parse (the source screen).
  The server call is withheld client-side (the same set `426` already withholds, shared with P6.11);
  logging, editing, recompute and export are untouched, offline and indefinitely (hard rule 1).
- Both carry the "Update in the App Store" button **only when a compiled-in app id exists** - none
  today, so the notice is text-only: no dead affordance, mirroring the site's `apple-itunes-app`
  gate. The copy is local (String Catalog, EN + RU) and constant; the server still sends no text.

**Two things that did not survive implementation as this section assumes:**

- **The shipped bundle version must be three dotted numerics.** `CFBundleShortVersionString` is
  `"1.0"` today (Info.plist), and `AppVersion` deliberately parses exactly three components - so
  every real install currently resolves `.none` no matter what the document says. The surface is
  correct (and fail-open, per the rule above); the version just has to become `1.0.0` before the
  notice can ever fire. UI tests pin the three-component running version via a DEBUG launch
  argument (`-configRunningVersion`), never by weakening the parser.
- **The live layer is now wired (PR.3a), with one release caveat.** `AppConfigService` constructs
  the store with a real `RemoteConfigFetcher` (`GET /v1/config` over `TankbookHTTPClient`, honouring
  `ETag`/`If-None-Match`/`304`) and a real `RemoteHealthProber` (`GET /health`), and the throttled
  foreground refresh actually fetches. In DEBUG the bundled signing key is the dev key's public half,
  so the path is exercised end to end; in RELEASE the key is still empty until ops provisions it,
  which is an explicit release blocker (`ConfigSigningKeyTests`) rather than a silent fail-open.
- **The transports now obey the layer (PR.3b).** Every transport reads the base URL **per operation**
  through a `ConfigTransportDirector` – never a URL captured once at construction – and reports every
  request outcome to `recordRequestOutcome` (`.transportFailure` when the host was unreachable,
  `.response(status:)` whenever it answered, any status). The ten inline `?? URL(string:
  "https://api.tankbook.live")!` fallbacks and `AppConfigService.fallbackBundled()` are gone; the
  bundled default lives only in `Config.default.json`, and the app's transport factories resolve the
  base URL from the one process-wide `ConfigStore` (`AppConfigStore`). A grep gate pins zero
  `api.tankbook.live` literals under `ios/App/Sources`. The `configPollInterval` remote override does
  not exist yet (PR.3c).

## Delivery

**Pull is the mechanism; push is only a hint.**

- `GET /v1/config` – **public, no auth** (guests and signed-out users need it too), `ETag`/`If-None-Match`, so an unchanged config costs a `304`. Checked on app foreground, throttled to **once per 6 hours** – a **compiled** constant (`ConfigStore.automaticRefreshInterval`), read from the cache record's `fetchedAt` against the injected clock, never `Date()`. A **user-initiated** refresh bypasses the throttle; the background/foreground paths do not. **There is no remote override yet** (`configPollInterval` does not exist – PR.3c). **The 6 hours is chosen for hibernation, not for cost** (product owner, 2026-09-01): iOS suspends and eventually terminates a backgrounded app, so the interval that matters is between *foregrounds*, not between wall-clock ticks. A shorter throttle would not buy a fresher config - the app is not running to honour it - it would only add fetches to the launches a user already makes. That is why the constant is compiled rather than tunable: the number is a property of the platform's lifecycle, not a knob worth turning remotely. Config changes are also rare, and polling is nearly free, but those are the lesser reasons.
- **Push nudge (optional accelerator):** the existing silent APNs channel (`NOTIFICATIONS.md`) gains a `config: true` hint so an urgent change – a kill switch during an incident – propagates in minutes rather than hours. Silent pushes need no user permission, but they are unreliable and only reach registered devices, so **the system must be correct with push disabled entirely**. Never make a nudge the only path.
- **Never at launch-blocking time.** Config fetch is background and asynchronous; the UI never waits on it. A cold start with no cached config uses bundled defaults immediately.
- **Launch counts as a foreground event**, so the update requirement is evaluated on every cold start - but it is evaluated **against the resolved snapshot the app already holds** (live, else cache, else bundled), not against the fetch in flight. The notice therefore appears instantly on a launch with a cached document and never at all on a first launch offline, and no screen has ever waited for a response to decide what to draw.

## Failure behaviour (extends `ERRORS.md`)

Config problems are invisible to the user, because there is nothing they can do about them:

| Situation | Behaviour |
|---|---|
| Fetch fails (offline, 5xx, timeout) | Silent. Keep cached config; retry with backoff |
| Payload malformed, unsigned, or version older than cached | Reject the whole document (never partially apply), keep cached, log at WARN |
| One unknown key in an otherwise valid document | Ignore that key, apply the rest – forward compatibility, same principle as payload records |
| Candidate `apiBaseUrl` fails its health probe | Discard candidate, keep current, log |
| Active `apiBaseUrl` fails repeatedly | Auto-revert to bundled default, log at WARN |
| Maintenance notice present | A user-visible case: a quiet informational banner, dismissible, never blocking |
| `appUpdate` absent, or any version string malformed | `.none` - no requirement and no notice; the malformed case logged at WARN. The gate fails open by design |

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
    public let appUpdate: AppUpdateThresholds?      // nil - and any malformed version - means .none
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

1. **Take a snapshot at the start of an operation and use it throughout.** A capture flow must not observe `tier3CloudFallback` flipping halfway through. Live-reading per call site is how you get races that reproduce once a month. The one deliberate exception is the **base URL itself**, which transports read per operation through `ConfigTransportDirector` (PR.3b): a long-lived transport built at launch must observe a later promotion or auto-revert, so `apiBaseURL` is resolved at the moment a request is made rather than captured once at construction. Everything else in the snapshot stays snapshot-based.
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
- **The update notice is inert too, and for the same reason at higher stakes.** The server sends two
  version strings and nothing else - no text, no link. An "update now" prompt is a more obeyed
  phishing surface than a maintenance banner, so the copy is local and the destination is a
  compiled-in App Store id.
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
- **Update-gate tests:** a build below `minSupportedVersion` resolves `.required`, the server-backed
  surfaces refuse while naming their next step, and logging, editing, recompute and export all stay
  reachable offline (hard rule 1); a build between the thresholds resolves `.recommended` and
  withholds nothing; `1.10.0` against `minSupportedVersion` `1.9.0` resolves as newer (the
  lexicographic mutation); a malformed or absent version resolves `.none` rather than locking the
  device out.
- **Kill-switch test:** flipping `tier3CloudFallback` off makes the capture pipeline stop attempting cloud extraction, with no user-visible error (it degrades exactly as F4).
