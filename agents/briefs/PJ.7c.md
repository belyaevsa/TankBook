# PJ.7c – the Welcome tagline changed and its UI assertion did not

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`. Specifically:

- `ios/App/UITests/WelcomeUITests.swift`
- `design/screenshots/PJ.3b-welcome*.png` (re-capture, see below)
- `docs/TASKS.md` – **do NOT touch it.** The orchestrator ticks it at merge. Editing it causes
  conflicts with other lanes.

Write the fix first, explore second. This is a small, fully diagnosed task; do not redesign
anything.

## Use this simulator

`iPhone 17 Pro` – `-destination 'platform=iOS Simulator,name=iPhone 17 Pro'`, and capture the
screenshots on it. A sibling agent is working on `iPhone 17`; do not touch that device, and
**never** use `pgrep -f` / `pkill -f` for a build (a brief is part of the process command line, so
an `-f` pattern matches the sibling agent - that has killed one 48 minutes into its task). Use
`pgrep -x xcodebuild`.

## The defect, already diagnosed – do not re-bisect it

Commit `4968590` changed the Welcome hero tagline:

- from `A head start, not an answer` (RU `Это фора, а не готовый ответ`)
- to `Scan the receipt – or type the numbers` (RU: see `ios/App/Sources/Localizable.xcstrings`)

It changed `ios/App/Sources/Welcome/WelcomeView.swift`, both artboards
(`design/screens/Welcome.dc.html`, `design/screens/LightWelcome.dc.html`) and the string catalogue –
but **not** `WelcomeUITests.swift:36`, which still asserts the old string:

```swift
XCTAssertTrue(app.staticTexts["A head start, not an answer"].waitForExistence(timeout: 5))
```

`WelcomeUITests.testFreshInstallShowsWelcomeWithThreeHittablePaths` therefore fails on `main`.
Confirmed in the full UI suite run of 2026-08-30 (252 executed, 5 failures).

The old string is **gone from the catalogue**, so the assertion cannot be satisfied. The shipped
copy is correct and the test is what is stale – fix the test, not the app copy.

## What to build

1. Update the assertion (and the comment above it, lines 33-35, which still explains the old
   wording) to assert the **shipped** tagline, quoted verbatim from `WelcomeView.swift`:
   `Scan the receipt – or type the numbers`. Note the dash is an **en-dash (U+2013)**, not a
   hyphen and not an em-dash – copy the character out of the source file rather than typing one.
   The comment should say what the assertion is for: the hero states the two doors of hard rule 15
   in the user's words, so a future copy change cannot silently re-introduce a capture-only promise.
2. Re-capture the four Welcome screenshots, which now show the old tagline and are stale evidence:
   `design/screenshots/PJ.3b-welcome.png`, `-ru.png`, `-light.png`, `-light-ru.png`. Use
   `scripts/capture-screenshots.sh` conventions; pass `-homeResetDatabase` alongside the seed
   (seeds are idempotent and silently do nothing on a populated database), and RU via
   `xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU`.
   **Never drive the simulator while an `xcodebuild test` is running** – check with
   `pgrep -x xcodebuild` (process name; **never** `pgrep -f`, which matches this brief itself and
   has killed a sibling agent before).

## Explicitly out of scope

- The app copy, the artboards, the string catalogue – all three are correct.
- The other four failures in that suite run (`ConfirmManualUITests` ×2, `TankbookShellUITests`,
  `UpdateRequirementUITests`). Other lanes own them.
- The "head start, not an answer" wording in `CLAUDE.md`, `docs/VISION.md`, `docs/EXTRACTION.md`,
  `docs/SITE.md` and `design/screens/SiteLanding.dc.html`: that is hard rule 15's own text and the
  site's body prose, which is where it belongs. Only the **hero slogan** moved.

## The vacuous-assertion trap for this task

Asserting `app.staticTexts.count > 0`, or matching a substring loose enough that any tagline
passes, or deleting the assertion. The point of the line is that **this specific user-facing
sentence** is on the screen. Keep it an exact-label match.

## Checks

- `cd ios && swift build` exit 0; `swiftlint lint` exit **0 run from the repo root**.
- `xcodebuild -project Tankbook.xcodeproj -scheme Tankbook -destination
  'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TankbookUITests/WelcomeUITests test`
  – **all 6 tests in the suite**, not just the one. Report the **observed count**: a filter that
  matches nothing prints "Test run with 0 tests ... passed" and exits 0.
- Mutation check: change the app's tagline in `WelcomeView.swift` to any other string, confirm
  `testFreshInstallShowsWelcomeWithThreeHittablePaths` **fails**, then restore it. Restore by
  **copying the file back from a backup copy you made first and verifying with `md5`** – never with
  `git checkout`, which has destroyed uncommitted work in this repo three times.

## Report back

Exact numbers: the observed test count and pass/fail for `WelcomeUITests`, the two exit codes,
whether the mutation actually failed the test (and the `md5` match after restore), and which
screenshot files you re-captured. Say whether you **ran** the tests or only wrote them. Do not
commit; the orchestrator commits after verifying in its own hands.
