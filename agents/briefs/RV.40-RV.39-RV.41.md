# RV.40 → RV.39 → RV.41 – the account lifecycle: sign out, keep your identity, stop duplicating your phone

**Three rows, one dispatch, in this order.** They are one piece of work: the product owner hit all
three in a single walk, and they interlock. **RV.40 first** because it is the mildest and it decides
a question RV.41 needs answered (does signing out revoke the device row?); **RV.39** next (the
identity the account card shows); **RV.41** last, because it changes the same `POST /auth/session`
RV.39 does and must not be merged blind on top of it.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios` - `backend/`, `ios/` and `docs/`.
**Do not run `git add` or `git commit`. Do not touch `docs/TASKS.md`.**

Use the **`iPhone 17`** simulator for every xcodebuild/xcrun step. No other agent is running.
The next free migration number is **017**.

---

# Part 1 – RV.40: there is no way to sign out

The product owner, 2026-09-03: *"There is no 'sign out' button in the settings, so I revoked access
from my current device."*

**Verified:** `AuthService.signOut` exists (`DELETE /auth/session`) and `SignInFlow.signOutLocally()`
exists, but **neither is reachable from Settings**. `signOutLocally` is wired only into the
restore-failure screens (`RestoringView`, `RestoreFailureViews`) - so only a user whose restore
already failed can sign out. `SettingsView.accountCard` pushes to `Route.accountDevices`, and
`AccountDevicesView` offers **Revoke** (per device) and **Delete account** - two destructive
operations with no ordinary sign-out between them.

So the mildest intent, *"stop syncing this phone"*, has no control, and the user is pushed into a
harsher one with side effects they did not want. **That is how the product owner ended up creating
the duplicate device row in RV.41.** The string `"Sign out"` is already in `Localizable.xcstrings`
EN+RU - the copy exists, the control does not.

## What to build

A Sign out control on the account surface, calling the existing `signOut` (server) plus a local
session clear.

**Hard rule 8 governs what it must NOT do.** Signing out is not deleting:

- the local log stays **completely untouched** - every entry, every attachment;
- unsynced changes are not silently dropped. **If a dirty queue exists, say so and let the user
  decide** (hard rule 7: name the next step), rather than discarding or blocking.

**Decide and record whether sign-out revokes this device server-side or merely drops the local
session.** They differ in whether the device row survives, which is exactly RV.41's subject - so
make this call in Part 1 and let Part 3 depend on it, not the reverse. Write the answer into
`docs/SYNC.md`.

## RV.40 tests

- **L4: sign out is reachable from Settings**, and after it the app is a guest with **every local
  entry still present**. Assert the entry count and a known entry's values - *a sign-out that
  quietly wiped the log would sail through an "a screen changed" check.*
- L4: with a dirty queue, the user is told before anything is dropped.
- `ERRORS.md` (Settings) and `SCREENMAP.md` (the account node) move with it; screenshots EN + RU.

---

# Part 2 – RV.39: the account card forgets who you are

The product owner: *"I signed out, signed in and now my account id is not shown."* The card reads
**"Apple ID"** where it used to read their email.

## The cause, verified - do not re-derive it

`AppIDTokenProvider` builds its `ProviderIdentity` with `email: credential.email`
(`ios/App/Sources/SignIn/AppIDTokenProvider.swift:72`), and **Apple populates
`ASAuthorizationAppleIDCredential.email` ONLY on the FIRST authorization** for a given Apple ID +
app pair. Every later sign-in returns nil, by design, forever. `AuthService.signIn` then calls
`decodeSession(..., email: identity.email)` (`AuthService.swift:82`), so the stored session's email
is nil and `L10n.accountTitle` correctly falls back to the provider name.

**The fallback is right; its input is wrong.** This is not cosmetic: the card is the only place a
user with two accounts can tell which one this phone is signed into.

**The server already has the answer.** `accounts` has an `email` column, populated at first sign-up
from the verified id token's `email` claim (`AuthRepository.cs:87-99`) - and **the JWT carries
`email` on every sign-in**, unlike the credential.

## What to build

- `SessionResponse` (`AuthEndpoints.cs:13`) gains the account's email; `POST /auth/session` returns
  it. `docs/API.md` moves in the same change.
- The client **prefers the server value**, falling back to `credential.email` (a first-run bonus),
  then to the provider name.
- **The private-relay case is real and must survive**: a user who chose Hide My Email genuinely has
  no usable address, and `"Apple ID"` is the correct display then. The bug is showing that fallback
  to someone who has a real email on file.

**One thing to decide and state**: the account insert is `ON CONFLICT DO NOTHING`, so a stored email
is never refreshed. If the first sign-up captured no email and a later token carries one, do you
backfill? Either answer is defensible; an unstated one is not.

## RV.39 tests

- **L2 (backend): a SECOND sign-in with the same Apple subject returns the SAME email as the first.**
  The regression is precisely that the second differs, so *a test that signs in once proves nothing.*
- **L1 (client): a session built from a response carrying an email keeps it when `credential.email`
  is nil.** Assert the rendered title **equals the email** - not that it is non-empty, because
  `"Apple ID"` is non-empty and is the bug.
- Keep a case for the genuine no-email account rendering the provider name, or the fix trades one
  wrong display for another. **Mutation-check both directions.**

---

# Part 3 – RV.41: one phone, two device rows

The product owner, with a screenshot: `Устройства` lists `iPhone · Это устройство` and, greyed
beneath it, a second `iPhone · Выполнен выход` - the same physical phone twice, with nothing to tell
them apart.

## The cause, verified

`AuthService.signIn` posts only `{provider, idToken, device: {name, platform}}`
(`AuthService.swift:76-79`) - **no stable per-install identifier** - and the server mints a fresh
`Guid.NewGuid()` device row on every sign-in (`AuthRepository.cs:137`). So the server cannot
recognise a returning install: **every sign-in is a new device**, and a revoke → re-sign-in cycle on
one phone necessarily produces two rows.

Hard rule 11 already says `deviceId` lives in the Keychain as `AfterFirstUnlockThisDeviceOnly`, and
**the Keychain survives app deletion and re-install** - so the identifier needed to fix this is
already the right shape in the right storage. It is simply never sent at sign-in.

## What to build

Send the stored `deviceId` (when one exists) with `POST /auth/session`, and have the server **reuse
that device row instead of minting a second**.

## The security fence - this is the whole risk of the change

**A client-supplied device identifier must never let a caller claim ANOTHER account's device row.**
Bind the reuse to the **authenticated account from the verified id token**: a device id that does
not belong to this account is ignored and a new row minted, never adopted.

This is the same class of mistake as **`PR.35`**, where `POST /auth/session` verified the signature
and never the audience, so any developer's id token was accepted. **Treat a client-supplied id as an
unverified claim, never as authority.**

**Decide too what a REVOKED row does when its device returns**: re-attach (the row goes live again)
or stay revoked and mint a new one - which is today's behaviour and is exactly what the product
owner is looking at. Whichever you choose goes in `docs/API.md` and `docs/SECURITY.md`. Note the
interaction with Part 1: if sign-out revokes server-side, then every ordinary sign-out → sign-in
hits this path, so the answer matters more than it looks.

## RV.41 tests

- **L2: sign in, revoke, sign in again with the same stored deviceId → the account has ONE device
  row, not two.** Assert the row **COUNT and the id**, never that sign-in succeeded - *it succeeded
  throughout the bug.*
- **L2: account B cannot attach account A's deviceId.** Assert A's row is untouched and B got a new
  one. This is the fence; without this test the fix is a vulnerability.
- **Mutation-check the count assertion** and report it.

---

## Read before writing

1. **`CLAUDE.md`** - hard rules 1, 7, 8 (nothing lost silently), 10, 11 (Keychain, `deviceId`), 12, 14.
2. `docs/SECURITY.md` (the `PR.35` audience finding is the precedent for Part 3's fence),
   `docs/API.md` → auth, `docs/SYNC.md`, `docs/SCREENMAP.md`, `docs/ERRORS.md`.
3. `backend/src/Tankbook.Api/Auth/` (`AuthEndpoints`, `AuthRepository`, `AppleGoogleIdTokenVerifier`).
4. `ios/Sources/TankbookCore/Auth/` (`AuthService`, `AuthSession`, `KeychainSessionStore`),
   `ios/App/Sources/SignIn/AppIDTokenProvider.swift`, `ios/App/Sources/Settings/SettingsView.swift`
   and `AccountDevicesView.swift`.

## The baseline gate (CLAUDE.md rule 14)

    cd backend && dotnet build ; echo "BUILD=$?"
    cd backend && dotnet format --verify-no-changes ; echo "FORMAT=$?"
    cd backend && dotnet test ; echo "TEST=$?"
    cd ios && swift build ; echo "IOSBUILD=$?"
    cd ios && swift test ; echo "IOSTEST=$?"
    swiftlint lint ; echo "LINT=$?"          # from the repo ROOT
    swift run --package-path ios localization-gate --sources ios/App/Sources \
      --catalogue ios/App/Sources/Localizable.xcstrings ; echo "L10N=$?"
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "APPBUILD=$?"

**Today: backend 362, iOS 1228. Neither may fall.**

**Echo the exit code from the COMMAND, never through a pipe** - `cmd | tail -2 ; echo $?` reports
`tail`'s status. Redirect to a file instead. Run swiftlint from the **repo root**; from `ios/` its
root-relative `excluded:` paths report thousands of phantom violations.
`backend/scripts/dev-up.sh` starts Postgres + MinIO (plain `docker run`, no compose).

Match the process NAME (`pgrep -x ...`). **Never `pgrep -f` or `pkill -f`** on a build/test pattern.

## Vacuous-assertion traps, named

- Asserting sign-in "succeeded" in Part 3. It succeeded throughout the bug.
- Asserting the account title is non-empty in Part 2. `"Apple ID"` is non-empty and is the bug.
- Asserting a screen changed after sign-out in Part 1, rather than asserting the entries survived.
- Testing Part 3 with only one account. The fence needs a second one.

## Screenshots

EN **and** RU, dark, outside any test run, capture lines added to
`scripts/capture-screenshots.sh`: the Settings account card with a real email (Part 2), and the
sign-out control plus its dirty-queue warning (Part 1). RU is the real test - "Выполнен выход" and
the sign-out confirmation are long.

If the simulator has been driven hard, `xcrun simctl shutdown` + `erase` + `boot` before capturing:
a stale device silently produces shots of the wrong screen, which is worse than no shot.

You have no image input - say so plainly. The orchestrator opens every screenshot personally.

## Report back

- Exit codes (captured, not piped) and test counts before/after, **both tiers**.
- **Part 1:** does sign-out revoke server-side or only drop the local session, and where you wrote
  it down. What happens to a dirty queue.
- **Part 2:** whether you backfill an email that was absent at first sign-up, and why.
- **Part 3:** what a revoked row does when its device returns; **and quote the test that proves
  account B cannot attach account A's deviceId** - that one is the fence.
- The mutation results (Part 2 both directions, Part 3 the count).
- Confirmation the local log is untouched by sign-out.
- Files changed, docs extended, anything unfinished - named plainly.
