# RV.54 – "N devices" counts revoked devices, so revoking one changes nothing on screen

**The product decision is already made (product owner, 2026-09-04): option (a) – the number counts
LIVE devices only.** You are implementing a decision, not making one. Do not relitigate it.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios` – **`ios/` and `docs/` only.**
**Do not run `git add` or `git commit`. Do not touch `docs/TASKS.md`.** Touch no `backend/` file.
**Never move, rename or delete a file you did not create.** `.claude/worktrees/rv48` is another
session's worktree and is not your gate.

## The diagnosis, verified – confirm, do not re-derive

`GET /account/devices` returns revoked rows **marked, never omitted** – that is deliberate, so a user
can see that a device WAS revoked, and **it must stay that way**. The account card's number is simply
`devices().count`, so it includes revoked rows.

Effect: the user revokes their old phone, the card still reads the same number, and the reasonable
conclusion is that the revoke failed.

**This also made RV.6's brief unsatisfiable**, which is worth knowing: RV.6 demanded a test asserting
the count VALUE changes after a revoke, and that test could not be written while the count included
revoked rows. Your change makes it writable – **write it**.

## What to build

**The card counts LIVE devices only.** The number then answers "how many devices can reach my data",
which is what a user reading it wants, and a revoke visibly decrements it.

**The revoked rows stay in the LIST.** The history is the point of showing them.

**The list and the count must agree.** Today they silently disagree and the LIST is the correct one.

**Check every consumer of the count.** `AppSync.fetchedDeviceCount` feeds the Settings account card;
RV.22's sync chip does NOT read it (already verified – confirm, do not assume). Enumerate what reads
it and say so.

**Do not change what the endpoint returns** – this is a client-side counting change. The server keeps
returning revoked rows marked.

## Read before writing

1. **`CLAUDE.md`** – hard rules 7 (every error names its next step), 8 (nothing lost silently), 10
   (EN+RU, whole phrases – "1 device" / "2 devices" pluralises differently in RU, which has THREE
   plural forms: 1 устройство, 2 устройства, 5 устройств), 14.
2. `docs/API.md` -> `/account/devices`; `docs/SCREENMAP.md` -> the account screen.
3. `ios/App/Sources/Settings/AppSync.swift` (`fetchedDeviceCount` and every reader),
   `AccountDevicesModel.swift`, `AccountDevicesView.swift`, `SettingsView.swift`,
   `ios/Sources/TankbookCore/Account/AccountClient.swift`.

## Tests

**iOS unit 1322 today; must not fall.** Name the UI suites you run; expect
`AccountDevicesUITests` and `SettingsUITests`.

- **The headline L1: with a server list of 3 devices of which 1 is revoked, the count reads 2 and
  the LIST still shows 3 rows.** Both halves in one assertion set – that is the "list and count must
  agree" contract.
- **The RV.6 test that was unwritable: after a revoke, the count VALUE decrements.** Assert the
  number, not that a request happened.
- L1: a list of all-revoked devices reads 0 without crashing or rendering a negative.
- L4: the account card renders the live count, EN and RU, with correct pluralisation for 1, 2 and 5.

**Vacuous-assertion traps, named:**
- Asserting the list renders. It always did.
- Asserting the count is non-nil. It was non-nil throughout the bug.
- Asserting `count == devices.count` – that is the bug restated as a test.

**Mutation-check and report it**: restore the count to include revoked rows and confirm the
decrement test goes red. Restore byte-for-byte, confirm green.

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

**Required, EN and RU, dark** – the card's number is what the user sees. Save as
`design/screenshots/RV.54-account-devices.png` and `-ru.png`, captured OUTSIDE a test run.
**The RU plural forms are the specific risk here** – shoot a case with a revoked device present.
You have no image input; say so.

## Report back

- Exit codes (captured, not piped), counts before/after, UI suites run, mutation result.
- **The full list of `fetchedDeviceCount` consumers** and what each now shows.
- Confirmation the endpoint is unchanged and revoked rows still appear in the list.
- Confirmation the RV.6 test is now written and passing.
- Anything you noticed that is not RV.54 – named separately.
