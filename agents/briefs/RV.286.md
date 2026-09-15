# RV.286 - Signing in during the deletion grace period must REACTIVATE the account, not lock the user out for 30 days

Task row: `docs/TASKS.md` -> `RV.286` (RV section). Scenario: J11a (sign-in IS registration), F10;
`docs/SYNC.md` -> account deletion. **Product owner decided 2026-09-15: option (a), reactivate.**

## Where you may write

Only inside this repository checkout. Never `/tmp` for files that matter (the log dir
`/tmp/agentlogs` is the orchestrator's, not yours). Never commit. Never tick `docs/TASKS.md`.

## Write code first, explore second

You have the cause pinned below. Confirm it with one read of each named line, then write the
failing test, then the fix. A run that reads for an hour and writes nothing is the failure mode.

## The defect, pinned

Production log 2026-09-15 (shape-only, the owner's own account):

```
10:24:53 account.delete accountHash=acct_c876a1fa RecordsPurged=0 BlobsPurged=0 GraceEndsAt=2026-10-15
11:22:50 auth.session Provider=apple Outcome=matched accountHash=acct_c876a1fa
11:22:51 GET /v1/sync/pull -> 410 deviceId=cda7ad23-…   (device log: errorCode=device_revoked)
11:23:03 auth.session … Outcome=matched            11:23:04 GET /v1/sync/pull -> 410 deviceId=86d8a93b-…
11:23:35 auth.session … Outcome=matched            11:23:38 GET /v1/sync/pull -> 410 deviceId=d2d7b2bd-…
```

The user deleted the account, changed their mind a minute later, signed in with the same Apple ID
three times, and each time Settings showed *"This device was signed out - sign in to reconnect"*,
whose only action is the sign-in that produced it. Locked out until the purge on 2026-10-15.

**Cause, backend, two lines:**

1. `backend/src/Tankbook.Api/Auth/AuthRepository.cs:96-116` `FindOrCreateAccountAsync`: the insert is
   `ON CONFLICT (apple_sub) DO NOTHING`, and the fallback `SELECT id, email FROM accounts WHERE
   apple_sub = @Sub` has **no `deleted_at` predicate**. A tombstoned account is returned as
   "matched" and `AuthService.ExchangeSessionAsync` (`AuthService.cs:106-129`) mints a session for it.
2. `backend/src/Tankbook.Api/Sync/SyncRepository.cs:141-153` `IsDeviceActiveAsync` requires
   `a.deleted_at IS NULL`, so every bearer request on that session answers `410 device_revoked`.
   `BlobRepository.cs:30` mirrors the same check.

`docs/SYNC.md:808` already promises: *"a tombstoned account stays fully recoverable for the whole
window before the purge job deletes anything"*. Nothing on either tier IS that recovery. The records
were never purged (`RecordsPurged=0`) - the data is all there.

**Cause, app, one line:** `ios/Sources/TankbookCore/Auth/KeychainSessionStore.swift:91-98` `clear()`
deletes `Account.deviceId` along with the tokens. `AccountDevicesModel.deleteAccount()`
(`ios/App/Sources/Settings/AccountDevicesModel.swift:114-129`) calls `sessionStore.clear()` after the
`DELETE`. So each re-sign-in sends no `deviceId` and `FindOrCreateDeviceAsync`
(`AuthRepository.cs:136-170`) mints a fresh device row - three in three minutes in the log above.
`docs/SECURITY.md:30` says the `deviceId` is a per-install identifier that *"must survive
reinstall-with-restore"*; nothing says it should die at sign-out, and `AuthRepository.cs:130-134`'s own
comment describes re-attaching *"a revoked row that its device returns"* - a path the app can never
take while `clear()` drops the id.

**This brief's diagnosis is a hypothesis - confirm it before you change anything.** Read the four
files above first. If the cause is elsewhere, say so in the report and fix the real one.

## Part A answers (already done, do not re-derive)

- **Siblings:** the `deleted_at IS NULL` guard appears in `SyncRepository.IsDeviceActiveAsync` and
  `BlobRepository.cs:30`; both are the CONSUMERS and stay as they are. The producer with the missing
  predicate is `FindOrCreateAccountAsync` only. Refresh (`AuthService` rotate) cannot be reached during
  grace because `DeleteAccountAsync` revokes every chain (`AccountService.cs:86-104`) - leave it.
- **State creation:** `AccountRepository.TombstoneAccountAsync` (`AccountRepository.cs:129-165`) writes
  `deleted_at`; the purge job `AccountPurgeHostedService` reads `DueAccountsAsync` (`:171-185`) with
  `deleted_at <= cutoff`. A reactivated account must leave that working set - clearing `deleted_at`
  does it; nothing else references the tombstone.
- **Doc vs code:** `SYNC.md:808` promises recoverability the code does not have; `SECURITY.md:30`
  describes a `deviceId` lifetime the app's `clear()` contradicts. Both docs are RIGHT; the code is
  the stale part. Do not weaken either sentence.
- **Axes:** signed-out -> signed-in transition; clean install vs upgrade (an upgraded install has a
  Keychain `deviceId` already; a clean one has none - both must work); RU strings for the card copy.
- **Visibility in production:** the new outcome must be a distinct log value (`Outcome=reactivated`)
  so the next production log answers "did a grace sign-in happen?" in one grep.

## What to build

### Backend (`backend/`)

1. `FindOrCreateAccountAsync` returns a third state. Change the return to carry an outcome
   `Created | Matched | Reactivated` (an enum, not a second bool). Implementation: after the insert
   returns null, run ONE statement:
   ```sql
   UPDATE accounts SET deleted_at = NULL
   WHERE apple_sub = @Sub AND deleted_at IS NOT NULL
   RETURNING id, email
   ```
   (and the `google_sub` twin). A row returned = `Reactivated`. Otherwise the existing `SELECT` =
   `Matched`. Keep it race-safe the way the insert is: the UPDATE is atomic and idempotent.
2. Reactivation must also undo what `DeleteAccountAsync` did to devices: `AccountService` /
   `AuthRepository.RevokeAccountAsync` set `revoked_at` on the account's devices (check what it does -
   `AccountRepository.cs:108` names the device marker). `FindOrCreateDeviceAsync` already clears
   `revoked_at` for a device id the client returns; a client with NO id gets a fresh row, which is
   correct. Do not un-revoke devices the client did not present - the other phones re-attach when
   they sign in again (they hold their own `deviceId`).
3. `TankbookLog.AuthSession` (`Logging/TankbookLog.cs:55`) logs `Outcome=reactivated` for the new
   state. Shape only, as today.
4. `AccountDeleteTests` / `AccountEndpointTests` (`backend/tests/Tankbook.Api.Tests/Account/`) -
   Postgres-backed, so they will be **skipped locally** (Docker's engine is dead on this machine -
   say so in the report; CI runs them). Still write them and make them compile:
   - **The headline test, red on today's code:** delete -> `POST /auth/session` with the same
     subject -> the account's `deleted_at` is null, `GET /sync/pull` with the new bearer is `200`, and
     `DueAccountsAsync` at a cutoff past the grace period does NOT return the account. Oracle:
     `SYNC.md:808`'s sentence. On today's code the pull is `410` - that is the red.
   - A session after the PURGE (simulate: run the purge for the account, then sign in) is
     `Outcome=created` with a different account id - the reactivation window is the grace period
     and not longer.
   - The existing cross-account test `AccountBCannotAttachAccountAsDeviceId` still passes -
     reactivation must not widen device attachment.
   If there is a unit-level seam without Postgres (a fake repository the `AuthService` tests use),
   add the `Reactivated` -> log-outcome mapping there too, so at least one new test RUNS locally.

### App (`ios/`)

5. `KeychainSessionStore.clear()` keeps `Account.deviceId`. Add a separate `forgetDevice()` (or
   equivalent) that nothing in the product calls today, so the intent is explicit; sign-out and
   account deletion both call `clear()` and both keep the id. Check every caller of `clear()`
   (`grep -rn 'sessionStore.clear\|\.clear()' ios/App/Sources ios/Sources/TankbookCore`) and every
   test that asserts the id is gone after clear - those assertions encode the defect; rewrite them
   to assert the id SURVIVES, with `SECURITY.md:30` as the oracle.
6. The card. When a `410` follows a sign-in the user just completed, *"sign in to reconnect"* is not
   a next step. With the backend fixed this state should no longer occur for a grace sign-in, but the
   copy still has to survive the case (an older backend, a purged account whose tokens were cached).
   Change nothing about the card's trigger; change the copy only if you can name the next step
   honestly - otherwise leave it and say so in the report. Do NOT add monetization, retries, or a
   modal (hard rule 7, `docs/ERRORS.md`).
7. Docs in the same change: `docs/SYNC.md` -> account deletion gets one sentence: *"Signing in with
   the same Apple/Google subject during the grace period reactivates the account: `deleted_at` is
   cleared, the presenting device re-attaches, sync resumes from the applied cursor."*
   `docs/API.md` `POST /auth/session` names the third outcome. `docs/JOURNEYS.md` J11a gets the same
   sentence as a **Fallbacks** line; if J11a carries a `Status: implemented` line, clear it (the story
   changed). `docs/SECURITY.md:30` unchanged (it is already right). `docs/LOGGING.md` if the auth
   event table lists outcomes.

## Explicitly out of scope

- Option (b), a fresh account during grace - rejected by the owner.
- Un-revoking OTHER devices on reactivation - they re-attach on their own sign-in.
- The purge job, the outbox, the ledger - untouched.
- `RV.181` (share hand-off) - a sibling agent may be working in `ios/App/Sources/Shared/` and
  `ios/App/Sources/Settings/DiagnosticsPreviewView.swift`; do not touch those files.

## Docs to read, in order

1. `docs/SYNC.md` -> "Account deletion" (line ~808) - the authority for this row.
2. `docs/SECURITY.md` lines 25-40 and 130-142 (the `deviceId` lifetime and RV.41).
3. `docs/API.md` -> `POST /auth/session` (line ~64 and ~87).
4. `docs/ERRORS.md` -> Settings account card.
5. `docs/LOGGING.md` -> auth events.
6. `docs/DEFECT-PATTERNS.md` - skim Part 1 before adding any fallback.

## Checks (exit codes, from the repo ROOT)

- Backend: `cd backend && dotnet build` -> 0; `dotnet format --verify-no-changes` -> 0;
  `dotnet test` -> 0 with the Postgres-backed tests reported as skipped (state the skipped count).
- iOS: `scripts/gate.sh` -> 0. Current baseline: **`swift test` 2116 tests / 262 suites**, app-target
  bundle **267** - both must RISE. `swiftlint lint` from the repo root, 0 errors.
- Localization: `cd ios && swift run localization-gate` 0 - only if you touched a
  string; then EN + RU screenshots of the Settings card, dark theme, from a booted simulator.
- `RELEASE=1 scripts/gate.sh` only if you touch a `#if DEBUG` seam (you should not need to).

## Mutation the brief names

Revert the `deleted_at` UPDATE in `FindOrCreateAccountAsync` (leave the old SELECT). The headline
backend test must go red (it will only show in CI locally - so ALSO mutate the local seam: make
`clear()` delete the `deviceId` again and the Keychain test must go red). Report both outputs.

## Vacuous traps

- A reactivation test that never calls `DELETE /account` first.
- Asserting `Outcome=matched` still logs - it does, and proves nothing.
- Testing `clear()` keeps the id by reading it back in the same process without going through the
  store's `load()`.
- A device test that presents the SAME `deviceId` on re-sign-in and passes on today's code because
  `FindOrCreateDeviceAsync` already re-attaches - the app-side defect is that the id is GONE; the
  test must start from a cleared store and assert the id is still there.

## Standing fences

- `swiftlint lint` from the repo ROOT, not `ios/`.
- Check the test COUNT, not the exit code; `-only-testing:` matching nothing prints "0 tests".
- Never stash, move or `git checkout` for a clean baseline.
- Never `pgrep -f`; use `pgrep -x`. Never `pkill -f`.
- `simctl launch` on a running app ignores new arguments - `terminate` first.
- Assume you are not alone in the checkout: another agent is live on RV.181. Never move, rename or
  revert a file you did not create.
- You cannot see your own screenshots. State what you captured.
- Never commit.

## Report back

Exit codes observed (verbatim `echo $?`), the failing-then-passing output for the headline test and
the Keychain test, which tests were RUN vs only written (the Postgres ones are "written, skipped
locally"), the mutation outputs, the docs you edited, and **anything you found and did not fix**.
