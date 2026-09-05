# RV.73 - import fails on every file the user actually picks

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`, and within it only:
`ios/App/Sources/Import/**`, `ios/Sources/TankbookCore/**`, `ios/Tests/**`, `ios/App/UITests/**`,
`docs/ERRORS.md`, `docs/LOGGING.md`, `design/screenshots/**`.

**Never move, rename or delete a file you did not create.** Another agent has just finished work in
this checkout (sync/logging files); if something looks wrong or a test is red and you did not touch
it, **report it and carry on** - do not "clean the baseline".
Do NOT tick anything in `docs/TASKS.md` - the orchestrator ticks at merge. Do NOT commit.
No `git add -A`, `git checkout`, `git stash`, `git clean`.

## The defect, diagnosed to a line

The product owner picked a My Fuel Manager CSV from the Files app on build `1.0.0+714` and got the
amber card **"We couldn't read that file - try again, or send it to us."**

**The server never saw a request.** In the same minute the device pulled, pushed a 5-item batch and
uploaded a 115 KB blob - the connection was healthy - and the server log contains **no
`/v1/import/parse` line at all**. So the failure is local, before any network call. This is
**not** RV.68 (the missing `/v1`); that fix is in this build.

**The mechanism:**

- `ImportFlowModel.parse(fileURL:)` reads the picked file with
  `guard let data = try? Data(contentsOf: fileURL) else { parseFailure = .unknown; return }` -
  `ios/App/Sources/Import/ImportFlowModel.swift:280`.
- **Neither `.fileImporter` handler takes the security scope**:
  `ios/App/Sources/Import/ImportWizardView.swift:60-67` (the parse path) and `:338-344` (the
  "Send us the file" path, which hands the URL to `SendFileConsentSheet(fileURL:)` at `:346`).
- A URL from the system file picker is **security-scoped**. Outside the app container the read is
  refused, `try?` swallows the error, the `.unknown` card renders, and nothing is uploaded - exactly
  the two symptoms observed together.

**Why no gate caught it:** every test and screenshot reads from `Bundle.main` or
`FileManager.default.temporaryDirectory` (`installSeededParse` at `ImportFlowModel.swift:137-146`,
`ImportService.resource` at `ImportService.swift:184-190`, the `-seedSendFile` seam at
`ImportWizardView.swift:355+`). **Neither location needs a security scope, so both pass against the
live bug.** This is the RV.49 lesson a second time: a suite that exercises a different entry point
than production is not measuring production.

## Write code first, explore second

The cause is named above. Do not go re-derive the import wizard.

## What NOT to explore

- The server. **Nothing on the backend changes.** `/v1/import/parse` is fine and was never called.
- RV.68's URL fix and `TransportErrorClassifier` - already correct, already tested.
- The MFM parser, the review list, duplicate detection, the commit step. All out of scope.
- Whether import should be local (hard rule 9: server-side parsing is a decided, written exception).

## What already exists

- `ImportFlowModel` (`ios/App/Sources/Import/ImportFlowModel.swift`) - `parse(fileURL:)` at `:275`,
  `parseFailure`, `uploadedFileData`, `performParse`, `cancelParse`.
- `ImportWizardView` (`ios/App/Sources/Import/ImportWizardView.swift`) - the two `.fileImporter`s.
- `SendFileConsentSheet(fileURL:)` - the PJ.20 share path, same URL, same defect.
- `AppLog` / `TankbookLog` and the OB.2 event vocabulary (`ios/Sources/TankbookCore/Logging/`) -
  use the existing facade for the new log line; do not invent a logging mechanism.
- `docs/ERRORS.md` -> Import: the existing card copy and next steps.

## Read before writing

1. `docs/ERRORS.md` -> Import (**authority** for the copy and the next step of each state).
2. `docs/LOGGING.md` §4 and hard rule **12** - what may be logged.
3. `CLAUDE.md` hard rules **1** (import parsing is the ONE network exception; everything else about
   import is local), **7** (every error names its next step), **12**, **14**, **15**.

## What to build

### 1. Take the security scope around every read of a user-picked URL

Both `.fileImporter` handlers. `startAccessingSecurityScopedResource()`, and
`stopAccessingSecurityScopedResource()` in a `defer` - released on every path, including the early
returns. Note the API returns a `Bool`; a `false` return is not automatically fatal (a URL already
inside the container needs no scope), so **do not turn a `false` into a failure** - attempt the read
either way and let the read decide.

### 2. Copy the picked file into the app container, and say why in a comment

The scope is released as soon as the handler returns, but the URL outlives it: `uploadedFileData`,
the "Send us the file" share and any retry all read later. Copy the bytes into the app's own
container at pick time and work from that copy. **Decide and write down** (a doc comment plus the
`docs/ERRORS.md` note) whether the copy is deleted at the end of the wizard or lives with the other
import artefacts - do not leave it undecided. It holds user data, so it must not outlive its use.

### 3. Stop swallowing the error, and split the two states

- `try?` discards the error, which is why this had to be diagnosed from the ABSENCE of a server
  line. Log the read failure with the error's **type and code** - never the path, never the file
  name, never a byte of content (hard rule 12).
- **"We couldn't read that file" and "we read it but couldn't parse it" are different problems with
  different next steps** (hard rule 7). Today both land on `.unknown`. Give the read failure its own
  state and its own copy: the next step for an unreadable file is "pick it again" / "move it out of
  iCloud", not "choose a different app". Take the wording from `docs/ERRORS.md` -> Import and extend
  that doc in the same change.
- EN **and** RU through the String Catalog, full localised phrases, never concatenation. The
  localization gate must stay 0.

## Explicitly out of scope

Widening `allowedContentTypes` (that would mask this, not fix it). Any backend change. The parser.
Making import work offline. Touching `docs/TASKS.md`.

## Tests

**Report the counts you observe, before and after; they must rise.** The suite was 1444 tests / 152
suites on 2026-09-05 before the OB.3 row landed - read the current number yourself, do not trust
this line.

L1 (`ios/Tests/`): put the read behind an injectable seam (a small `FileReading` closure or
protocol) so the states are testable without a real scoped URL:
- a reader that fails with a permission-shaped error -> the **read-failure** state, and a log line
  carrying the error type and **no path and no file name**;
- a reader that succeeds but the server rejects the body -> the **parse-failure** state (unchanged
  behaviour, asserted so the split cannot collapse back);
- the two states are distinct values, not one string.
- Assert the copied file is written where you decided and cleaned up when you decided.

L4: `ImportUITests` (and `ImportRV68UITests` if you touch its paths) must stay green.
**If there is no way to drive the real `.fileImporter` from XCUITest, say so plainly rather than
asserting the seeded path again** - the seeded path is the one that already passes against the live
bug, and an L4 test over it is worth nothing here. Name the suites you run with `-only-testing:`.
Do NOT run the whole UI suite (2026-08-29 rule). Check the observed count is non-zero.

### Vacuous-assertion traps, named

- **Any test that reads from `Bundle.main` or `FileManager.default.temporaryDirectory`.** Neither
  needs a security scope, so both pass today, against the live bug. This is the trap that let the
  defect ship.
- Asserting "an error card renders" - one already does, with the wrong message.
- Mocking `Data(contentsOf:)` to succeed and asserting the happy path.
- Asserting `startAccessingSecurityScopedResource` was *called* rather than that the failure state
  and the message are now correct.

### Mutation checks (run them, report which named test failed, restore byte-for-byte)

1. Remove the `startAccessing...` call -> the permission-shaped read test must fail.
2. Map the read failure back onto the parse-failure state -> the split test must fail.
3. Delete the `defer` release -> say what, if anything, catches it. **If nothing does, report that
   as a Residual** rather than inventing a test that cannot fail.
4. Log the file name in the read-failure line -> a privacy assertion must fail.

A mutation that **passes** is a finding: the test is vacuous. Say so.

## The baseline gate (CLAUDE.md rule 14)

From the **repo ROOT**, judged by exit code (`echo $?`):
- `cd ios && swift build` -> 0
- `cd ios && swift test` -> 0, count reported
- `swiftlint lint` **from the repo root** -> 0 errors (running it from `ios/` produces thousands of
  phantom violations)
- the localization gate **from the repo root** -> 0
- `xcodebuild -project Tankbook.xcodeproj -scheme Tankbook -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TankbookUITests/ImportUITests -only-testing:TankbookUITests/ImportRV68UITests test` -> 0
  (`swift build` does not compile `ios/App`; only `xcodebuild` does. `xcodegen generate` first if
  you added a file.)
- **Never `pgrep -f` for a build** - your own brief is in your command line and you will match a
  sibling agent. Use `pgrep -x xcodebuild`.

## Screenshots

Only if the copy changes - and it will, because the read-failure state is new. EN **and** RU, dark,
`design/screenshots/RV.73-import-read-failed.png` / `-ru.png`.
- Capture outside a test run (`simctl` and `xcodebuild test` fight over the device).
- RU: `xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU`.
- **Verify the pair differs: `md5 -q a.png b.png`**, and report both hashes. RV.58 shipped an "RU"
  shot byte-identical to its EN one because the launch argument did not take.
- You cannot see your own screenshots; do not claim they look right.

## Report back

1. Exit code of every gate, and observed test counts (before -> after).
2. Each mutation: what you broke, which named test failed, that you restored it. Any that passed.
3. **Whether you could drive the real file picker from a test.** If not, say what the honest proof
   of the fix is - that answer matters more than a green suite here.
4. What the user now sees in each of the two states, in EN and RU.
5. Anything in this brief that was wrong. A fence can be wrong the same way a diagnosis can
   (RV.70) - report it as a Residual rather than obeying quietly.
