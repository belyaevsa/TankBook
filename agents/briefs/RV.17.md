# RV.17 – the attachment viewer should carry what was read, and let the photo out

Three additions on top of RV.9's `AttachmentViewerView`, requested by the product owner:
show the recognised data, make the receipt downloadable and shareable, and animate the download.

**RV.9 must be landed before this starts** - this brief edits the file it created.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`. **Do not run `git add` or `git commit`.**

## What exists (build on it, do not redesign it)

- `ios/App/Sources/EditEntry/AttachmentViewerView.swift` - four states (local, fetching,
  unavailable, PDF), `ZoomableImageView`, `AttachmentPDFView`.
- `ios/App/Sources/EditEntry/ReceiptCardView.swift` - the chip that opens it.
- `ios/App/Sources/Persistence/BlobService.swift` → `localData(for:)`, the synchronous network-free
  "is it here already" check; `LazyBlobFetcher.fetch(sha256:)` for the download (cache-first,
  verify-on-download, `BlobSyncError.hashMismatch` discards bad bytes).
- The recognised data is **already persisted** on `Attachment`: `ocrText` and `extractedTimestamp`.

## What to build

### (a) Show what was read

Present the recognised data **as an additional page in the viewer**, not as chrome over the photo -
the product owner's words: *"just as additional photo"*. When the attachment carries nothing
recognised, that surface is **absent**, not empty.

**Never re-run OCR from the viewer.** This is presentation of stored data. Re-recognising would also
break hard rule 13 - the user has already confirmed values, and a fresh read could contradict them.

### (b) Download and share

The receipt must be savable and shareable (`ShareLink` / `UIActivityViewController`). Two
consequences:

- The full rendition must be **fetched on demand** when it is not local, not merely displayed when
  it happens to be there. Sharing a thumbnail would be a bug that looks like a feature.
- **Offer share only once the full rendition is local.** A share sheet that hands over a 44 pt
  thumbnail is worse than no share sheet.

**Privacy, stated so it is not guessed at:** sharing exports a domain value **by the user's
deliberate act**, which is fine. **Nothing about the share may be logged beyond shape** - hard rule
12. Log that a share happened and its outcome; never what was shared, its hash, or its size in a way
that identifies the receipt.

### (c) Download progress

While the fetch runs in viewer mode, the wait must **look like work**. RV.8 is the precedent and its
reasoning applies unchanged: a motionless placeholder reads as a finished statement, and this fetch
can take seconds on a cellular link. Use the system `ProgressView`; degrade under Reduce Motion.


## Do not touch `docs/TASKS.md`

The orchestrator marks the row after verifying your work. Editing it from an agent is the conflict
class that forces iOS dispatch to be sequential: resolving a `TASKS.md` conflict by side silently
un-ticks a task (`HANDOVER.md`), and it cost a scattered commit on 2026-09-03. Report what you did;
the row is not yours to tick.

## Explicitly out of scope

- Delete, rotate, crop, or edit the image.
- Re-running extraction, or writing anything back to the entry.
- The capture flow, `CapturePipeline`, or the Confirm sheet.
- Any backend file - `/blobs` already serves what is needed.

## Read before writing

1. **`CLAUDE.md`** - hard rules 1 (nothing is sync-gated), 7 (every error names its next step),
   10 (EN + RU), 12 (never log domain values), 13, 14.
2. `docs/ERRORS.md` → **Edit entry**, including the four rows RV.9 added. Your new failure modes
   (fetch failed while sharing, share cancelled) are rows there.
3. `docs/SYNC.md` → **Delivery**, which RV.9 extended with the viewer as the second lazy-download
   trigger. On-demand fetch for share is a third; the doc moves in the same change.
4. `docs/SCREENMAP.md` → the viewer node RV.9 added.
5. `docs/DESIGN.md` → motion, and the accessibility floor.

## Tests

- `cd ios && swift test` - **1154 today; must not fall.**
- `AttachmentViewerUITests` exists (5 tests) - extend it. Name the suites you ran and the counts.
- The checks that matter:
  - with recognised data present, that surface is reachable; with none, it is **absent** rather than
    an empty page;
  - share is offered **only** when the full rendition is local;
  - the progress indication is on screen **for the whole fetch** - drive it with a slow seeded
    transport, the way `-seedGatewayBudget` does for RV.8, rather than hoping to catch a fast one.

**Vacuous-assertion traps, named:**
- Asserting the share button `exists`. Assert it is **hittable**, and assert it is absent in the
  not-local state - XCUITest keeps covered and disabled elements in the hierarchy.
- A progress test that passes because the fetch was instant. If you cannot slow the transport, say
  so plainly rather than shipping a test that proves nothing.
- Asserting `ocrText` is non-nil in the model instead of testing the screen.

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    swiftlint lint ; echo "LINT=$?"
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "APPBUILD=$?"

**Judge by the exit code you echoed.** swiftlint from the repo root; zero **errors**; `file_length`
at 700 is an error - if `AttachmentViewerView.swift` approaches it, split at a real seam.

Match the process NAME (`pgrep -x xcodebuild`); **never `pgrep -f` or `pkill -f`**.

"Failed to load the test bundle" is contention, not a red - re-run once.

## Screenshots

`design/screenshots/RV.17-recognised.png`, `RV.17-downloading.png`, and `-ru.png` for each - dark,
outside any test run. RU is where the recognised-data labels overflow.

Install the app you just built - newest `DerivedData/Tankbook-*` by `ls -dt`, or you will shoot a
stale build.

## Report back

- Exit codes, test counts, suites RUN, whether new tests failed before the change.
- How you drove the slow fetch for the progress test - or that you could not.
- What you log for the share, verbatim, so rule 12 can be checked.
- Files changed, doc sections extended, anything unfinished - named plainly.
