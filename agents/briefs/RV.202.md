# RV.202 - a service or expense can be given a receipt, not only shown one

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** **Agents never tick `docs/TASKS.md` and
never commit.**

**Scenario: J7 (the invoice in your hand), J7b (the shop receipt), J8b ("look at the receipt
again").** A change to what the user is promised edits `docs/JOURNEYS.md` **in the same change**
(`CLAUDE.md`, 2026-09-10).

## The defect, pinned - and it is narrower than it sounds

Product owner, 2026-09-10: *"entries service / expenses must allow to attach, view, replace the
attachments to it. The same flow as for fill ups."*

`EditEntryNonFillView.swift:36-39` renders the shared `EditEntryRows.receiptCard` **only when
`!attachments.isEmpty`**, and never passes `onAddReceipt`. So:

- **View works** and **replace/delete work** - they live in `AttachmentViewerView` ([RV.37]) behind
  that same shared card.
- **An entry that arrived without a photo has no card and no "Add receipt" button at all.**

The fill-up screen has the three-way branch this one lacks (`EditEntryView.swift:448-466`): existing
attachments -> card; a pending image -> `pendingReceiptCard`; none -> the card **with**
`onAddReceipt` and `.receiptAttachSource`. **The affordance is missing, not the machinery** -
`receiptCard` already takes `onAddReceipt` as a parameter (`EditEntryRows.swift:14-20`).

## What to build

Give the non-fill screen the same three-way branch, calling the **same** `receiptCard` and the
**same** `.receiptAttachSource` chooser. **Reuse `attachReceipt`'s path rather than writing a
second one**: it persists the photo, it reports a failed write, and it is where the blank-fields-only
merge hangs.

Note `RV.11`'s fence, which the fill-up screen already obeys: **the chooser hangs off the CARD, not
the screen.** iOS 26 anchors a `confirmationDialog` popover to the view it is attached to, and a
screen-level attachment pointed its arrow at the middle of the form.

## The seam that will fight you, and the decision you must state

`EditEntryNonFillView` takes `onAttachmentChanged: (FuelExtraction?) -> Void`. **A service invoice's
recognition is not a `FuelExtraction`.** That fuel-shaped seam is the subject of [RV.201] and is not
yours to solve - but you must **choose and say which**:

- pass `nil` and let the entry keep the photo without any value merge, leaving the widening to
  RV.201; **or**
- widen the callback here if it is genuinely a one-line change.

**Either is acceptable. Choosing silently is not.** Say what you did and why in your report.

## This brief's reading is a hypothesis - confirm it before you change anything

Four of the orchestrator's diagnoses were wrong in one session and an agent caught every one - two of
them in this very file this week. **Read `EditEntryView`'s branch and `attachReceipt` first**, and in
particular find out what happens today when a service HAS an attachment: does the viewer's Replace
actually work from a non-fill entry, or does it only look like it does? The orchestrator asserted it
does, from the fact that the card is shared. **Verify it rather than inheriting the claim.**

## Explicitly out of scope

- `RV.201` (late-arriving recognition, generalising the Inbox merge over entry kind).
- `RV.200` (inferring the expense category from a scan).
- `RV.199` (the header total against the line sum) - **it is in flight right now on this same
  screen.** Expect `EditEntryNonFillView` and the money card to have changed under you; **re-read
  before editing, and do not revert its work.**
- The capture-mode scan paths. This row is the EDIT screen.

## Docs to read before writing (in order)

1. `ios/App/Sources/EditEntry/EditEntryView.swift:440-470` - the branch to mirror, and `RV.11`'s
   comment about where the chooser hangs.
2. `docs/JOURNEYS.md` -> **J8b** (*"look at the receipt again"*) and **J7**. **Amend them**: what the
   user is promised about a service's receipt is changing.
3. `docs/ERRORS.md` -> the attach-failure row ([RV.149]'s message).
4. `CLAUDE.md` hard rules 7 and 8.

## Environment axes this crosses

**Locale**: a new button and possibly new copy, so **EN and RU screenshots**, dark theme, capture
lines added ([RV.176] fails CI on a frame no line produces). Reuse or extend the
`RV.198-service-items` pose. **Offline** is worth one sentence: attaching is local, and nothing here
may require the network (hard rule 1).

## If this adds a failure path, what makes it visible in production?

**It adds the one `RV.149` was filed for.** A photo write can fail, and on the fill-up path that is
already reported rather than swallowed. **Your path must report it too** - reuse
`reportLostReceiptPhoto`, do not write a second message, and make sure the report fires **after the
entry is on disk** so a failed save can never claim success.

## Tests you must add

- **L1, and it FAILS TODAY**: attaching to a service persists the photo, and the entry still carries
  it after a reload. Oracle: the stored `Attachment` id on the reloaded record.
- **L1**: a failed photo write is **REPORTED, not swallowed** ([RV.149]'s rule, one entry kind over -
  the fill-up path has this test and the non-fill path has none).
- **L1**: the same for an Expense, not only a Service - they share the screen and must share the
  behaviour.
- **L4 `EditEntryUITests`, EN and RU**: a service with no attachment offers "Add receipt", takes one,
  and the viewer opens it. Filter **by suite name** and check the count - `PJ.23`'s and `RV.198`'s
  tests are extensions of that suite, so a file-name filter matches zero and prints `TEST SUCCEEDED`.

Every expectation names its ORACLE. Report each suite's observed, **non-zero** count.

## The mutation you must run - I am naming it, do not choose your own

**Drop the `onAddReceipt` argument at your new call site** - restoring today's state exactly - and
show the attach L1 goes red. Then restore byte-identical and re-run. Report both outputs verbatim.

## Vacuous traps, named

- **Asserting the button exists** rather than that the attachment persisted. This project has two
  monuments to that mistake (`PJ.55`, `RV.170`).
- A second attach path beside `attachReceipt`.
- **Shipping attach without the failure report** - that is exactly the half `RV.149` had to be filed
  for after `PJ.28`'s fence stopped one entry kind short.
- Hanging the chooser off the screen instead of the card (`RV.11`).
- Testing Service and forgetting Expense.

## Never stash, move or `git checkout` to get a "clean baseline"

An agent's `git stash` + `mv` loop destroyed three of its own new files on 2026-09-08.

## Never `pgrep -f` for a build process

Your brief is in your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**. Use
`pgrep -x xcodebuild`. **Never `pkill -f`.**

## `simctl launch` on a running app ignores new arguments - `terminate` first

**You cannot see your own screenshots**: state what you captured, never that it looks right. **Never
pass `SKIP_BUILD=1` after changing the source.**

## Concurrent work in this checkout

Another `opencode` run has been growing the receipts corpus since 2026-09-10 19:57 and holds
uncommitted changes in `Spike/ReceiptSpike/fixtures/`,
`ios/Sources/TankbookCore/Config/PumpPhotoGate.swift` and `ios/Tests/TankbookCoreTests/Corpus*`.
**Do not touch, revert or `git checkout` any of them.** Also pre-existing and **not yours**: four
`ReminderNotificationActionTests` failures (the simulator's notification daemon drops `add` from a
test-hosted process), and `SyncWriteTriggerTests`, which fails **under machine load** and passes
alone - re-run it alone before reporting it.

## Standing checks

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0 (from `ios/` it exits 2 with ~5000 phantom errors).
3. `cd ios && swift test` - full; report the count. **Run it alone.**
4. **`xcodebuild ... build` for the app target** ([RV.174]).
5. `xcodegen generate`, then `EditEntryUITests` **by suite name**, non-zero count.
6. Localization gate - exit 0; report keys and RU percentage.
7. `bash scripts/check-screenshot-manifest.sh` - exit 0, after adding your capture lines.

Verify by **exit code** (`echo $?`).

## Report back

**Whether Replace actually works from a non-fill entry today** - verify, do not inherit the claim;
what you did about the `FuelExtraction?` callback and why; every check with its **exit code
observed** and counts; **the mutation's red-then-green output verbatim**; what you captured in both
locales; how you amended `JOURNEYS.md`; and **anything you found and did not fix**.
