# RV.6 – the device-count fetch rides on every `refresh()`

Filed from production (four `GET /v1/account/devices` in 14 seconds) and **investigated on
2026-09-04 by a read-only pro agent**. This brief is built on that investigation, not on the
original filing — **two claims in the original row were wrong** and are corrected below. Do not
re-derive the diagnosis; do confirm it compiles against today's code before changing anything.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios` — `ios/` and `docs/` only.
**Do not run `git add` or `git commit`. Do not touch `docs/TASKS.md`.** Touch no `backend/` file.

**Use the `iPhone 17 Pro` simulator** for every xcodebuild/xcrun step — another agent (RV.47) holds
`iPhone 17` right now.

**Never move, rename or delete a file you did not create.** Two other sessions work in this
checkout. There is a git worktree at **`.claude/worktrees/rv48`** that is **not yours**: `swiftlint`
walks into it and reports ~22 errors from inside it. **Those are not your gate** — check that your
own files are clean and carry on. If something else is broken and is not yours, report it and
continue.

## What was established — the state of the bug today

**Half of it is already fixed.** RV.18's `OpportunisticSyncPolicy` (30 s) closed the *automatic*
burst that most likely produced the original log: every `scenePhase == .active` transition used to
run a full cycle → `runSync` → `refresh()` → a devices fetch, and launch alone fired **twice ~0.6 s
apart**. That shape is now impossible.

**What remains is not a poll at all.** Two call sites reach `GET /account/devices`, both via
`AccountClient.devices()`:

1. **`AppSync.refresh()`** (`ios/App/Sources/Settings/AppSync.swift:312-315`) re-fetches the count
   **unconditionally on every call** — it sets `fetchedDeviceCount = nil` and fetches again. It is
   **never reused to skip a fetch**. `refresh()` is called from six places, and the one that matters
   is **`SettingsView`'s `.task` (`:66`), which runs on every appearance and is ungated** — RV.18's
   interval covers `runOpportunisticSync` only.
2. **`AccountDevicesModel.load()`** — already correct: `didLoad`-guarded, one fetch per push.

So one "check my devices" round trip costs **three** network fetches: Settings appears (#1) → push
AccountDevices (#2) → pop back, `.task` re-runs (#3). **Gear → account → back → account is four
GETs in well under 14 s with no sync cycle involved.** There is no in-flight guard, no interval, and
no reuse anywhere on this path.

## Two corrections to the original row — do not repeat them

- **There is NO rate limit on `GET /account/devices`.** The row claimed *"the per-IP limits key on
  it"*. `Program.cs:584` maps it with **no** `.RequireRateLimiting` while six neighbouring groups
  have one, and `docs/API.md`'s table lists limits only for `auth/session`, `auth/refresh`,
  `import/parse`, `extract`, `sync/push`, `blobs/begin` and `feedback`. **The cost is battery**, plus
  the risk if a limit is ever attached to an endpoint already being hammered. Do not justify the fix
  with a limit that does not exist.
- **RV.22's sync chip did NOT worsen this.** `SyncStateChip` reads the computed `surfaceState` plus
  stored counts, never calls `refresh()` or `devices()`, and is gated to the active tab root.

**Also noted, and out of scope:** RV.26's refresher can turn one devices GET into two on a 401 (the
screen's client wires it; the count path deliberately does not). Real, but not the repetition shape
— leave it.

## What to build

**Stop fetching the device count on every `refresh()`.** Either:

- keep `fetchedDeviceCount` and re-fetch **only when it is nil**, clearing it explicitly on
  **sign-in, sign-out, and after a revoke or account delete**; or
- drop the count fetch from `refresh()` entirely and let the AccountDevices screen be the sole
  fetcher.

Either collapses the round trip above from three fetches to one. **Pick one, implement it, and say
why in your report.**

**The invalidation is the whole risk.** A cached count that never clears is a worse bug than the one
you are fixing: the user revokes a device, the card still says "2 devices", and they conclude the
revoke failed. **Enumerate every event that must invalidate it** and show each one does.

**Do not gate this behind `OpportunisticSyncPolicy`.** A time interval would make the count
*sometimes* stale for reasons the user cannot see. The count changes on events, not on a clock —
invalidate on the events.

## Read before writing

1. **`CLAUDE.md`** — hard rules 1 (no screen is sync-gated), 7 (every error names its next step), 12
   (counts and codes are loggable, domain values never), 14.
2. `docs/API.md` → `/account/devices` and the rate-limit table; `docs/SYNC.md` → the Settings sync
   surface.
3. `ios/App/Sources/Settings/AppSync.swift` (`refresh`, `fetchedDeviceCount`, and all six callers),
   `ios/App/Sources/Settings/AccountDevicesModel.swift`, `AccountDevicesView.swift`,
   `SettingsView.swift:66`, `ios/Sources/TankbookCore/Account/AccountClient.swift`.

## Tests

**iOS 1243 today; must not fall.** (`CaptureOrientationTests` is `.disabled` on purpose — RV.52.
Leave it disabled.)

- **The headline assertion is a REQUEST COUNT, not a screen state.** Over a recording transport:
  `GET /v1/account/devices` fires **at most once** across `Settings → AccountDevices → pop →
  Settings → AccountDevices`. The seeded `AccountStubTransport` / `SeededLaunchTransport` already
  serve this path, so this is cheap to add.
  **"The screen loaded" passes against the bug** — that is exactly what the original acceptance
  criteria would have done.
- **Invalidation tests, one per event you listed**: after a revoke, after sign-out then sign-in, and
  after account delete, the next read fetches again and shows the new count. **Assert the count
  VALUE changed**, not that a request happened.
- L1 in core if you put the reuse decision there.

**Vacuous-assertion traps, named:**
- Asserting the devices list renders. It always did.
- Asserting `fetchedDeviceCount != nil`. It was non-nil throughout the bug.
- Counting requests on a single push only — the bug is the **second** visit.

**Mutation-check and report it**: restore the unconditional re-fetch and confirm the request-count
test goes red. Restore byte-for-byte, confirm green.

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    cd ios && swift test ; echo "IOSTEST=$?"
    swiftlint lint ; echo "LINT=$?"          # repo ROOT; ignore .claude/worktrees/*
    swift run --package-path ios localization-gate --sources ios/App/Sources \
      --catalogue ios/App/Sources/Localizable.xcstrings ; echo "L10N=$?"
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build ; echo "APPBUILD=$?"

**Echo the exit code from the COMMAND, never through a pipe** (`cmd | tail -2 ; echo $?` reports
`tail`'s status); redirect to a file instead. Match the process NAME (`pgrep -x xcodebuild`);
**never `pgrep -f`/`pkill -f`** — that pattern killed a sibling agent on 2026-08-24, and siblings are
running today.

## Screenshots

Only if a visible surface changed — the device card's count is the one thing a user sees, and it
should look identical. If nothing changed, say "none applies" rather than fabricating one. You have
no image input; say so.

## Report back

- Exit codes (captured, not piped), test counts before/after, the mutation result.
- **Which approach you took** (reuse-with-invalidation, or remove from `refresh()`), and why.
- **The full list of invalidation events**, and the test that covers each.
- **The request count before and after** across the navigation sequence — the number this row exists
  to move.
- Confirmation you did not gate it on a time interval.
- Anything you noticed that is not RV.6 — named separately.
