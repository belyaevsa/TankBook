# Task PR.6b - the import Cancel exists for the test, not for the user

Repo: **`/Users/sbelyaev/repos/fuel-counter-ios`**, branch `main`. Work in this checkout.

**Tier 1, order 7**, the half PR.6 did not deliver (`df094f0`). Small, but it is a **user-facing
bug the orchestrator reproduced from a screenshot**, and its test passes today.

## Where you may write

```
ios/App/Sources/Import/ImportSourceView.swift
ios/App/Sources/SignIn/RestoringView.swift      (only if it has the same defect - check)
ios/App/UITests/ImportUITests.swift
ios/Tests/TankbookCoreTests/**                  (if a metric belongs in core)
docs/ERRORS.md
```

**Do not** touch anything else - not `Capture/**`, `ConfirmManual/**`, `TankbookCore/Transport/**`
(PR.6's timeouts are verified and closed), `backend/`, `site/`, `Spike/`, `design/`, `project.yml`.
**Do not commit. Do not tick `docs/TASKS.md`.**

## The defect, reproduced from the rendered screen

While a parse is in flight (`-seedImportParsing`, the same state the test drives), the user sees
the primary bar as a **dimmed spinner with no label** and **no Cancel anywhere on screen**. Two
captures were deleted rather than committed because of it.

The Cancel is rendered - `ImportSourceView.swift:280-292`, inside `bottomBar`'s `VStack`, below the
primary bar. And `bottomBar` is the **last child of a plain `VStack`** (`:16-42`), so its lower
content lays out where the **tab bar** is.

**Its test passes anyway**, and this is the part that matters:

```swift
let cancel = app.buttons["importCancelButton"]
XCTAssertTrue(cancel.waitForExistence(timeout: 10))
cancel.tap()
```

`waitForExistence` asserts presence in the **accessibility tree**, and the tap is by coordinate.
`HANDOVER.md` records the rule: **XCUITest's `isHittable` does not model occlusion** - an element
under a bottom bar reports itself hittable, and a "tap" hits whatever is actually on top. So the
affordance exists for the test and not for the user, which is the exact "wait you cannot escape"
that PR.6 was written to remove.

## The pattern to copy - already in this tree

`ManualFillUpView.swift:168` anchors its save bar the right way:

```swift
.safeAreaInset(edge: .bottom) { saveBar }
```

That reserves the space instead of growing into it. `TankbookCore.TabBarMetrics` exists for this
arithmetic (P3.7 moved it into core precisely because a double-counted inset survived two phases
"verified by looking at one device").

## What to build

1. **Make the Cancel visible while parsing** - not merely present. Prefer the established
   `safeAreaInset` anchoring over ad-hoc padding; if you instead move the Cancel above the primary
   bar, say why in your report.
2. **Check `RestoringView` for the same defect** and fix it if it has one. PR.6's agent noted its
   Cancel is reachable only through `-seedRestoreProgress` today - if it is occluded the same way,
   it is the same bug.
3. **The parsing primary bar currently shows a spinner with NO text.** A button whose label
   disappears tells the user nothing about what is happening. Give it a parsing label (EN + RU
   through the String Catalog) so the state is legible without the Cancel having to carry it.

## Explicitly out of scope

The transport timeouts (**PR.6**, closed) · retry/backoff (**PR.7**) · anything outside the two
views named above · `docs/TASKS.md` · committing.

## Tests

```
cd ios && swift build   ; echo "build: $?"
cd ios && swift test    ; echo "test: $?"     # 978 today (verified). MUST rise if you add core metrics.
swiftlint lint          ; echo "lint: $?"     # from the REPO ROOT, must be 0
xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
  -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "app build: $?"
```

**The L4 assertion must be about VISIBILITY, not existence.** `exists` and `isHittable` both lie
here - that is the whole finding. Compare the Cancel's `frame` against the tab bar's (or the
window's safe area) and assert it is not covered. Then keep the existing behavioural assertions -
cancelling returns to the picker and never advances to the preview.

Run only `-only-testing:TankbookUITests/ImportUITests` and **report the observed count** (13 today);
**a `--filter`/selector matching nothing prints "0 tests ... passed" and exits 0** - that caught the
orchestrator three times today, so read the count.

**Never `pgrep -f`** for a build - your brief is part of your command line, and that killed a
sibling agent 48 minutes in. Use `pgrep -x xcodebuild`; never `pkill -f`.

## Mutations you must run and report

1. Put the Cancel back inside the plain `VStack` where it is occluded. **Your new test must fail.**
   If it passes, it is still asserting existence and you have rebuilt the bug's disguise.
2. Remove the Cancel entirely. A test must fail.
3. Remove the parsing label from the primary bar. A test must fail, or the label is unasserted.

A mutation that does not fail is a finding. One that does not **compile** proves nothing and must be
redone. Use a **heredoc** for scripted edits.

## Screenshots - this row IS a screenshot fix

EN **and** RU, dark, of the import parse in flight, named `PR.6b-import-cancel{,-ru}.png`, and
registered in `scripts/capture-screenshots.sh`. Capture **outside** a test run.

**The Cancel must be plainly visible in the image.** Eight captures have now been deleted rather
than committed on this project for not showing their subject, two of them for this very state
yesterday. You cannot see them - the orchestrator opens every one, and this row is judged on that
image, not on the suite.

## Report back

Every command with its **real exit code** and the observed `ImportUITests` count; all three mutation
results; how your L4 assertion distinguishes **visible** from **present**; whether `RestoringView`
had the same defect; the files changed; and anything in this brief that is wrong.

En-dashes only, never em-dashes.
