# RV.58 – the client keeps syncing for three minutes after a 410

**READ THIS FIRST: an earlier version of this row claimed a cross-account data leak. That was WRONG
and has been retracted.** Do not implement it. The corrected scope is small and is below.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios` – **`ios/` and `docs/` only.**
**Do not run `git add` or `git commit`. Do not touch `docs/TASKS.md`.** Touch no `backend/` file.
**Never move, rename or delete a file you did not create.**

## What was wrong, and why it matters that you know

The original filing read a production log and concluded a device had pushed a fill-up into a
different account. Two things dissolved it:

1. The product owner had **deliberately revoked and re-added** the device, so the `410` is exactly
   what `docs/API.md` says it is – a revoked device – not a mystery.
2. **`accountHash` is computed two ways under one field name** (`AccountHash.Compute(email)` at
   `AuthService.cs:121` versus `AccountHash.ForAccount(accountId)` in the request middleware), so the
   two different-looking hashes are almost certainly ONE account. That is filed separately as RV.63.

**So: no account fencing, no queued-work re-homing, no sign-in interlock.** There is no evidence for
any of it. If you find yourself designing that, stop – you are implementing the retracted version.

## The remaining defect, which is real

From the log, one device, verbatim timestamps:

- **14:53:10** `GET /v1/sync/pull -> 410`
- the same device then ran `sync.pull`, `blob.begin`, `blob.commit` and `sync.push` and went on
  pulling until **14:56:04** – about three minutes past the 410.

`410` is the server saying access is gone (`SyncRepository.cs:77`, `SyncEndpoints.cs:82`;
`docs/API.md`: revoked device / deleted account). The client should **end the sync cycle and route to
sign-in**, not carry on.

## What to build

**Handle 410 as terminal for the cycle.** On a 410 from pull: stop the cycle, drop the session, and
surface sign-in.

**Hard rule 8 applies – nothing lost silently.** Local data must not be destroyed by a 410; the
device's unsynced work stays on the device. Say in your report exactly what happens to it.
**Hard rule 7**: whatever the user sees must name its next step and survive being ignored.
**Hard rule 1**: no screen is sync-gated – a revoked device must still be able to use the app
locally.

**A separate question worth ANSWERING IN `docs/API.md` rather than coding around**: should the server
accept a `sync/push` on a revoked device's still-valid access token at all, when it answers 410 on
pull? Write the answer down; do not change backend code (you may not touch `backend/`).

## Read before writing

1. **`CLAUDE.md`** – hard rules 1, 7, 8, 12, 14.
2. `docs/API.md` -> `/sync/pull` status codes; `docs/SYNC.md` -> the sync cycle and offline behaviour;
   `docs/ERRORS.md` -> the revoked-device row (add one if it is missing).
3. `ios/App/Sources/Settings/AppSync.swift`, the sync coordinator and its 401/410 handling,
   `ios/Sources/TankbookCore/Account/`, and how RV.26's refresher treats non-401 failures.

## Tests

**iOS unit 1322 today; must not fall.**

- **The headline L1, over a recording transport: a 410 on pull produces NO further request in that
  cycle.** Assert the request COUNT after the 410 is zero – asserted by the cycle STOPPING, not by a
  flag or a state enum.
- L1: a 410 does not delete local entries (rule 8) – assert the row count is unchanged.
- L4: sign-in is reachable afterwards and the app still opens its screens offline (rule 1).

**Vacuous-assertion traps, named:**
- Asserting sign-in appeared. The bug is the three minutes of TRAFFIC after it.
- Asserting the session was cleared without asserting no further request went out.
- Testing a 401 instead of a 410 – they are different paths and 401 already works.

**Mutation-check and report it**: treat 410 like any other failure (retry) and confirm the
request-count test goes red. Restore byte-for-byte, confirm green.

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    cd ios && swift test ; echo "IOSTEST=$?"
    swiftlint lint ; echo "LINT=$?"               # repo ROOT
    swift run --package-path ios localization-gate --sources ios/App/Sources \
      --catalogue ios/App/Sources/Localizable.xcstrings ; echo "L10N=$?"
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "APPBUILD=$?"

**Echo the exit code from the COMMAND, never through a pipe.** Never `pgrep -f`/`pkill -f`.

## Screenshots

Only if a user-visible surface changed (a revoked-device message would be one). If so: EN and RU,
dark, `design/screenshots/RV.58-*.png`. If nothing visible changed, say "none applies".

## Report back

- Exit codes (captured, not piped), counts before/after, mutation result.
- **The request count after a 410, before and after your change** – the number this row exists to move.
- **What happens to unsynced local data on a 410**, stated explicitly.
- What you wrote in `docs/API.md` about push on a revoked token.
- Confirmation you did NOT build account fencing.
