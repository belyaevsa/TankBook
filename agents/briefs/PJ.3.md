# Task PJ.3 - the Welcome root, with its three paths

Repo: **`/Users/sbelyaev/repos/fuel-counter-ios`**, branch `main`. Work in this checkout.

**Tier 2, row 11** - the first row of "required for v1". `SCREENMAP.md`'s root screen **does not
exist in the app**. Today a reinstall or an Android migrant is funnelled into "Add your first car"
as if they were new, and their existing account is never offered.

## Where you may write

```
ios/App/Sources/Welcome/**          (new)
ios/App/Sources/Navigation/**
ios/App/Sources/SignIn/**
ios/App/Sources/Home/**             (only the guest-state wiring)
ios/App/Sources/Localization/L10n.swift · ios/App/Sources/Localizable.xcstrings
ios/Tests/TankbookCoreTests/**
ios/App/UITests/WelcomeUITests.swift (new) · SignInUITests.swift · HomeUITests.swift
ios/App/UITests/TankbookShellUITests.swift
scripts/capture-screenshots.sh
docs/SCREENMAP.md · docs/JOURNEYS.md
```

**Do not** touch `Capture/**`, `ConfirmManual/**`, `Import/**`, `ServiceEntry/**`, `Settings/**`,
`TankbookCore/Sync/**`, `Config/**`, `Transport/**`, `backend/`, `site/`, `Spike/`, `project.yml`.
**Do not commit. Do not tick `docs/TASKS.md`.**

## The artboards are the source of truth for pixels

`design/screens/Welcome.dc.html` and `design/screens/LightWelcome.dc.html`. **Match them; do not
reinvent the screen.** Both exist and are the spec.

## Verified immediately before dispatch - and one row detail is stale

There is **no Welcome view anywhere** in `ios/App/Sources`. `arrivedViaRestore` **already exists**
on `SignInFlow` (`SignInFlow.swift:112,135,143`) and `makeDefault` defaults it to **false**
(`:306`) - so the row's "add the parameter" is not quite right. What is missing is that
**`SignInFlowHost` (`SignInView.swift:7`) does not expose it** and builds its flow internally, so
nothing in production can ever pass `true`, and **J11a's wrong-provider question can never fire**.

## What to build

1. **The Welcome root**, skippable, one screen, three paths: **Add your car** -> AddVehicle;
   **Import from another app** -> ImportWizard; **"Already use Tankbook? Sign in"** ->
   `SignInFlowHost(arrivedViaRestore: true)`.
2. **Shown only with no vehicle AND no session**, and **never again once a car exists**.
3. **Restoring's cancel returns here** (`SCREENMAP.md:118`), not to a dead end.
4. **The guest Home becomes a real state.** `-forceGuestHome` and `-signInWrongProvider` are
   fixtures for states production could not reach; once Welcome exists, both are reachable for real.
   Retire them and let the tests drive the real path - there are 7 references today.
5. **RU locale defaults fuel kinds to 92/95 alongside RUB** - a locale guess is a default input the
   user can change (hard rule 13), never a fact.

**Hard rule 15 applies to this screen.** Two of the three paths are entry doors; neither may be
framed as the lesser one, and "Add your car" must not be styled as the only real choice.

## Explicitly out of scope

The capture pipeline · import parsing · sync · anything in Settings · `docs/TASKS.md` · committing.

## Tests

```
cd ios && swift build   ; echo "build: $?"
cd ios && swift test    ; echo "test: $?"     # 997 today (verified). MUST rise.
swiftlint lint          ; echo "lint: $?"     # from the REPO ROOT, must be 0
xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
  -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "app build: $?"
```

- **L1**: `SignInFlowHost` exposes `arrivedViaRestore`.
- **L4 new `WelcomeUITests`**: a fresh install shows Welcome with **three hittable paths**, each
  lands on its screen, and **Welcome never reappears once a car exists**.
- **L4 `SignInUITests`**: the third path over an empty stub account shows `wrongProviderQuestion`
  **without** `-signInWrongProvider`.
- **L4 `HomeUITests.testGuestStateRendersGuestChrome`**: runs **without** `-forceGuestHome`.
- **L4 `TankbookShellUITests`**: extend the no-dead-ends walk to include Welcome.

Run only the suites you touched with `-only-testing:` and **report the observed count for each**
(`SignInUITests` 8, `HomeUITests` and `TankbookShellUITests` unknown to me - report what you see).
**A selector matching nothing prints "0 tests ... passed" and exits 0** - it caught the orchestrator
three times this session, so read the count. **Never `pgrep -f`** for a build; use
`pgrep -x xcodebuild`, never `pkill -f`.

## Mutations you must run and report

1. Show Welcome when a vehicle already exists. The "never reappears" test must fail.
2. Pass `arrivedViaRestore: false` from the third path. The `wrongProviderQuestion` test must fail -
   this is the one the whole row exists for.
3. Keep `-forceGuestHome` as the only route to the guest Home. The de-fixtured `HomeUITests` case
   must fail.

A mutation that does not fail is a finding. One that does not **compile** proves nothing and must be
redone. Use a **heredoc** for scripted edits.

## Screenshots

**EN and RU, dark AND light** - this row has a light artboard, so light is not optional here.
Name them `PJ.3-welcome{,-ru}{,-light}.png`, register them in `scripts/capture-screenshots.sh`, and
capture **outside** a test run (`simctl` and `xcodebuild test` fight over the device).

**Check the screen is in frame and all three paths are visible.** Eight captures have been deleted
rather than committed on this project for not showing their subject. You cannot see them; the
orchestrator opens every one and reads the Russian for grammar, not only for overflow - RU runs
20-30% longer and short strings expand worst.

## Report back

Every command with its **real exit code** and observed counts; all three mutation results **with the
suites you ran**; how closely the screen matches each artboard and anything you could not match;
which fixture flags you retired and whether any resisted; the files changed; and anything in this
brief that is wrong - eleven agent pushbacks here have been correct.

En-dashes only, never em-dashes.
