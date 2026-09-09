# RV.149 - a fill-up's receipt photo can fail to save and the user is never told

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create** - assume you are not alone in this
checkout. If a file is in your way or a test is red that is not yours, report it and carry on.

## The defect, pinned to a line

`ManualFillUpReceiptSave.swift:124-135` (`ConfirmManualSaveSupport.receiptAttachmentIDs`):

```swift
/// A write failure degrades to no photo, never blocks the entry (hard rule 1).
func receiptAttachmentIDs(scanned: ScannedSavePlan,
                          repository: TankbookRepository) -> [AttachmentID] {
    guard let attachmentID = scanned.attachmentID else { return [] }
    do {
        try writeReceiptAttachment(id: attachmentID, repository: repository,
                                   extraction: scanned.extraction)
        return [attachmentID]
    } catch {
        AppLog.error(operation: "confirmManual.receiptPhotoSave", category: .ui, error: error)
        return []          // ← logs, drops the photo, tells the user NOTHING
    }
}
```

The comment is **half right and that is what makes it dangerous**: the save correctly never blocks
(hard rule 1), and it silently loses the photo (hard rule 8 - *nothing lost silently*). The throw
comes from `writeReceiptAttachment` at `:155-157` (`ReceiptAttachmentError.notEncodable`) or from
`VehiclePhotoStore.save` (a storage failure).

**[PJ.28] fixed exactly this defect on the EXPENSE path** (`8005181`) because that was its fence,
and its agent reported this one on the way out. The expense path's answer is at
`ExpenseEntryView.swift:249-253`: a `photoWriteFailed` flag, and after the record is on disk,
`toastCenter.show(L10n.expenseReceiptNotSavedMessage)`.

**The single call site is `ManualFillUpView.swift:572`**, and that view already holds
`@Environment(AppToastCenter.self) private var toastCenter` (`:29`) and already calls
`toastCenter.noteEntryChanged()` at `:618`. So the reach exists - there is no plumbing excuse.

## This brief's reading is a hypothesis - confirm it before you change anything

Line numbers were read on the tree as left. **Confirm the fill-up scanned save actually reaches the
catch and says nothing** before you change it. If a toast already fires somewhere I did not look,
report that and stop.

## What to build

**Give the fill-up path the message the expense path already has** - the same string, not a second
one. `L10n.expenseReceiptNotSavedMessage` (`ios/App/Sources/Localization/L10n+PJ28.swift`) is one
full localised phrase per language, deliberately not composed. The situation is identical, so the
user must not meet two different sentences for it.

**The word "expense" is in the string, and that is your one real design decision.** Either:

