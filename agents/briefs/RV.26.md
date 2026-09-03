# RV.26 – a session that cannot authenticate still arms the cloud gateway

Production, 2026-09-03: `POST /v1/extract -> 401` at 08:29:27, 08:32:20 and 08:33:32, each with
`RequestBytes=53406` - **53 KB uploaded three times for an answer that could never succeed**.
`accountHash` and `deviceId` were null on all three, so no usable token was presented, and - unlike
the sync path, which does `401 -> auth.refresh -> retry` three times in the very same log - **no
refresh was attempted**.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`. **Do not run `git add` or `git commit`.**
**Do not touch `docs/TASKS.md`.** Touch no `backend/` file - the fix is client-side.

**Use the `iPhone 17 Pro Max` simulator for every xcodebuild/xcrun step.** Two other agents are
using `iPhone 17` and `iPhone 17 Pro` concurrently, and `simctl`/`xcodebuild` fight over a device.

## The cause, verified 2026-09-03 - do not re-derive it

`ios/App/Sources/ConfirmManual/GatewayScanSession.swift`, `GatewayScanStarter.makeTransport`:

```swift
guard (try? KeychainSessionStore().load()) != nil else { return nil }
```

It gates on a session **existing**. A session that exists but can no longer authenticate passes
that check, and the gateway arms. `docs/JOURNEYS.md` F4 then makes the outcome silent by design: a
gateway refusal surfaces no error, so the user gets **no cloud reading, ever, and is never told**.

**This is not a retry bug.** `GatewayExtractClient` correctly retries only `transportUnavailable`
and treats 4xx as a refusal - that part is right. The defect is **arming at all**.

## Confirm it reproduces before building

The log line carries `clientVersion 1.0.0+1`, a developer build. **Establish whether a real,
properly-signed-in session can reach this state** before assuming it ships - e.g. a session whose
refresh token was revoked server-side, or one written by an older build. Say what you found. If it
turns out to be reachable only in a developer build, **say so plainly and still fix the gate** -
but do not overstate the production impact in your report.

## What to build - and the choice is yours to make and justify

The gateway must be armed **only when the session can actually authenticate**. Two shapes, both
defensible; pick one, implement it, and say why in your report:

- **Refresh like the sync path does.** The transport attempts `auth.refresh` on 401 and retries
  once, exactly as sync already does (that path is right there in the same log, working). Fixes the
  case where the session is merely stale.
- **Mark the session `authExpired` on a 401** so `AppSync.surfaceState` reports it, the Settings
  card names the next step, and **RV.22's chip shows it** (that chip is being built in parallel - a
  401 that leaves the user uninformed is exactly what it exists to surface).

These are not exclusive and the honest answer may be both: refresh when a refresh can work, mark
`authExpired` when it cannot. What is **not** acceptable is a fix that silently disarms the gateway
and tells the user nothing - hard rule 7 says every error names its next step, and F4's silence is
half of what makes this bug expensive.

**Do not degrade the guest path.** A guest has no session and correctly gets no gateway; on-device
OCR still runs (hard rule 1 - the entry is never blocked). Whatever you change must leave that
untouched, and **capture must never be blocked** by any of this.

## Explicitly out of scope

- The retry policy in `GatewayExtractClient` - it is correct.
- The sync path's own refresh - it works.
- Any `backend/` file. RV.33/RV.34 are being built there concurrently; do not touch them.
- RV.22's chip itself - another agent is building it. You may *feed* it (`surfaceState`), but do
  not build chip UI.

## Read before writing

1. **`CLAUDE.md`** - hard rules 1 (local-first; no screen is sync-gated), 7 (every error names its
   next step), 11 (tokens live in the Keychain), 12 (never log domain values - ids, counts and
   outcome codes only), 14.
2. `docs/JOURNEYS.md` → **F4** (the silent-gateway failure journey), `docs/ERRORS.md` → Settings
   and the Confirm sheet, `docs/SYNC.md` → the sync surface, `docs/API.md` → `/extract` auth.
3. `ios/App/Sources/ConfirmManual/GatewayScanSession.swift` (`GatewayScanStarter`,
   `GatewaySeedTransport`), `ios/App/Sources/Settings/AppSync.swift`,
   `ios/Sources/TankbookCore/` auth/session and token-provider types.

## Tests

- `cd ios && swift build ; swift test` - **1189 today; must not fall.**
- **The L2 the row asks for, and its assertion is the whole point: a stale session produces NO
  `/extract` request at all.** Count the requests the transport made and assert the count is
  **zero**. *"Assert the request count is zero - asserting 'the call failed' passes against the
  bug."* A fake transport that records its invocations is the shape; the seam already exists
  (`GatewayExtractTransport` is a protocol, `GatewaySeedTransport` is the precedent).
- If you implement refresh-on-401: an L2 where the refresh **succeeds** must produce exactly one
  retried request that succeeds, and one where refresh **fails** must produce zero further requests
  and leave the session marked - assert both counts.
- If you touch `surfaceState`: L1 on the state transition, `SyncSurfaceTests` is the model.

**Vacuous-assertion traps, named:**
- Asserting the extraction failed / returned nil. It did that throughout the bug - that is the bug.
- Asserting `makeTransport()` returned nil without exercising the path that would have uploaded.
- A test whose "stale session" is actually *no* session. The guest case already worked; the broken
  case is a session that **exists and cannot authenticate**. Build that fixture explicitly.

**Mutation-check and report it**: restore the `load() != nil` gate, confirm the zero-request test
goes red, restore your fix byte-for-byte and confirm green.

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    swiftlint lint ; echo "LINT=$?"          # from the repo ROOT
    swift run --package-path ios localization-gate --sources ios/App/Sources \
      --catalogue ios/App/Sources/Localizable.xcstrings ; echo "L10N=$?"
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build ; echo "APPBUILD=$?"

**Judge by the exit code you echoed.** Zero lint **errors**.

Match the process NAME (`pgrep -x xcodebuild`). **Never `pgrep -f` or `pkill -f`** on a build/test
pattern - an agent's brief is part of its command line.

## Screenshots

Only if a user-visible surface changed - if you add copy naming the next step (and hard rule 7 says
a silent refusal needs one), then `design/screenshots/RV.26-<surface>.png` and `-ru.png`, dark,
outside any test run, with the capture lines added to `scripts/capture-screenshots.sh`. If nothing
visible changed, say "none applies" rather than fabricating a shot. You have no image input; say so.

## Report back

- Exit codes, test counts before/after, suites RUN, the mutation result.
- **Whether this reproduces on a real signed-in session** or only a developer build - and how you
  established it.
- **Which shape you implemented** (refresh, mark-expired, or both) and why.
- **The request count your L2 asserts**, quoted from the test.
- Confirmation the guest path and on-device OCR are untouched, and that capture is never blocked.
- Files changed, docs extended (F4 and the ERRORS row move with this if the user-facing behaviour
  changed), anything unfinished.
