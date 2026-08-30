# PR.13 – "offline" and "the server is down" are not the same sentence

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`. Expected files:

- `ios/Sources/TankbookCore/Sync/SyncEngine.swift` (`SyncOutcome`)
- `ios/Sources/TankbookCore/Sync/SyncSurface.swift`
- `ios/Sources/TankbookCore/Sync/Restore.swift` if the split reaches it
- the sync transport that classifies the failure
- `ios/App/Sources/Settings/` for the rendered rows and the seeded-transport variants
- `ios/App/Sources/Localizable.xcstrings` – **this file is in your fence and no other lane's.**
  It is not line-mergeable; a sibling touching it at the same time silently loses keys.
- tests under `ios/Tests/` and `ios/App/UITests/SettingsUITests.swift`

Do **NOT** touch `docs/TASKS.md` (the orchestrator ticks it at merge). Do **NOT** touch
`ios/App/Sources/ConfirmManual/`, `ios/App/Sources/Garage/`, `ios/App/Sources/Home/HomeTestSeed.swift`,
`ios/App/Sources/AddVehicle/` – a sibling lane (P2.3b) owns those.

Write code first, explore second.

## Use this simulator

`iPhone 17` – `-destination 'platform=iOS Simulator,name=iPhone 17'`. A sibling agent uses
`iPhone 17 Pro`. **Never** `pgrep -f` / `pkill -f` for a build: a brief is part of the process
command line, so an `-f` pattern matches the sibling and has killed one 48 minutes in. Use
`pgrep -x xcodebuild`.

## What is wrong today

`SyncOutcome.transportUnavailable` (`SyncEngine.swift:18`) is a single `Bool` that `SyncEngine`
sets for **any** transport failure. So a user on a plane and a user whose server is returning 5xx
are told the same thing – and `docs/ERRORS.md` → Settings (the authority for this task) gives them
**different next steps**, quoted verbatim:

| Condition | Shows | Next step |
|---|---|---|
| **Sync now** tapped, offline | Row settles back to "Will sync when you're back online" | None. **The tap is never punished with an error** |
| **Sync now** tapped, server 5xx | "Sync service unreachable - your data is safe on this phone. It will go up automatically when the service is back." | Try again · leave it (auto-retry continues) |

Also from the same table, and load-bearing: **"Offline with a queue" is not an error state** – "a
week offline is the same as an hour (S7)". Offline is a passive, reassuring row. Server-down is the
one that names a next step.

Note the shape already used correctly elsewhere in this file: `authExpired`, `upgradeRequired` and
`refusal` are each separate from `transportUnavailable` **precisely because the honest next step
differs** – the doc comments at `SyncEngine.swift:12-23` say so. Follow that precedent rather than
inventing a new one.

## What to build

1. Split the outcome into **offline** and **server-unavailable**, keeping the existing precedent's
   shape. Whatever you choose (two `Bool`s, or an enum), the classification must be made where the
   transport failure is actually known – do not have the UI guess from an error string.
2. `SyncSurface` renders the two `ERRORS.md` rows above. Keep the S7 guarantees intact:
   - offline with a queue stays a **passive** row and never turns into an error;
   - **nothing is lost either way** – rows stay dirty;
   - a **Sync now** tap while offline is never punished with an error.
3. Both strings through the String Catalog, **EN + RU** (hard rule 10). Read
   `docs/LOCALIZATION.md` before writing the RU: if a `%@` receives runtime data, the surrounding
   phrase must **not** govern its case – that error has shipped twice.

## The trap this task is known to contain – expect it, do not be surprised by it

`SyncEngine` currently maps every transport failure to `transportUnavailable`, and the last change
in this area broke `testLowPowerReasonVanishesWhenTheModeEnds`, because the resumer drains
**through** the opportunistic sync cycle. If that test reddens, it is telling you something real
about ordering – do not "fix" it by skipping the cycle for seeded launches generally. Only
`-freezeSyncState` (the capture script's flag) may skip it.

## Explicitly out of scope

- `PR.14` (the "Changed by sync" row) and `PR.8` (trace headers) – later rows in this same seam.
- Retry/backoff behaviour: `PR.7` shipped it; consume it, don't revisit it.
- Any change to what counts as a *conflict*.

## Named vacuous traps for this task

- A test asserting only that **some** error was produced. It passes under either mapping, which is
  exactly the bug. Each test must pin **which** of the two states came out.
- Asserting the two states differ without asserting **which sentence each renders** – the whole
  point is the user-facing next step.
- Classifying by matching on a localized string, or on an error's `localizedDescription`
  (it bridges to `NSError` and drops a struct's custom text – that made a fixture vacuous in PR.5).
- A UI test that asserts a row *exists* without asserting its text.

## Checks

- `cd ios && swift build` exit 0; `swiftlint lint` exit **0 from the repo root**.
- `cd ios && swift test` – **all 1062 unit tests, never subsetted**; report the observed count. It
  is green on `main` right now, so anything red is yours.
- `xcodebuild -project Tankbook.xcodeproj -scheme Tankbook -destination
  'platform=iOS Simulator,name=iPhone 17' -only-testing:TankbookUITests/SettingsUITests
  -only-testing:TankbookUITests/LowPowerModeUITests test` – both whole suites (LowPowerMode because
  of the trap above). Report the **observed count**: a filter matching nothing prints "0 tests ...
  passed" and exits **0**.
- **Screenshots, EN and RU, dark theme**, one per new state, to `design/screenshots/` as
  `PR.13-settings-offline{,-ru}.png` and `PR.13-settings-server-down{,-ru}.png`. Pass
  `-homeResetDatabase` alongside the seed (seeds are idempotent and silently do nothing on a
  populated database); RU via `-AppleLanguages "(ru)" -AppleLocale ru_RU`. Never drive the
  simulator while an `xcodebuild test` runs.
- **Mutation-check the split**: collapse the two states back into one (classify server-down as
  offline) and confirm a test **fails naming the wrong sentence**, not merely "an error appeared".
  Restore by copying back a backup you made first and verifying with `md5` – **never**
  `git checkout`, which has destroyed uncommitted work in this repo three times.

## Report back

Observed counts and exit codes for every command; which files you touched; the exact EN and RU
strings you added; whether the mutation produced a failure and what it said; the `md5` match after
restore; the screenshot filenames. Say whether you **ran** the tests or only wrote them. Do not
commit – the orchestrator verifies in its own hands and commits.
