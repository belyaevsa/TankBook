# OB.4 / PR.11 - the user can send what the device knows about itself

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`, and within it only:
`ios/Sources/TankbookCore/Logging/**`, `ios/Sources/TankbookCore/Persistence/**` (reads only - no
migration, no schema change), `ios/App/Sources/Settings/**`, `ios/App/Sources/Shared/**`,
`ios/Tests/**`, `ios/App/UITests/**`, `docs/LOGGING.md`, `docs/ERRORS.md`, `docs/SCREENMAP.md`,
`design/screenshots/**`.

**Never move, rename or delete a file you did not create.** A second Claude session works in this
checkout (reminders code, and a worktree under `.claude/worktrees/`). Expect files and even a red
test that are not yours: **report them and carry on**, never "clean the baseline".
Do NOT tick anything in `docs/TASKS.md` - the orchestrator ticks at merge. Do NOT commit.
No `git add -A`, `git checkout`, `git stash`, `git clean`.

## What this row is, and what is already built

`docs/LOGGING.md` §5 promises an opt-in **"Attach diagnostics"**: the last 24 h of our own INFO+ log
entries, run through the redactor, **previewed by the user before anything leaves the device**.
Today the data-assembly half exists and **nothing reaches a screen**:

- `DiagnosticsExport` / `DiagnosticsBundle` (`ios/Sources/TankbookCore/Logging/DiagnosticsExport.swift`)
  assembles breadcrumbs + app/device metadata and renders them - **it has no caller in the app
  target at all.** Verify that yourself with a grep before you start; it is the shape of this row.
- The breadcrumb ring is real and already redacted (`Logging/Breadcrumbs.swift`, `Redactor.swift`).
- **`OSLogStore` is not used anywhere.** The 24-hour window §5 promises does not exist yet.
- The bundle carries **no sync state and no row counts**, which the row requires.

This is the last row of the OB cluster, and the two before it did the work it stands on: OB.2 emits
the events, OB.3 persists the sync state. Nothing else blocks it.

## What already exists (build on these; do not duplicate or redesign)

- `DiagnosticsBundle.rendered()` - the exact text the user previews and sends. Extend it; keep the
  `key=value` line shape the redactor's `LogRenderer` already uses.
- `TankbookLog` / `AppLog` (`ios/App/Sources/AppLog.swift`), subsystem `live.belyaev.tankbook`,
  categories in `docs/LOGGING.md` §4. **The app logs only through this facade**, so the subsystem is
  the correct `OSLogStore` predicate.
- `LogContext` (appVersion, platform, deviceId) and `LogRenderer.timestamp`.
- **OB.3's persisted sync state** (`ios/Sources/TankbookCore/Sync/SyncStateStore.swift`):
  `PersistedSyncState(lastSuccessAt:lastFailure:)`, and `SyncFailureRecord(at:kind:code:traceId:)`.
  `SyncCoordinator.lastSyncDate()` / `.lastOutcome()` / `.lastFailure()` are the live readers, and
  `AppSyncSurface` (`ios/App/Sources/Settings/AppSync.swift`) already holds `dirtyCount` and
  `flaggedCount`.
- `Repository.rowCount(in:)` (`ios/Sources/TankbookCore/Persistence/Repository.swift:541`) - **the
  row-count query already exists.** Use it; do not write SQL.
- `AboutView` (`ios/App/Sources/Settings/AboutView.swift`, 87 lines) and `FeedbackComposerView` /
  `FeedbackModel` - PJ.20's composer, with the **once-asked consent default OFF and persisted**
  (`FeedbackConsentStore`) and a separate `attachDeviceModel` toggle. Follow that pattern exactly.
- `ActivityView` (`ios/App/Sources/Shared/ActivityView.swift`) - the share sheet wrapper.
- `AboutUITests` (`ios/App/UITests/AboutUITests.swift`, 2 tests today).

## Read before writing (in this order)

1. `docs/LOGGING.md` §5 (**the authority for this row**), plus §4 for the field vocabulary and §6
   for what we deliberately do not build.
2. `docs/ERRORS.md` -> About & feedback.
3. `docs/SCREENMAP.md` - the preview is a new screen; add it to the graph with its back path.
4. `CLAUDE.md` hard rules **7**, **11**, **12**, **13**, **14**.

## What to build

### 1. The 24-hour window from `OSLogStore`

Collect this app's own INFO+ entries for the last 24 h, subsystem `live.belyaev.tankbook`, and merge
them with the breadcrumb ring (the ring is the in-memory fallback and covers what OSLog may have
dropped). **Every collected line goes through the same redactor before it is held**, exactly as
`DiagnosticsExport.make(lines:)` already assumes - never trust a line because OSLog produced it.

`OSLogStore` can fail or be unavailable (permissions, simulator, an empty store). That is a
**degraded bundle, not an error**: fall back to breadcrumbs alone and say so **in the bundle itself**
(a `logStore=unavailable` line), so support can tell a quiet device from a missing capability. Put the
window (24 h) and the entry cap where `docs/PRACTICES.md` says a compiled constant belongs, with the
reasoning in a comment.

### 2. What the bundle carries

Extend `DiagnosticsBundle` with, and nothing beyond:
- **Sync state**: last success (`lastSuccessAt`), dirty count, flagged count, and the last failure -
  its class, its `code` and its `traceId` (OB.3 persists exactly these, and the traceId is what maps
  a user's report to the server's own lines - `docs/LOGGING.md` §2).
- **DB row counts** per table via `Repository.rowCount(in:)` - **counts only**.
- The existing app/device metadata.

**Hard rule 12 governs every field**: ids, counts, codes, durations, field names yes; a station, a
note, an amount, a coordinate, a token, a file name, a path - never. If a field would still be
interesting to someone who wanted to profile the user, it does not ship (§6).

### 3. The opt-in, the preview, the share

- An **"Attach diagnostics"** row on About, **default off, never automatic, never silent** - the same
  once-asked shape as PJ.20's consent, and it must persist.
- A **preview screen showing exactly the text that will be sent** - not a summary of it, not a
  count. That is §5's whole point: the user reads the bytes. Add it to `docs/SCREENMAP.md` with its
  back path.
- Share from the preview via the existing `ActivityView`.
- All copy through the String Catalog, **EN + RU**, full localised phrases, never concatenation.
  The localization gate must stay 0.

## Explicitly out of scope

Sending the bundle to `POST /feedback` automatically (the user shares it; the composer's own
attachment flow is PJ.20's and is done). Any backend change. Crash reporting / Sentry (§6 keeps it
out of v1). A log viewer, search, or filtering UI. Changing what any event logs. `docs/TASKS.md`.

## Tests

**Counts as of commit `43da625`: `swift test` 1455 tests / 154 suites, 0 failures. Report the number
you observe, before and after; it must rise.**

L1 (`ios/Tests/TankbookCoreTests/`):
- The bundle carries the sync fields: given a `PersistedSyncState` with a failure holding a kind, a
  code and a traceId, the rendered text contains all four **and** the dirty/flagged counts.
- Row counts appear as counts.
- **The privacy sweep is the headline test.** Build a bundle from a log whose breadcrumbs were
  recorded over a repository holding a station name, a note and an amount, and sweep the **whole
  rendered output** for those strings - not per-field. Model it on OB.2's
  `everyEventThisRowAddsIsFreeOfDomainValues`, which is the reason that pattern exists.
- `OSLogStore` unavailable -> a bundle that still renders, with the `logStore=unavailable` marker
  and the breadcrumbs intact.

L4 `AboutUITests` (2 tests today, must rise):
- The preview opens from About and **contains none of the seeded station/amount strings** (seed real
  data first - a preview over an empty database proves nothing).
- The opt-in is **off** on first open and the preview is unreachable until it is turned on.

Name the suites you run with `-only-testing:`: `AboutUITests`, plus `SettingsUITests` if you touch
that screen. **Do not run the whole UI suite** (2026-08-29 rule). Check the observed count is
non-zero - a filter matching nothing prints "0 tests ... passed".

### Vacuous-assertion traps, named

- A privacy sweep over an **empty** breadcrumb ring or an empty database. It passes against any bug.
  Seed the values first, then sweep.
- Asserting the bundle is non-empty, or that `rendered()` does not throw.
- Asserting the preview screen *exists* rather than that it shows the same text that gets shared.
- Testing the consent default by reading the model's property instead of the persisted store.
- Asserting `OSLogStore` returned entries - on a simulator it may legitimately return none, which
  makes the test both flaky and vacuous. Assert the **fallback behaviour** instead.

### Mutation checks (run them; report which named test failed; restore byte-for-byte)

1. Skip the redactor on the OSLog lines -> the privacy sweep must fail.
2. Drop the `traceId` from the sync section -> the sync-fields test must fail.
3. Default the opt-in to **on** -> the L4 consent test must fail.
4. Render a summary instead of the full text in the preview -> say what fails. **If nothing does,
   report it as a Residual** rather than inventing a test that cannot fail.

A mutation that passes is a finding: the test is vacuous. Say so rather than moving on.

## The baseline gate (CLAUDE.md rule 14)

From the **repo ROOT**, judged by exit code (`echo $?`):
- `cd ios && swift build` -> 0
- `cd ios && swift test` -> 0, count reported
- `swiftlint lint` **from the repo root** -> 0 errors (from `ios/` it prints thousands of phantom
  violations - that false red has cost two sessions already)
- the localization gate **from the repo root** -> 0
- `xcodebuild -project Tankbook.xcodeproj -scheme Tankbook -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TankbookUITests/AboutUITests test` -> 0
  (`swift build` does not compile `ios/App`; only `xcodebuild` does. `xcodegen generate` first if
  you added a file.)
- **Never `pgrep -f` for a build** - your own brief is in your command line and you will match a
  sibling agent. Use `pgrep -x xcodebuild`.

## Screenshots

EN **and** RU, **dark**, in `design/screenshots/`: `OB.4-about-diagnostics.png` (the About row with
the opt-in) and `OB.4-diagnostics-preview.png` (the preview with real seeded content), plus `-ru`
for each - four files.

- Capture **outside** a test run (`simctl` and `xcodebuild test` fight over the device).
- RU: `xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU`.
- **Verify each pair differs: `md5 -q a.png b.png`**, and report the hashes. RV.58 shipped an "RU"
  shot byte-identical to its EN one and could not tell.
- A `-` prefixed launch argument can **persist across relaunches** - reinstall between shots when a
  consent flag sticks (RV.64), or the "off" and "on" shots will be identical.
- You cannot see your own screenshots. The orchestrator opens all four.

## Report back

1. Exit code of every gate, and observed test counts (before -> after).
2. Each mutation: what you broke, which named test failed, that you restored it. Any that passed.
3. The four screenshot paths and their md5s.
4. **A verbatim sample of a rendered bundle** (from the test fixture, not a real device) so the
   orchestrator can read what a user would actually send.
5. **What a support engineer can now answer that they could not before.** If part of the bundle
   answers nothing, say so - OB.1's report did exactly this and it was worth more than a claim.
6. Anything in this brief that was wrong. A fence can be wrong the same way a diagnosis can (RV.70):
   report it as a Residual rather than obeying quietly.
