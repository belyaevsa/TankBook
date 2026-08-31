# PR.14 – "Changed by sync" is real data, not a fixture

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`:

- `ios/Sources/TankbookCore/Sync/` (the overwrite query, the restore round trip)
- `ios/App/Sources/EditEntry/` (the row; delete `-forceChangedBySync`)
- `ios/App/Sources/Navigation/ToastCenter.swift`, `ios/App/Sources/Home/HomeView.swift`,
  `ios/App/Sources/Settings/AppSync.swift` (the post-batch toast)
- `ios/App/Sources/Localizable.xcstrings` – **you own it this run.** Not line-mergeable: add keys,
  never restructure.
- tests: `ios/Tests/`, `ios/App/UITests/EditEntryUITests.swift`

Do **NOT** touch `ios/App/Sources/Home/HomeSections.swift`,
`ios/App/Sources/Shared/StatTile.swift`, or `docs/TASKS.md` – a sibling lane (P6.13) owns the first
two.

Write code first, explore second.

## Use this simulator

`iPhone 17 Pro`. A sibling uses `iPhone 17`. **Never** `pgrep -f`/`pkill -f` for a build (a brief is
part of the process command line; that pattern killed a sibling agent once). Use `pgrep -x xcodebuild`.

## What is wrong today

The "Changed by sync" row is a **fixture**, driven by `-forceChangedBySync`
(`EditEntryView.swift`, `EditEntryRows.swift`). The real `syncOverwrite` log already stores what it
needs, so **overwrites are recorded and invisible**: a sync silently changes a user's entry and
nothing surfaces it.

That is **hard rule 8** - *nothing lost silently; conflicts surface as badges where the data lives,
never as modals at sync time* - and it is currently unmet on the one screen where the data lives.

## What to build

1. The row is built from the **real** `syncOverwrite` log: the device that overwrote, the date, and
   a **"Restore my version"** action that round-trips.
2. The post-batch toast **"Synced. N entries need a look"** driven by
   `SyncOutcome.flaggedEntries` - not a constant, not a fixture.
3. **Delete `-forceChangedBySync`.** A launch flag that fakes the state is exactly what let this
   ship unbuilt; leaving it lets the next person fake it again.
4. Strings EN + RU. Read `docs/LOCALIZATION.md` first: **if a `%@` receives runtime data, the
   surrounding phrase must not govern its case** - that error has shipped twice in Russian
   ("с вашего телефон Android"), and "N entries need a look" is a plural, so check the 11/21 plural
   edges the audit documents.

## Hard rules that bound this

- **Rule 8**: the badge lives where the data lives. No modal at sync time, no interruption.
- **Rule 13**: "Restore my version" gives the user back *their* value; once they have chosen, no
  later merge may quietly overwrite it again.
- **Rule 12**: log ids, counts and codes - never the amounts or stations involved.

## Named vacuous traps

- A test asserting the row **appears** without asserting it names the **right device and date** from
  the log. A constant row passes that, which is the bug you are removing.
- A toast test asserting a toast appeared without asserting **N** matches `flaggedEntries`. Pin the
  number, or a hardcoded 1 passes.
- Asserting "Restore my version" is tappable without asserting the **value actually returns** to the
  user's version and **survives** the next sync. The round trip is the guarantee.
- Testing at L1 only. `EditEntryView` lives in `ios/App`, which **no core test can reach** - a
  guarantee here pins at L4 or nowhere. That mistake was made twice in one session.

## Checks

- `swift build --package-path ios` exit 0; `swiftlint lint` exit **0 from the repo root**.
  **`swift build` does not compile `ios/App`** – also run `xcodebuild ... build` → `BUILD SUCCEEDED`.
  Files stay under **700 lines** (`file_length` is an error here).
- `swift test --package-path ios` – whole suite, never subsetted; it stood at **1105**. Report the
  observed count (a sibling is adding tests underneath you - say what you saw, a rise is not a
  failure).
- `xcodebuild ... -only-testing:TankbookUITests/EditEntryUITests
  -only-testing:TankbookUITests/SettingsUITests test` on `iPhone 17 Pro`, whole suites, then
  `scripts/check-ui-test-count.sh` on the log.
- **Screenshots EN + RU, dark**: the real "Changed by sync" row
  (`design/screenshots/PR.14-changed-by-sync{,-ru}.png`) and the batch toast
  (`PR.14-synced-toast{,-ru}.png`). `-homeResetDatabase` alongside the seed; never drive the
  simulator while `xcodebuild test` runs. The orchestrator opens these - RU runs 20-30% longer and
  a toast is where that overflows.
- **Mutations, two**: (a) make the row's device/date constant instead of reading the log, and
  confirm a test fails **naming the wrong device**; (b) make the toast's N a constant and confirm a
  test fails on the count. Restore by copying backups back and verifying `md5` – **never**
  `git checkout`.

## Report back

Observed counts and exit codes; how the row reads the overwrite log; whether "Restore my version"
round-trips and survives a subsequent sync; both mutation results; `md5` matches; the RU strings you
added and the plural forms you used; screenshot filenames. Say whether you **ran** the tests or only
wrote them. Do not commit.
