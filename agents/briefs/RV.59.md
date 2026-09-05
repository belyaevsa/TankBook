# RV.59 – one logical action fires the same request twice

Filed from two production logs (2026-09-04). **Low severity, pure waste – but it is the third and
fourth instance of the duplicate-request family after RV.6 and RV.18, and the launch cause is now
known exactly.** Confirm it still holds; do not re-derive it.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios` – **`ios/` and `docs/` only.**
**Do not run `git add` or `git commit`. Do not touch `docs/TASKS.md`.** Touch no `backend/` file.
**Never move, rename or delete a file you did not create.**

**Use the `iPhone 17` simulator.**

## The four shapes, and what is proven about each

**(1) CONFIRMED CAUSE – config is refreshed twice at launch.** `configService.refresh()` is called
from **two places that both fire at launch**:

- `ios/App/Sources/Navigation/TabRoots.swift:295` – inside the launch `.task`
- `ios/App/Sources/Navigation/TabRoots.swift:330` – inside `.onChange(of: scenePhase)` when
  `phase == .active`

Launch transitions to `.active`, so both run. The log shows it exactly: two `GET /v1/config/` with
near-identical durations, **937.1787 ms and 937.7665 ms**, both `499`.

**This is the RV.18 shape that was never applied to config.** RV.18 gated the SYNC cycle behind
`OpportunisticSyncPolicy` after finding launch fired it twice ~0.6 s apart. Config and rates were
left ungated.

**(2) SAME SIGNATURE, CAUSE NOT TRACED – `rates/pack` doubles too.** `GET /v1/rates/pack` appears
twice with matched durations, twice over: 1435.3853/1435.2512 ms, then 1090.1152/1099.9465 ms, all
`499`. **Trace its caller and say whether it shares (1)'s cause** – `RemoteRateFetcher` is built in
`ios/App/Sources/ConfirmManual/ManualFillUpCurrencySupport.swift:127`, which is not obviously a
launch path, so do not assume.

**(3) One traceId issues two identical pulls 11 s apart.** Trace
`01a06ce7-96ee-7d7d-bc97-afbe6577f201` logged `GET /v1/sync/pull -> 401`, then `sync.pull
SinceScn=118 Returned=3 NextSince=121` at 14:51:55 (543 ms) and **again** `SinceScn=118 Returned=3`
at 14:52:06 (627 ms) – the same cursor, the same three rows, twice, inside one trace, after the 401
refresh. The cursor only advances on the NEXT cycle, so the second call did no work.

**(4) Cold start fires calls that cannot succeed.** `GET /v1/sync/pull` and `GET /v1/outbox/` both
401 at 14:51:52, then `GET /v1/outbox/` 401 **again** at 14:51:53 – two outbox calls one second
apart, all three before `auth.refresh` rotates. The client knows the token's expiry; it should
refresh first rather than spend three round trips learning it.

The `499`s in (1) and (2) mean the client abandoned both copies, so the work was wasted on both
sides of the wire.

## What to build

**Fix (1) at its cause: one launch must produce one config refresh.** Launch already runs the
`.task`; the `.active` transition that immediately follows must not run a second one. Whatever
mechanism you choose, **it must still refresh on a REAL foreground** (background -> active later),
because that is what `docs/CONFIG.md` requires - collapsing them into "launch only" would be a
different bug.

**Then (2)**: if it shares the cause, it is the same fix; if not, name what it is.

**Then (3) and (4): one 401 should produce one refresh and ONE replay**, not a replay plus the
cycle's own call, and a known-expired token should be refreshed BEFORE the first call rather than
after three rejections. Check whether the outbox poll and the sync cycle each independently trigger
refresh-and-retry, which would explain both at once.

**Do NOT fix any of this with a time throttle.** Same reasoning as RV.6: these are control-flow
bugs, not frequency problems, and a throttle would hide them while leaving the second call to fire
whenever the window happened to be open. **`OpportunisticSyncPolicy` is the precedent for the SYNC
cycle only** - do not extend an interval over config.

**Related, do not duplicate it:** [RV.65] covers `/extract` sending its body twice after a 401.
That is a different defect - one request deliberately replayed with a large body - and it is being
fixed separately. If you touch `TankbookHTTPClient.send`, say so, because RV.65 edits the same method.

## Read before writing

1. **`CLAUDE.md`** – hard rules 1 (local-first; nothing may require the network), 12, 14.
2. `docs/CONFIG.md` – delivery, the poll interval and what a foreground must re-evaluate;
   `docs/SYNC.md` – the cycle and `OpportunisticSyncPolicy`; `docs/API.md` – the endpoints.
3. `ios/App/Sources/Navigation/TabRoots.swift` (the `.task` and the `scenePhase` handler),
   `AppConfigService`, `ios/App/Sources/Settings/AppSync.swift`,
   `ios/Sources/TankbookCore/Rates/RemoteRateFetcher.swift`,
   `ios/Sources/TankbookCore/Config/TankbookHTTPClient.swift` (the 401 seam).

## Tests

**iOS unit 1378 today; must not fall.**

- **Every assertion here is a REQUEST COUNT over a recording transport.** "The sync succeeded" and
  "config loaded" both pass against these bugs today.
- L1: a cold launch issues **exactly one** `GET /v1/config/`. And **exactly one** on a genuine
  background -> foreground afterwards, so the fix does not silently disable the foreground refresh.
- L1: a cold start with an expired token issues **one** `auth/refresh` and **one** `sync/pull`.
- L1: a 401 mid-cycle produces one replay of the failed call and no second cycle.
- L1: the outbox poll is issued once per cycle, not twice.

**Vacuous-assertion traps, named:**
- Asserting the screen rendered, or that config is non-nil. Both were true throughout.
- Asserting "at most one" without a test that the LEGITIMATE second refresh (real foreground) still
  happens - that is how this gets "fixed" into a worse bug.
- Counting requests on launch only, and never on the foreground transition.

**Mutation-check and report it**: restore the second `configService.refresh()` call and confirm the
one-per-launch test goes red. Restore byte-for-byte, confirm green.

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    cd ios && swift test ; echo "IOSTEST=$?"
    swiftlint lint ; echo "LINT=$?"               # repo ROOT
    swift run --package-path ios localization-gate --sources ios/App/Sources \
      --catalogue ios/App/Sources/Localizable.xcstrings ; echo "L10N=$?"   # from repo ROOT
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "APPBUILD=$?"

**Echo the exit code from the COMMAND, never through a pipe**; redirect to a file instead.
**Never `pgrep -f`/`pkill -f`.**

## Screenshots

None applies – no user-visible surface changes. Say so rather than fabricating one.

## Report back

- Exit codes (captured, not piped), unit counts before/after, mutation result.
- **Request counts before and after** for: cold launch config, foreground config, cold-start
  sync/pull, outbox per cycle. These are the numbers this row exists to move.
- **What `rates/pack`'s doubling turned out to be** – same cause, or its own.
- Confirmation you did NOT use a time throttle, and that the real foreground refresh still fires.
- Whether you touched `TankbookHTTPClient.send` (RV.65 edits the same method).
- Anything you noticed that is not RV.59 – named separately.
