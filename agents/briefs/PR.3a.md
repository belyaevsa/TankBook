# Task PR.3a - the config layer goes live: a real fetcher, a real prober, a real key

Repo: **`/Users/sbelyaev/repos/fuel-counter-ios`**, branch `main`. Work in this checkout.

This is the first of three slices completing **P0.12** (`docs/TASKS.md` -> "tick P0.12 when PR.3
lands"). P0.12 delivered **nothing three times** as a single task and went green only once split;
this brief is that lesson applied again. **PR.3b** (transports read `ConfigStore.current`, delete
the nine base-URL fallbacks) and **PR.3c** (the `configPollInterval` remote key) are separate rows
and are **out of scope here** - see "Explicitly out of scope".

## Where you may write

```
ios/Sources/TankbookCore/Config/**
ios/App/Sources/Config/AppConfigService.swift
ios/Tests/TankbookCoreTests/**
backend/tests/Tankbook.Api.Tests/Config/**
docs/CONFIG.md
```

**Do not** touch `ios/App/Sources/Settings/**`, `SignIn/**`, `Import/**`, `ConfirmManual/**`,
`site/`, `deploy/`, `.github/`, `Spike/`, `project.yml`, `design/`, or `backend/src/**`.
**Do not commit. Do not tick `docs/TASKS.md`** - the orchestrator ticks at merge, and a concurrent
session is editing that file right now.

## Write code first, explore second

Every claim below was **verified in the source by the orchestrator before this brief was written**,
with the greps reproduced so you do not re-derive them. Start editing.

## What NOT to explore

- **Do not re-derive whether the layer is live.** It is not. `AppConfigService.make()` passes
  `fetcher: nil`, no health prober, and `bundledConfigPublicKey = ""`.
- **Do not redesign `ConfigStore`'s validation, canonicalization, allowlist, auto-revert or
  rollback floor.** P0.12a/b/c built and tested all of it. Your job is to *feed* it.
- **Do not touch the nine `?? URL(string: "https://api.tankbook.live")!` fallbacks.** They are
  PR.3b. Touching them here guarantees a merge conflict with that slice.
- **Do not chase `api.tankbook.app`.** The `parity.*` fixtures deliberately keep the old domain -
  the signature is over those exact bytes (`docs/TASKS.md` -> W0). It is not a defect.

## What already exists

```swift
// ios/Sources/TankbookCore/Config/ConfigStore.swift
public struct ConfigFetchResult { let document: Data; let signature: String; let etag: String? }
public protocol ConfigFetcher: Sendable { func fetch() async throws -> ConfigFetchResult }
public protocol HealthProber: Sendable { func probe(baseURL: URL) async -> Bool }
public func recordRequestOutcome(_ outcome: ConfigTransportOutcome) async   // 0 app callers - PR.3b
public func refresh() async                                                 // line 208, NO throttle
```

`TankbookHTTPClient` (`ios/Sources/TankbookCore/Config/TankbookHTTPClient.swift:86`) already does
the request-time allowlist and host-bound `Authorization`. Build on it; do not write a second HTTP
client.

Server side, already shipped and **not yours to change**:

```
GET /v1/config             -> signed document, honours ETag / If-None-Match, 304 when unchanged
GET /v1/config/public-key  -> { keyId, publicKeyBase64 }; 503 when Config:SigningKey is unset
```

## Read before writing

1. `docs/CONFIG.md` - **the authority for this task**. Especially "Delivery" (poll, push as a
   hint), "Defence in depth" (the key is **injected, never fetched**) and the `apiBaseUrl` guardrails.
2. `docs/API.md` -> the `/config` contract.
3. `ios/Sources/TankbookCore/Config/ConfigStore.swift` in full.

## What to build

### 1. `RemoteConfigFetcher` in core, over `TankbookHTTPClient`

`GET {base}/v1/config`, sending `If-None-Match` when an etag is known, and honouring **304**.

**The protocol does not currently carry an etag in either direction** - `fetch()` takes nothing and
must return a `ConfigFetchResult`. A 304 has no document, so it cannot be expressed today. Resolve
it deliberately; the orchestrator's recommendation is to widen the seam:

```swift
public protocol ConfigFetcher: Sendable {
    /// Returns nil when the server answered 304 - the held document stands.
    func fetch(ifNoneMatch etag: String?) async throws -> ConfigFetchResult?
}
```

and have `ConfigStore.refresh()` pass the cached record's etag and treat `nil` as "no change,
not a failure". Three test doubles conform (`StubConfigFetcher` x2, `GatedConfigFetcher`) and must
be updated. If you choose differently, **say why in the report** - but a fetcher that cannot
express 304 makes the ETag support on the server unreachable, which is the point of this slice.

### 2. `RemoteHealthProber` in core

`GET {base}/health`, `true` only on a 2xx. This is what the health gate before `apiBaseUrl`
adoption calls; it is injected today and never built.

### 3. A compiled refresh throttle in `ConfigStore.refresh()`

`docs/CONFIG.md` promises **once per 6 hours**; today every foregrounding fetches, so the doc is
fiction (battery and data, U9). Add a **named compiled constant** and skip the fetch inside the
window, using the cache record's `fetchedAt` and the injected `clock` - never `Date()` inline.

A **user-initiated** refresh must still be able to bypass the throttle; a background/foreground one
must not. **Do not add a `configPollInterval` remote key** - it does not exist in
`Config.default.json`, `ConfigDocument`, the server seeder or the schema, and adding it spans both
tiers and three bundled copies. That is PR.3c.

### 4. Bundle the Ed25519 public key, and make the empty one a release blocker

Today `bundledConfigPublicKey = ""`, so **every signature fails open to bundled defaults** - the
layer would be live and still do nothing. The dev signing seed is in
`backend/src/Tankbook.Api/appsettings.Development.json` (`Config:SigningKey`), and its public half is:

```
cdLMDhOLOTNvUCbnluHI9zchTSbr4iE2s+EFKzkrQlk=
```

Bundle that for **DEBUG** so the path is exercised end to end. **The production key is not
provisioned** (`appsettings.json` has `"SigningKey": ""`) and is an ops action nobody in this repo
can take - so for release builds the value stays empty **and must fail a test**, turning today's
silent fail-open into an explicit release blocker (`docs/PRACTICES.md` §6.1 asks for exactly this
lint). Say plainly in the code comment which half is which.

**Verify the key rather than trusting this brief**: add a backend test in
`backend/tests/Tankbook.Api.Tests/Config/` asserting the dev signer's `PublicKeyBase64` equals the
same constant the app bundles. A hand-copied 44-character string is precisely the kind of thing
that drifts silently.

### 5. Wire all three into `AppConfigService.make()`

Replace `fetcher: nil` with the real fetcher and pass the prober. Keep the existing fail-open
behaviour on every error path: a config fetch failure is **silent** and keeps the current config
(hard rule 1 - no screen is ever sync-gated, and config is never launch-blocking).

### 6. Update `docs/CONFIG.md`

The throttle is now real: state the compiled default and that there is no remote override yet.
Correct anything the slice makes stale - `CONFIG.md:134`'s throttle claim is called out in
`docs/PRACTICES.md` as already disagreeing with the code.

## Explicitly out of scope

The nine base-URL fallbacks and any transport reading `ConfigStore.current` (**PR.3b**) · the
`configPollInterval` remote key (**PR.3c**) · wiring `recordRequestOutcome` from transports
(**PR.3b**) · any new UI, screen or string · the App Store id · `docs/TASKS.md` · committing.

## Tests

```
cd ios && swift build   ; echo "build: $?"
cd ios && swift test    ; echo "test: $?"     # 904 today, verified green. MUST rise.
swiftlint lint          ; echo "lint: $?"     # from the REPO ROOT, must be 0
cd backend && dotnet build && dotnet test ; echo "backend: $?"
cd backend && dotnet format --verify-no-changes ; echo "format: $?"
```

You changed `AppConfigService.swift`, which every launch runs. `swift build` does **not** compile
`ios/App`:

```
xcodegen generate
xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
  -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "app build: $?"
```

**Do NOT run the full UI suite** (standing rule, 2026-08-29). The one suite this slice touches is
**`UpdateRequirementUITests`** - the config-driven update notice is what goes live when the fetcher
works. Run exactly that and **report the observed count**; a selector matching nothing prints
"Executed 0 tests" and reads like success:

```
xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:TankbookUITests/UpdateRequirementUITests test
```

**Never `pgrep -f` for a build or test.** Your brief is part of your command line, so
`pgrep -f "xcodebuild.*test"` matches other agents and has killed one 48 minutes in. Use
`pgrep -x xcodebuild`. Never `pkill -f`.

## Mutations you must run and report

Break it, confirm the named test fails, restore **byte-for-byte**.

1. **Make the fetcher ignore `If-None-Match`** and always return a document. The 304 test must fail.
2. **Remove the throttle guard** so every refresh fetches. The throttle test must fail. Then the
   subtler half: make the throttle swallow a **user-initiated** refresh too - a test must fail, or
   the throttle is enforcing more than the doc promises.
3. **Set the DEBUG public key to `""`.** A test must fail. This is the mutation that matters most:
   before this slice, an empty key was the *shipping state* and nothing failed.
4. **Change one character of the bundled public key.** The backend parity test must fail.

A mutation that does not fail is a finding - report it as one. A mutation that does not **compile**
proves nothing and must be redone. Use a **heredoc** for scripted edits: a previous mutation
"passed" only because zsh glob-expanded a path inside an inline `python3 -c` string and the edit
never applied.

## Do NOT run the screenshot script

This slice changes no pixels.

## Report back

- Every command with its **real exit code** and observed counts (iOS before/after, backend, the app
  build, the `-only-testing:` run and its count).
- All four mutation results.
- **Which seam you chose for 304 and why**, if not the recommended one.
- The exact files you changed.
- Anything in this brief you found to be **wrong** - a wrong brief is the orchestrator's error, and
  saying so is worth more than working around it. Three agents have refused a bad brief and been
  right every time.

En-dashes only, never em-dashes.
