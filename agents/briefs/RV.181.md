# RV.181 - The diagnostics share reaches AirDrop and not Telegram: share the bundle as a FILE

Task row: `docs/TASKS.md` -> `RV.181` (RV section, status `[~]`, the device report of 2026-09-15 at
the end of the row). Scenario: J13 export / J8b share, and the diagnostics evidence path.

## Where you may write

Only inside this repository checkout. Never commit. Never tick `docs/TASKS.md`.

## Write code first, explore second

The seam is one file and the change is one call site plus one small service function. Do not
re-investigate the presenter - that was done over three sessions and is recorded in the row.

## The defect, and what is already ruled out

**Device report (product owner, iPhone 13, build 1344, 2026-09-15):** Settings -> About -> diagnostics
preview -> Share. Chosen **AirDrop**: the bundle arrived on the Mac. Chosen **Telegram**: nothing
arrived. Same app, same minute, same payload.

**Ruled out:** the presenter. `SharePresenter.present` (`ios/App/Sources/Shared/ActivityView.swift`)
presents from the key window's top-most controller and the completion gate logs the outcome
(`docs/LOGGING.md` -> Shares). AirDrop is an out-of-process extension and it completed, so the
hand-off works. The failure is destination-specific.

**The payload:** `DiagnosticsPreviewView.presentShare()` (`DiagnosticsPreviewView.swift:79-86`) hands
the sheet `items: [text]` - ONE `String` built by `DiagnosticsService.makePreviewText()`
(`DiagnosticsService.swift:61`): the header, ~60 log lines, sync counts, row counts. In the owner's
bundle that is roughly 12-15 KB of text.

**Hypothesis (not yet confirmed by the `diagnostics.share` outcome line - the owner's bundle was
generated before the share, so it does not carry one):** Telegram's share extension accepts plain
text only up to its message limit (4096 characters) and refuses or drops anything longer, while
AirDrop, Notes and Mail accept a `String` of any length. Whether or not that is the exact mechanism,
**a file is accepted by every destination**, and the export door already shares files
(`ExportFlow.swift:27`) - so the robust fix does not depend on confirming the hypothesis.

**Confirm what you can before changing anything:** read the two files above and
`docs/LOGGING.md` -> Shares. If `makePreviewText()` is already written to disk somewhere (an OB row
may have added a file export - `grep -rn 'diagnostics' ios/App/Sources/Settings/*.swift`), reuse it.

## What to build

1. **Share the diagnostics as a file.** Write the preview text to
   `<tmp or caches>/tankbook-diagnostics-<yyyyMMdd-HHmm>.txt` (UTF-8, `.txt`, file protection
   `completeUntilFirstUserAuthentication` like every file the app writes - `docs/SECURITY.md`), and
   hand the sheet `items: [fileURL]`. Keep the on-screen preview exactly as it is. Log
   `AppLog.share(operation: "diagnostics.share", kind: "file", ...)` - `kind` changes from `text` to
   `file`; the event name does not. Remove the temp file after the completion handler fires
   (success or not); a share the user never finishes may leave one behind - sweep the directory on
   the next write so at most one exists.
2. **Keep the text as a second item ONLY if you verify it does not change which destinations
   appear.** A `[fileURL, text]` pair makes some extensions take the text and ignore the file. Default
   to `[fileURL]` alone; say in the report which you chose and why.
3. **Do not touch the other four doors** (export, per-car export, import send-file, the receipt
   photo). They already share file URLs / images. If you find one that shares a bare `String`, report
   it - do not fix it here.
4. Docs in the same change: `docs/LOGGING.md` -> Shares: the `kind` for `diagnostics.share` becomes
   `file`. `docs/TASKS.md` is the orchestrator's - do not edit. `docs/ERRORS.md` if the diagnostics
   preview has a row naming the share.

## Explicitly out of scope

- Re-diagnosing the presenter. `RV.181`'s history is in the row; the seam stays as it is.
- Telegram-specific code of any kind. There is no destination detection (hard rule 12: never log a
  destination app either).
- `RV.286` - a sibling agent is live in `ios/Sources/TankbookCore/Auth/`,
  `ios/App/Sources/Settings/AccountDevices*.swift`, `SettingsView.swift`, `backend/`. Do not touch
  those.

## Docs to read, in order

1. `docs/LOGGING.md` -> Shares (line ~170) - the authority for the log shape.
2. `docs/SECURITY.md` -> file protection classes (hard rule 11).
3. `docs/ERRORS.md` -> Settings / About & feedback.

## Checks (exit codes, from the repo ROOT)

- `scripts/gate.sh` -> 0. Baseline: **`swift test` 2116 / 262**, app-target bundle **267** - the app
  bundle must RISE (the new tests below are app-target). `swiftlint lint` from the repo root, 0.
- `xcodebuild test -only-testing:TankbookUITests/RV181ShareHandoffUITests` - report the observed
  count (non-zero), and note `testExportReachesSaveToFiles` is a known flake that passes alone.
- Screenshot, EN and RU, dark: the diagnostics preview with the share sheet OPEN showing the file
  row (the sheet's header names the `.txt`). The simulator cannot prove a Telegram dispatch - state
  that plainly; the owner's iPhone is the acceptance.

## Tests you must add (app-target bundle, `ios/App/Tests/`)

- `RV181DiagnosticsFileShareTests`: the share item built for the diagnostics preview is a single
  file URL whose path ends in `.txt`, whose contents equal `makePreviewText()`'s output byte for byte
  (oracle: the preview on screen IS the file), and whose file protection attribute is
  `completeUntilFirstUserAuthentication` (oracle: `SECURITY.md`). **Red on today's code**: today the
  item is a `String`.
- The temp file is gone after the completion handler runs with `completed: false` (a cancel must not
  leave the bundle on disk).
- Extend `RV181ShareSeamSourceTests` (it greps sources for the seam) only if it asserts the diagnostics
  call shape.

## Mutation the brief names

Change `items: [fileURL]` back to `items: [text]`; `RV181DiagnosticsFileShareTests` must go red.
Report the output.

## Vacuous traps

- A test that asserts the share sheet APPEARS - that passes on today's code and is exactly how this
  row shipped broken twice.
- Writing the file but still passing `[text]` to the sheet.
- Asserting the `.txt` exists without reading it back against `makePreviewText()`.

## Standing fences

- `swiftlint lint` from the repo ROOT, not `ios/`.
- Check the test COUNT, not the exit code.
- Never stash, move or `git checkout` for a clean baseline.
- Never `pgrep -f`; use `pgrep -x`. Never `pkill -f`.
- `simctl launch` on a running app ignores new arguments - `terminate` first.
- Assume you are not alone in the checkout: another agent is live on RV.286. Never move, rename or
  revert a file you did not create.
- You cannot see your own screenshots. State what you captured.
- Never commit.

## Report back

Exit codes observed (verbatim), the failing-then-passing output for the headline test, the mutation
output, which tests RAN, the item shape you chose ([fileURL] or [fileURL, text]) and why, and
**anything you found and did not fix** - in particular any other door that shares a bare `String`.
