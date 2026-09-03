# RV.37 – an attached receipt must be deletable and replaceable

Required by the product owner: a receipt attached to an entry must be **downloadable, deletable and
replaceable**, and on replace the app must **ask** whether to re-read it and update the entry.

**Download is already done** — RV.17 landed it today (Share, gated on the full rendition being
local). **This task is delete and replace.**

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`. **Do not run `git add` or `git commit`.**
**Do not touch `docs/TASKS.md`.**

## What exists (build on it, do not restructure it)

`ios/App/Sources/EditEntry/`:

- `AttachmentViewerView.swift` — RV.9 + RV.17. Four states, a pager whose second page shows the
  recognised data, `Share` and `Close` in the header, `presentShare()`, `load(force:)`.
  **This file landed hours ago — read it first and add to it.**
- `AttachmentRecognisedView.swift`, `AttachmentRenditionViews.swift`, `ReceiptCardView.swift`.
- `ios/App/Sources/ConfirmManual/ReceiptAttachSupport.swift` — the existing camera/Photos source
  chooser (`receiptAttachSource`), already used by ConfirmManual and Edit entry. **Replace should
  reuse this door, not build a second one** (hard rule 15: the two doors are peers).
- `AppLog.info(operation:category:outcome:)` — stable codes only, so a call site cannot log a domain
  value. Use it; do not add a logging path that takes free text.

## THE GAP YOU WILL HIT FIRST

`Repository` has `softDeleteVehicle`, `softDeleteFillUp`, `softDeleteChargeSession`,
`softDeleteServiceRecord`, `softDeleteExpense`, `softDeleteReminder` — and **no
`softDeleteAttachment`**. Deleting a receipt is not a solved problem you can call into; it needs the
tombstone path adding, consistently with the others.

And an entry references its attachments by id: `var attachments: [AttachmentID]`. So a delete is
**two writes that must agree** — tombstone the attachment record *and* unlink the id from the entry.
Decide the order and make it atomic within the existing write transaction; a half-applied delete
leaves an entry pointing at a tombstone, which the viewer would then fail to open.

## What to build

### Delete

- Hard rule 8: **nothing lost silently.** The attachment is a synced record with a **tombstone and
  the 30-day undo**, exactly like any other entity — not a file quietly unlinked. If Recently deleted
  should list it, say so and wire it; if you judge it should not, say why.
- **Do not delete a blob another entry still references.** Blobs are content-addressed and
  deduplicated — `blob.begin` logs `Dedupe=hit`, so sharing is real, not theoretical. The safe rule
  is that the tombstone removes the *reference*; blob reclamation is a separate concern and is **out
  of scope** for this task. Say in your report what you left the blob doing.
- Confirm before deleting (it is destructive and `docs/ERRORS.md` says red lives only in system
  dialogs).

### Replace

- Reuse `receiptAttachSource` for the camera/Photos choice.
- **Replace is a new attachment plus a tombstone for the old one, never an in-place mutation** — or
  the 30-day undo has nothing to restore.
- **Then ask: "re-read this and update the entry?"** This ask is the whole feature.
  - **"Leave it as it is" is the DEFAULT.** A silent re-read would overwrite values the user has
    already confirmed, which hard rule 13 forbids outright: *"once a user changes one, that value is
    theirs permanently"*.
  - If the user accepts, the extracted values are still **suggestions filling blanks only** — the
    same boundary the Confirm sheet enforces (`GatewaySuggestionPolicy`, `ReceiptAttachMerge`).
    **Never a blind overwrite**, even on an explicit yes.
- The third option the product owner named — *"replace with another receipt"* — is just replace
  again; do not build a separate flow for it.

## Explicitly out of scope

- Blob reclamation / garbage collection (named above).
- Re-running extraction anywhere except the explicit accept path.
- The capture flow, `CapturePipeline`, the Confirm sheet.
- Any backend file. **Another agent is working in `backend/` — touch nothing there.**

## Read before writing

1. **`CLAUDE.md`** — hard rules 8 (nothing lost silently), 13 (the app suggests, the user decides),
   15 (peer doors), 7 (every error names its next step), 10, 12, 14.
2. `docs/SYNC.md` — tombstones and the 30-day window; attachment records sync like any other.
3. `docs/ERRORS.md` → **Edit entry**, including the rows RV.9 and RV.17 added. Your new states
   (delete confirm, replace ask, a failed replace) are rows there.
4. `docs/JOURNEYS.md` → **J8b**, which RV.17 extended; replace and delete belong in that journey.
5. `docs/SCREENMAP.md` → the viewer node.

## Tests

- `cd ios && swift test` — **1165 today; must not fall.**
- `AttachmentViewerUITests` exists (RV.9 + RV.17) — extend it; name the suites you ran and the counts.
- The checks that matter:
  - delete removes the receipt from the entry **and it is recoverable** for 30 days;
  - replace swaps the photo **and the ask appears**;
  - **declining leaves every field byte-identical** — assert the VALUES, not that a dialog showed. A
    dialog that overwrites anyway passes the weaker assertion, and that is the failure this task is
    most likely to ship;
  - accepting fills only fields that were blank, and leaves a user-typed value untouched.

**Vacuous-assertion traps, named:**
- `.exists` on the delete or replace control. Assert **hittable** — XCUITest keeps covered elements
  in the hierarchy.
- Asserting the attachment count dropped without asserting it can be restored. That tests deletion,
  not the undo rule 8 requires.
- Testing accept without a pre-filled field. If every field is blank, "fills blanks only" and "blind
  overwrite" are indistinguishable.

**Mutation-check** the decline path and report it: make accept the default, and confirm the
byte-identical test goes red.

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    swiftlint lint ; echo "LINT=$?"          # from the repo ROOT
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "APPBUILD=$?"

**Judge by the exit code you echoed.** Zero lint **errors**; `file_length` at 700 is an error and
`AttachmentViewerView.swift` has grown — split at a real seam rather than loosening the rule.

Match the process NAME (`pgrep -x xcodebuild`). **Never `pgrep -f` or `pkill -f`** on a build/test
pattern — an agent's brief is part of its command line.

"Failed to load the test bundle … executable couldn't be located" is contention, not a red — re-run once.

## Screenshots

`design/screenshots/RV.37-replace-ask.png` and `-ru.png`, dark, outside any test run — the **ask** is
the shot that matters, and RU is where its three options overflow. Install the newest
`DerivedData/Tankbook-*` build (`ls -dt`), or you will shoot a stale one.

## Report back

- Exit codes for build, swiftlint, app build, `swift test`, each UI suite — numbers, not prose.
- Test counts before/after; suites RUN; the mutation result for the decline path.
- **What you left the blob doing on delete**, and whether Recently deleted lists the attachment.
- The final EN and RU copy for the ask, verbatim.
- Files changed, doc sections extended, anything unfinished — named plainly.
