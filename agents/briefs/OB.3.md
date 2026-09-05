# OB.3 / PR.12 - the device remembers when it last synced, and how it last failed

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`, and within it only:
`ios/Sources/TankbookCore/**`, `ios/Tests/**`, `ios/App/Sources/**`, `ios/App/UITests/**`,
`docs/LOGGING.md`, `docs/SYNC.md`, `docs/ERRORS.md`, `design/screenshots/**`.

**Never move, rename or delete a file you did not create.** A second session works in this
checkout (there is a git worktree under `.claude/worktrees/`); if a file looks wrong or a test is
red and you did not touch it, **report it and carry on** - do not "clean the baseline".
Do NOT tick anything in `docs/TASKS.md` - the orchestrator ticks at merge.
Do NOT commit. Do not run `git add -A`, `git checkout`, `git stash`, or `git clean`.

## The symptom this row exists for

Relaunch the app signed in and open Settings. `AppSyncSurface.lastSyncDate` is `nil` because
nothing persists it, and `L10n.syncedAgo` maps `nil` to **"Synced just now"**
(`ios/App/Sources/Localization/L10n.swift:316-318`). **So after every cold start the app claims it
synced a moment ago, whether or not it ever has.** And a failure the user needs to act on - a 410,
an auth expiry, a refused push - vanishes on relaunch entirely: `SyncCoordinator`'s
`lastOutcome` is in-memory state (`ios/Sources/TankbookCore/Sync/SyncCoordinator.swift:39-52`).

There is a second, smaller symptom, deliberately left by OB.1 for this row:
`docs/LOGGING.md:155` promises `net.response` carries "on failure the `errorCode`", and
`NetResponse` already **accepts** one (`ios/Sources/TankbookCore/Logging/LogEvents.swift:204-222`) -
but `LoggingHTTPTransport` never passes it
(`ios/Sources/TankbookCore/Logging/HTTPTransportLogging.swift:63-70`). The doc promises a field the
device never emits.

## Write code first, explore second

Everything you need is named below with file and line. Do not go re-derive the sync architecture.

## What NOT to explore

- Whether `SyncEngine`'s failure classification is right. It is; OB.3 records what it decided.
- The backend. **Nothing on the server changes in this row.** No endpoint, no migration.
- `SyncServerNotice` / `SyncSurface` copy for the *live* states - already correct and tested.
- Blob upload, retry backoff (PR.7), device counts (RV.6/RV.54). Out of scope.

## What already exists (build on these, do not duplicate)

- `SyncCoordinator` (`ios/Sources/TankbookCore/Sync/SyncCoordinator.swift`) - lock-guarded `State`
  with `lastSyncDate` / `lastOutcome`; **already takes `lastSyncDate:` in `init` (line 67)**, and
  sets `snapshot.lastSyncDate = Date()` on a non-inert cycle (line 159).
- `SyncOutcome` (`ios/Sources/TankbookCore/Sync/SyncEngine.swift:5-43`) - the failure flags
  (`offline`, `serverUnavailable`, `authExpired`, `deviceRevoked`, `upgradeRequired`,
  `refusedByServer`, `retryAfterSeconds`, `deferred`). **It carries no server code and no traceId.**
- `SyncServerError` (`ios/Sources/TankbookCore/Sync/SyncWire.swift:128+`).
- `RemoteSyncTransport.send` (`ios/Sources/TankbookCore/Sync/RemoteSyncTransport.swift:49-72`) -
  catches `TankbookHTTPClientError.httpError(status, code, traceId, retryAfterSeconds)` and
  **discards the `traceId` (the `_`) and keeps the code only long enough to classify**.
- `TankbookHTTPClientError.httpError` (`ios/Sources/TankbookCore/Config/TankbookHTTPClient.swift:125`)
  and the private `problemBodyMembers(fromBody:)` (`:334-341`) which reads `traceId` + `code`
  from a problem+json body in one `JSONSerialization` pass.
- `UserDefaultsSyncCursorStore` (`ios/Sources/TankbookCore/Sync/SyncTransport.swift:28-46`) - the
  precedent for a small non-sensitive device-scoped store, and the shape to copy.
- `SyncService.makeCoordinator` (`ios/App/Sources/Settings/AppSync.swift:11`) and
  `AppSyncSurface.refresh()` (`:317-355`), which reads `core.lastSyncDate()` / `core.lastOutcome()`.
- `SettingsView.statusLine` (`ios/App/Sources/Settings/SettingsView.swift:230-250`) and
  `accountStatusLines` (`:207-228`).
- `SettingsTestSeed` (`ios/App/Sources/Settings/SettingsTestSeed.swift`) - the `-seedSettings*`
  launch-argument map; add to the map, do not invent a second mechanism.

## Read before writing (in this order)

1. `docs/SYNC.md` -> "The Settings sync surface (normative)" (from line 449). **Authority for what
   that surface may say.** Note the rule it states: the status line is **reassurance, never a
   warning** - it does not turn amber with age.
2. `docs/LOGGING.md` §4 (line 155 for `net.response`, line 144 for what an error line carries).
3. `docs/ERRORS.md` -> Settings (the existing next-step copy for each failure class).
4. `CLAUDE.md` hard rules **7** (every error names its next step), **12** (never log domain
   values), **13**, **14** (build + lint before anything counts).

## What to build

### 1. A persisted sync state (core)

New file `ios/Sources/TankbookCore/Sync/SyncStateStore.swift`:

```swift
public enum SyncFailureKind: String, Codable, Sendable, Equatable { ... }
public struct SyncFailureRecord: Codable, Sendable, Equatable {
    public let at: Date
    public let kind: SyncFailureKind
    public let code: String?      // the server's problem+json code (OB.1), raw
    public let traceId: String?
}
public struct PersistedSyncState: Codable, Sendable, Equatable {
    public var lastSuccessAt: Date?
    public var lastFailure: SyncFailureRecord?
}
public protocol SyncStateStore: Sendable { func load() -> PersistedSyncState; func save(_ s: PersistedSyncState) }
```

- `SyncFailureKind` cases exactly cover the classes `SyncOutcome` can end in and nothing else:
  `offline`, `serverUnavailable`, `authExpired`, `deviceRevoked`, `upgradeRequired`, `tierRefused`,
  `rateLimited`, `refused`, `invalidResponse`. A **deferred** or **inert** cycle is not a failure
  and must not be recordable - same reasoning as `SyncCycleCounts` (SyncCoordinator.swift:19-23).
- Derive the kind from `SyncOutcome` in **one** place - a single `init?(outcome:)`-shaped
  function, so no second classification can drift from `SyncServerNotice.classify`.
- Ship `UserDefaultsSyncStateStore` (JSON under one key, e.g. `tankbook.sync.state`, with an
  injectable `UserDefaults` so tests never touch `.standard`) and `InMemorySyncStateStore` for
  tests. Copy `UserDefaultsSyncCursorStore`'s doc-comment reasoning about why a preference slot is
  the right home: **this record is infrastructure - a timestamp, a class, a code, a trace id - and
  contains no domain value** (hard rule 12). Nothing else may be added to it.

### 2. Carry the code and the traceId from the wire to the outcome

`RemoteSyncTransport.swift:60` has both and throws both away. Route them to the coordinator
**without changing what is thrown** - every existing `catch SyncServerError.…` in `SyncEngine` must
keep matching, and a wrapper error would silently stop matching without a compile error. So:

- Add a small lock-guarded sink in core (e.g. `SyncFailureDiagnostics`, one `record(code:traceId:)`
  + `take()` that returns and clears), injected into `RemoteSyncTransport` and into
  `SyncCoordinator`.
- `RemoteSyncTransport.send` records `(code, traceId)` on the `httpError` catch **and records nils
  on the transport-failure catch** so a previous cycle's code cannot be attributed to an offline one.
- `SyncCoordinator` **clears the sink at the start of every cycle** and `take()`s it when the cycle
  ends in a failure. Cycles are serialized by the existing `inFlight` gate - say so in the comment.
- If you find a cleaner shape that keeps `catch SyncServerError` intact and makes a stale
  attribution **inexpressible** rather than merely tested against, take it and say why in the
  report. That instinct is what made OB.1 and RV.62 better than their briefs.

### 3. Persist and restore

- `SyncCoordinator` takes an optional `SyncStateStore` (default an in-memory one, so no existing
  call site changes behaviour): on a successful non-inert cycle write `lastSuccessAt` **and clear
  `lastFailure`**; on a failing one write the `SyncFailureRecord` and leave `lastSuccessAt` alone.
- `SyncService.makeCoordinator` (`AppSync.swift:11`) passes `UserDefaultsSyncStateStore()` and
  seeds `init(lastSyncDate:)` from the stored `lastSuccessAt`.
- `AppSyncSurface` exposes the restored `lastFailure` so Settings can render it before any cycle runs.

### 4. Settings shows it

- The status line must stop claiming "Synced just now" when nothing has ever synced. **Ask the
  product-facing question in the report**: `L10n.syncedAgo` maps `nil` to "just now" deliberately
  (its doc comment says so). With a persisted date, `nil` now means *genuinely never synced on this
  device* - give that its own honest string (EN + RU) rather than the reassurance lie.
- Render the restored last failure as a caption line on the account card, in the vocabulary
  `docs/ERRORS.md` -> Settings already uses for that class, **naming its next step** (hard rule 7),
  with an accessibility identifier (`settingsLastFailure`). It is a **statement of the last
  outcome, not an alarm**: follow `docs/SYNC.md`'s reassurance rule and the existing
  `SyncServerNotice.isAttention` convention for colour - do not invent a new severity.
- **The raw `code` and `traceId` are NOT shown to the user.** They are persisted and logged; OB.4
  exports them. A support id on screen is a separate decision nobody has made.
- All new strings through the String Catalog, **EN + RU**, full localised phrases - never
  concatenation (the P1.4 "%@ расходы" bug). The localization gate must stay 0.

### 5. Close OB.1's loose end: `errorCode` on `net.response`

`LoggingHTTPTransport.execute` (HTTPTransportLogging.swift:42-70) must pass `errorCode:` when the
response is a failure. The decorator holds the raw body, so read the problem+json `code` there -
**one shared parse helper with `TankbookHTTPClient.problemBodyMembers`, not a second copy** (promote
it to an internal/public helper). Only for a non-2xx status, and **only the `code` member**: never
`title`, never `detail`, never any other body value (hard rule 12). `willRetry` stays as it is
unless the caller genuinely knows.

## Explicitly out of scope

Diagnostics export / share sheet (that is OB.4/PR.11). Any backend change. Any new endpoint. A
support-id UI. Changing the retry schedule. Touching `docs/TASKS.md`.

## Tests

**Counts today (measured 2026-09-05, from the repo ROOT): iOS `swift test` 1444 tests / 152 suites,
0 failures. It must rise.** Report the number you observed, not the number you expected.

L1 (`ios/Tests/TankbookCoreTests/`):
- Round trip through `UserDefaultsSyncStateStore` over an ephemeral suite name.
- A coordinator over an in-memory store: a successful cycle writes `lastSuccessAt` and **clears** a
  pre-existing `lastFailure`; a failing cycle writes kind + code + traceId and **leaves
  `lastSuccessAt` untouched**.
- A **deferred** cycle (Low Power + `.background`) and an **inert** cycle (a second `syncNow` while
  one is in flight) write **nothing**.
- Attribution: a cycle that fails offline **after** a previous cycle failed with a server code
  records `code == nil` - the stale code must not ride along.
- A coordinator built from a stored state reports the stored date **and** the stored failure.
- A privacy sweep in the style of OB.2's `everyEventThisRowAddsIsFreeOfDomainValues`: encode a
  `PersistedSyncState` written from a cycle over a repository holding a station name, a note and an
  amount, and assert none of those strings appears in the encoded JSON.
- `LoggingHTTPTransport`: a 4xx whose body carries `{"code":"token_invalid","traceId":"…"}` emits
  `net.response` with `errorCode=token_invalid`; a 200 emits **no** `errorCode`; a 4xx with a body
  that has no `code` member emits none; and the rendered line carries neither `title` nor `detail`.

L4 (`ios/App/UITests/SettingsUITests.swift`, plus a new `-seedSettings*` argument):
- A seeded relaunch (stored success date, no cycle run) shows the **age** string, not "just now".
- A seeded stored failure shows `settingsLastFailure` with its next step.
Name the suites you run: `SettingsUITests` and `SettingsServerAheadUITests` via
`-only-testing:`, plus the full `swift test`. **Do not run the whole UI suite** (2026-08-29 rule).
Check the observed count is non-zero - a filter that matches nothing prints "0 tests ... passed".

### Vacuous-assertion traps, named

- **`init(lastSyncDate:)` already exists and already reports what it was given.** A test that only
  asserts that passes against today's bug and is worth nothing. The claim is *the app restores it
  from storage after a relaunch*.
- Asserting the store was written without asserting **what** (kind, code, traceId) it holds.
- Asserting `net.response` has an `errorCode` field on a body you also stubbed the parser for.
- Asserting a failure line "renders" without asserting it survives a relaunch with no cycle.
- `#expect(true)`, or a "no throw" assertion.

### Mutation checks (run them, report what failed and restore byte-for-byte)

1. Make `UserDefaultsSyncStateStore.save` a no-op -> the restore test must fail.
2. Drop `errorCode:` from the `NetResponse` call in `LoggingHTTPTransport` -> its test must fail.
3. Remove the sink clear at cycle start -> the stale-code attribution test must fail.
4. Record the failure on a **deferred** cycle -> the deferred test must fail.

If a mutation **passes**, that is a finding: the test is vacuous. Say so rather than moving on.

## The baseline gate (CLAUDE.md rule 14)

From the **repo ROOT**, judged by exit code (`echo $?`), not by skimming output:
- `cd ios && swift build` -> 0
- `cd ios && swift test` -> 0, count reported
- `swiftlint lint` **from the repo root** -> 0 errors (root-relative `excluded:` paths; running it
  from `ios/` produces thousands of phantom violations)
- the localization gate **from the repo root** -> 0
- `xcodebuild -project Tankbook.xcodeproj -scheme Tankbook -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TankbookUITests/SettingsUITests -only-testing:TankbookUITests/SettingsServerAheadUITests test` -> 0
  (`swift build` does **not** compile `ios/App`; only `xcodebuild` does. Run `xcodegen generate`
  first if you added a file.)
- **Never `pgrep -f` for a build** - your own brief is in your command line and you will match
  (and kill) a sibling agent. Use `pgrep -x xcodebuild`.

## Screenshots

Two states, EN **and** RU, **dark** theme, in `design/screenshots/`, named
`OB.3-settings-restored.png` / `-ru.png` and `OB.3-settings-last-failure.png` / `-ru.png`.

- Capture **outside** a test run - `simctl` and `xcodebuild test` fight over the device.
- RU: `xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU`.
- **Verify every EN/RU pair actually differs: `md5 -q a.png b.png`.** RV.58 shipped an "RU"
  screenshot byte-identical to its EN one because the launch argument did not take, and the agent
  could not tell. Report the md5s.
- A `-` prefixed launch argument can **persist across relaunches**; reinstall between shots if a
  seeded state sticks (RV.64).
- You cannot see your own screenshots. The orchestrator opens all four. Do not claim they look right.

## Docs to reconcile in this same change

- `docs/SYNC.md` -> "The Settings sync surface": the state now survives a relaunch; say what is
  stored and that it holds no domain value.
- `docs/LOGGING.md` §4: `net.response`'s `errorCode` is now actually emitted, and where it comes from.
- `docs/ERRORS.md` -> Settings: the last-failure line and its next step, if the copy is new.

## Report back

1. The **exit code** of every gate above, and the **observed** test counts (before -> after).
2. Each mutation: what you broke, which named test failed, and confirmation you restored it.
3. The four screenshot paths and their md5s (EN vs RU must differ).
4. **What the user now sees that they did not before**, per state. If the answer for a state is
   "the same message", say so plainly - OB.1's report did, and it was worth more than a claim.
5. Anything in this brief that was wrong. A fence can be wrong the same way a diagnosis can
   (RV.70): if following it would ship a defect, report it as a Residual rather than obeying quietly.
6. Whether the tests were actually **run**, not only written.
