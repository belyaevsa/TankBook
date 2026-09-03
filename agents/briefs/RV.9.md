# RV.9 – open an attachment and look at it properly

Reported by the product owner from a device walk: *"When I edit or try to view a log entry, an
attachment is not clickable. I can open and look at the receipt, actual. But I want to look
deeper."* Registered as RV.9 in `docs/TASKS.md`.

The receipt strip shows a **44x56 thumbnail** and nothing else. `AttachmentPhotoChip`'s own doc
comment says *"The chip is decorative"* - so there is no tap target anywhere in this app that opens
a receipt at full size, and no zoom. The photo the entry exists to evidence can only be squinted at.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`. Write nothing outside it, including no temp
files elsewhere. **Do not run `git add` or `git commit`** - the orchestrator verifies independently
and commits.

## Write code first, explore second

The dominant failure mode in this repo's agent runs is a run that reads everything and writes
nothing. The map below is already done. Read those files, then start writing.

## What already exists (build on it, do not redesign it)

- `ios/App/Sources/EditEntry/AttachmentPhotoChip.swift` - the 44x56 chip. Renders
  `attachment.thumbnailBase64` (inline in the payload, zero fetches) or a `photo`/`doc.text` glyph
  when there is none. Overlays a spinner veil while the full rendition has not landed.
- `ios/App/Sources/EditEntry/EditEntryRows.swift` -> `receiptCard(attachments:entry:pendingBlobIDs:onAddReceipt:)`,
  used by **`EditEntryView`** and **`EditEntryNonFillView`**. This is the surface the user tapped.
- `ios/Sources/TankbookCore/Sync/BlobStore.swift`:
  - `BlobStore.data(for: sha256) throws -> Data?` - **synchronous**, nil on a miss. This is how you
    ask "is the full rendition already on this device?" without touching the network.
  - `LazyBlobFetcher.fetch(sha256:) async throws -> Data` - **cache-first**: a hit returns
    immediately, a miss downloads, verifies the bytes hash to the requested sha256, discards them
    on mismatch (`BlobSyncError.hashMismatch`) and caches. Never bypass it; never display unverified
    bytes.
- `ios/App/Sources/Settings/AppSync.swift` -> `SyncService.makeBlobFetcher(sessionStore:)` returns
  **nil when signed out**. A guest has no fetcher, and that is a state you must render, not a crash.
- `EditEntryView.fetchPendingBlobs()` (~line 249) is the existing lazy-download pass and the model
  for how failure is treated: it fails silently and nothing blocks.

## Read before writing, in this order

1. **`CLAUDE.md`** - the hard rules. **Rule 1** (local-first: no screen is ever sync-gated),
   **rule 7** (every error names its next step), **rule 10** (String Catalogs, EN + RU),
   **rule 12** (never log domain values - an attachment's bytes, its sha256 content and any station
   or amount visible in it are domain values; ids and counts are fine) and **rule 14** all bind.
2. `docs/ERRORS.md` -> the **`### Edit entry`** table. Your new states are rows in it, in the same
   Condition / Shows / Next step shape as the ones already there.
3. `docs/SCREENMAP.md` -> the navigation graph and the **back-path conventions**. A full-screen
   viewer is a node; add it, including how it is dismissed.
4. `docs/SYNC.md` -> **Delivery** (lazy download, verify-on-download) and the blob pipeline.
5. `docs/DESIGN.md` -> palette tokens, and the **Motion** section (three orchestrated moments;
   nothing else animates beyond system defaults).

Extend those docs **in the same change**. A screen that appears in none of them is an unfinished
task, not a finished one.

## What to build

**The chip becomes a tap target**, and tapping it opens a full-screen viewer of that attachment.

The viewer must handle **four states**, and each one is the whole point of the task:

1. **The full rendition is on the device** (`BlobStore.data(for:)` returns it, or the attachment was
   captured on this device and never left). Show it full-screen, **zoomable and pannable**, fitted
   on entry. This is the "look deeper" the report asks for - a static full-screen image that cannot
   be magnified does not answer it.
2. **Not local, and a fetch is possible** (signed in). Show the thumbnail immediately - it is
   already in the payload, so something is on screen from the first frame - and fetch underneath.
   Replace with the full rendition when it verifies.
3. **Not local and no fetch is possible** (signed out, offline, or the fetch failed). Show the
   thumbnail, say plainly that the full photo has not downloaded yet, and **name the next step**
   (hard rule 7). The entry stays open and editable throughout - nothing here is ever a dead end,
   and nothing about this screen may gate the rest of the app (hard rule 1).
4. **The attachment is a PDF** (`attachment.kind == .pdf` - service invoices are stored as PDFs
   byte-identical). An image viewer handed PDF bytes shows nothing, which reads as a broken screen.
   Either render it (PDFKit is available; `PDFView` handles zoom and paging itself) **or** render an
   explicit, honest state saying it cannot be previewed and offering the next step. **Do not fail
   silently, and state in your report which of the two you chose and why.**

Dismissal follows `SCREENMAP.md`'s conventions - a swipe-down and a visible close control, not one
or the other; a viewer you can only leave by a gesture is a trap for the user who does not know it.