- rename the symbol and generalise the sentence so both surfaces read naturally (*"…the entry was
  saved without it"*), updating the expense call site and `docs/ERRORS.md`'s PJ.28 row in the same
  change; or
- keep two sentences and **write down why** the user should meet different wording on two screens.

**Pick one and record the reasoning in the row and in `docs/ERRORS.md`.** Do not add a second
near-identical string without an argument - that is the trap this row names. A rename touches
localization keys: if you rename, the RU translation must move with it and the localization gate
must stay at 100%.

**The entry must still save and the save must never await the photo** (hard rule 1). That behaviour
is correct today; do not regress it while adding the message.

## The third surface - check it and report, do not necessarily build it

`docs/ERRORS.md:209` (Capture) carries a row that is **documented and unbuilt**:

> | Storage full (can't save photo) | Warn sheet: "No space to keep the photo. The entry can still be saved without it." | Save without photo · manage storage (deep link) |

That is a **third sentence for the same situation**, in a third register (a warn sheet, not a
toast), with a next step ("manage storage (deep link)") that may not exist. **Determine whether it
is the same failure**, and report:

- whether any code reaches that row today (a doc naming behaviour with no call site is a named
  defect shape - `docs/DEFECT-PATTERNS.md`);
- whether it should be reconciled with the toast, or is genuinely a different moment.

**Do not build the deep link** - if that next step does not exist, say so and it becomes its own row
(hard rule 7 is violated by a documented step that goes nowhere).

## Explicitly out of scope

- [PJ.28] itself - shipped; touch its call site only if you rename the string.
- The Edit-entry (`EditEntryView.swift:271`) and attachment-viewer (`AttachmentViewerActions.swift:114`)
  writers. **Check them and report** whether they swallow the same failure - if they do, that is a
  finding, and it is a row, not this row's work.
- The storage deep link.

## Docs to read before writing (in order)

1. `docs/ERRORS.md` -> **Service & expenses** (the PJ.28 row, line 288) and **Capture** (line 209).
   This doc is the authority for every user-facing message and its next step.
2. `CLAUDE.md` hard rules 7 (every error names its next step), 8 (nothing lost silently), 1 (the
   save is local-first and never blocks on anything), 10 (String Catalogs, EN + RU).
3. `docs/DEFECT-PATTERNS.md` -> the silently-reachable-fallback shape, which is what this is.

Extend `docs/ERRORS.md` in the same change so the fill-up row exists and says what it does.

## Environment axes this crosses

**Locale** - a new or renamed string needs its RU translation and the localization gate at 100%.
**Screenshots: EN and RU are required** if any user-visible copy changes, and it does. No Release
seam, no offline path, no signed-out state.

## If this adds a failure path, what makes it visible in production?

The `AppLog.error(operation: "confirmManual.receiptPhotoSave")` line **already exists** and is the
shape-only event that answers "did this happen?" - keep it, and keep it shape-only (hard rule 12: no
path, no image, no domain value). Say whether the expense path has an equivalent; if it does not,
report it rather than adding one here.

## Tests you must add

- **L1/L3, and it FAILS TODAY**: a photo-write failure on the **fill-up** path still writes the
  entry with **no attachment**, and the failure is **reported to the user**. **Oracle**: the expense
  path's shipped behaviour at `ExpenseEntryView.swift:249-253` - the entry lands, `attachments` is
  empty, and the toast carries the shared message. Asserting only that the entry saved is **today's
  behaviour and the whole defect**.
- **L4**: the failure surfaces its named next step on the fill-up path, EN and RU.
- **L1**: the copy is the **shared** string - assert the localization **key**, not the English text,
  so a second string cannot be introduced and still pass.

Every expectation names its oracle in a comment. Name the UI suite you extend, and report its
observed, **non-zero** test count.

## The mutation you must run - I am naming it, do not choose your own

**Delete the user-facing report you add** (the toast call, or the flag that drives it) while leaving
the entry-saves-anyway behaviour intact. The new test **must go red**. Then restore and re-run.
Report both outputs verbatim. This is the row's headline claim: the defect was never "the entry is
lost", it was "the user is not told", so the mutation has to remove the telling and nothing else.

## Vacuous traps, named

- **Asserting the entry saved without asserting the user was told** - that is today's behaviour and
  passes on the unfixed code.
- A second localized string for the same situation, with no argument for why.
- Blocking or delaying the save on the photo write (hard rule 1).
- Asserting the toast's English text instead of its key, which lets a duplicate string pass.
- Testing the expense path by accident - name the suite and check the count is non-zero.

## Never stash, move or `git checkout` to get a "clean baseline"

Write the test, run it against the unmodified code, then make the change. **Do not** `git stash`,
`git checkout`, or move files out of the tree: an agent did that on 2026-09-08 and a bad `mv` loop
destroyed three of its own new files.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**.
Use `pgrep -x xcodebuild`. **Never `pkill -f`.**

## `simctl launch` on a running app ignores new arguments - `terminate` first

An "RU" screenshot was once English with Russian dates. It passes an md5-difference check and is
still wrong. **You cannot see your own screenshots**: state what you captured, never that it looks
right.

## Standing checks

Re-measure the baseline yourself and report what you observe. As left, `main` is **1824 tests / 212
suites, all green**, **815** localization keys at 100% RU.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0. From the root, **not** `ios/`: the `excluded:`
   paths are root-relative and from `ios/` it exits 2 with ~5000 phantom errors.
3. `cd ios && swift test` - full, never subsetted; report the count.
4. `xcodegen generate`, then the UI suite you touched by name with an observed, **non-zero** count -
   a filter matching nothing prints "0 tests … passed" and still exits 0.
5. Localization gate - exit 0; report keys and RU percentage. A rename must not drop it below 100%.
6. Release build only if you touch a `#if DEBUG` seam. Say which applies.

Verify by **exit code** (`echo $?`), and report the codes you observed.

## Report back

Every check with the **exit code you observed** and the observed counts; whether each test was **run
or only written**; **the named mutation's red-then-green output, verbatim**; your decision on the
shared-vs-second string and why; your findings on the third surface (`ERRORS.md:209`) and on the
Edit-entry / attachment-viewer writers; and **anything you found and did not fix**.