All strings EN + RU in `ios/App/Sources/Localizable.xcstrings` (hard rule 10). RU runs 20-30% longer
and short strings expand worst; **never compose a string by concatenation** - a full localised
phrase per language (the P1.4 bug: `"%@ spend"` + `"%@ расходы"` rendered "АВГУСТ РАСХОДЫ").

## Explicitly out of scope

- **No delete, rotate, crop, share, or save-to-Photos.** Viewing only. Each of those is its own
  decision with its own error rows.
- No change to how attachments are captured, written, synced or hashed.
- No re-OCR from the viewer.
- Do not touch `ios/App/Sources/Capture/CaptureReviewView.swift` (RV.5),
  `ios/App/Sources/ConfirmManual/ManualFillUpGatewayBanner.swift` or `GatewayScanSession.swift`
  (RV.8), or the `onSaved` plumbing added for RV.12 in `ManualFillUpView.swift`,
  `ScannedFillUpSheet.swift`, `Destinations.swift` and `CaptureView.swift`. You may READ all of them.

## What NOT to explore (closed questions)

- Whether blobs are content-addressed and verified on download - they are; `LazyBlobFetcher` does
  it. Do not re-derive the pipeline or add a second cache.
- Whether to encrypt anything here - no E2E in v1, signed off (`CLAUDE.md` decided list).
- The palette - all colours from `Theme.Palette` tokens, no ad-hoc hex (hard rule 5).

## Tests

- `cd ios && swift test` - **1154 unit tests today; the number must not fall.**
- L4 in `ios/App/UITests/`. The Edit-entry suites are the place; **name in your report which suites
  you ran and the observed count per suite**. `EditEntryTestSeed.swift` and
  `PhotoSyncingTestSeed.swift` already seed an entry with an attachment and the syncing state - use
  them rather than inventing a new seed, and pass `-homeResetDatabase` alongside any seed (the seeds
  are idempotent and silently do nothing on a populated database).
- The tests that pin this: the chip is **tappable** and opens the viewer; the viewer **dismisses
  back to the entry**; and the not-yet-downloaded state **names its next step** rather than showing
  an empty frame.

**Vacuous-assertion traps for this task, named. The last one is not hypothetical - it was found in
this repo two days ago:**
- Asserting the viewer's element `exists` after tapping. **XCUITest keeps a covered screen in the
  hierarchy**, so `exists` is true for things that are not visible, and two existing assertions in
  `CaptureUITests` are known-vacuous for exactly this reason. Assert **`isHittable`**, and assert the
  before-state too (not hittable before the tap, hittable after).
- Asserting the chip exists without asserting it is a **control the user can hit**. It existed
  before this task; that is the bug.
- A "zoom works" test that only checks the image view is present. If you cannot drive a pinch
  reliably, assert the zoom affordance's presence and say plainly in your report that the gesture
  itself is unverified - do not dress it up as a passing zoom test.
- Testing only the happy path. The offline / not-downloaded state is the one with a next step to
  name, and it is the one hard rule 7 is about.

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    swiftlint lint ; echo "LINT=$?"
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "APPBUILD=$?"

**Judge by the exit code you echoed, not by skimming output** - a `0` printed after a pipe is the
pipe's exit code, not the tool's. Run swiftlint from the repo root (its `excluded:` paths are
root-relative). Zero lint **errors** is the standard; `file_length` at 700 lines is an **error**, and
`EditEntryView.swift` is already large - if a file you touch approaches 700, split it at a real seam
rather than loosening a rule.

If you check whether the simulator is free, match the process NAME (`pgrep -x xcodebuild`).
**Never `pgrep -f` or `pkill -f`** on a build/test pattern: an agent's brief is part of its command
line, and on 2026-08-24 exactly that killed another agent 48 minutes into its task.

**If a UI run fails with "Failed to load the test bundle ... executable couldn't be located", that
is contention, not a red** - zero tests executed. Re-run it once before reporting a failure.

## Screenshots

`design/screenshots/RV.9-attachment-viewer.png` and `-ru.png`, **dark** theme, captured from a
booted simulator **outside any test run** (`simctl` and `xcodebuild test` fight over the device). RU:

    xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU

If the not-downloaded state is visually distinct, shoot it too - it is the state with the copy that
can overflow, and RU is where it overflows.

**Install the app you just built.** There are many `DerivedData/Tankbook-*` directories; take the
newest (`ls -dt ...`), or you will screenshot a stale build and believe the feature is missing.
Say in your report how you verified what is in the image; the orchestrator opens both personally.

## Report back

- The exit codes you observed for `swift build`, `swiftlint`, the app build, `swift test` and each
  UI suite - the numbers, not a summary.
- The unit-test count before and after; the UI test names and the observed count per suite. A
  `-only-testing:` that matches nothing prints "0 tests ... passed", which is not a pass.
- **Whether each test was actually RUN, not only written**, and whether you saw the new tests FAIL
  before the fix (revert it, watch them go red, restore).
- Which of the two PDF options you chose, and why.
- Every file you created or modified, and the doc sections you extended.
- Anything you could not finish, named plainly. An honest gap is worth more than a green report that
  does not hold.
