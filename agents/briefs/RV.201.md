# RV.201 - the late recognition that reaches a fill-up and nothing else

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** **Agents never tick `docs/TASKS.md` and
never commit.**

**Scenarios: J3 "the receipt catches up with you", J7 the invoice in your hand, J7b the shop
receipt.** A change to what the user is promised edits `docs/JOURNEYS.md` **in the same change**.

**This is the largest row in the service loop. Read the whole brief before writing a line.**

## The defect

Product owner, 2026-09-10: *"there should be async recognition of the captured documents, receipts
and a suggestion (as with FillUps) to update entries if recognized data arrived later and they are
different. **The flow must be the same**."*

**The flow exists, is shipped and is reachable - and every field in it is a fill-up field.**

- `GatewayInboxPolicy.offers(extraction:entry:)` takes `entry: FillUp`. So do `shouldOffer`, `item`
  and `merged` (`ios/Sources/TankbookCore/Inbox/GatewayInboxPolicy.swift`).
- `GatewayInboxItem.extraction` is a `GatewayExtraction` - the fuel reading.
- `InboxValueFormat.yours(_:entry: FillUp)` and `.receipt(...)` are fuel-typed, and their `label`
  switch **returns `""`** for any field outside the six.
- `AppInbox.resolve` ends in `repository.upsertFillUp(merged)` - one entity, hardcoded.
- `InboxView.tickID` falls to `"inboxTick_other"` for anything else, so two non-fuel fields would
  share one accessibility id and a UI test could not tell them apart.

And the producing side never defers for these kinds: `acceptExpenseScan` awaits its pipeline inline
(`CaptureExpenseScan.swift:32`), and `ServiceInvoiceScanner.process` awaits OCR plus
`InvoiceSplitter` before the form opens. **A service or expense recognition has nowhere to arrive
late to.**

## Two findings already on the table - confirm or refute both

1. **`FieldRef` already has `.vendor` and `.lineItem(Int)`** (`Domain/Enums.swift:226-227`), and
   `AttachmentRecognisedView.swift:214-216` **already renders labels for them**. So a non-fuel field
   vocabulary exists in exactly one place, on the ATTACH path, and the Inbox's own label table
   silently returns `""` for the same cases. **Do not write a third table.** Decide where the ONE
   label table lives and make both call it - this is `RV.169`'s complaint ("a second implementation
   beside the first") arriving as copy rather than logic.
2. **`RV.202` deliberately left you a seam.** Its `onAttachmentChanged: (FuelExtraction?)` callback
   is fuel-typed; the agent passed `nil` from the non-fill path and recorded that **this row owns
   the widening**. Go and look: widen it, or say why it stays and what fills the gap.

Neither is a conclusion. Four of the orchestrator's diagnoses were wrong in one session. **If the
tree disagrees with this brief, the tree is right - report it and proceed on what you found.**

## What to build

**One merge, generalised over entry KIND. Not a second Inbox.**

The shape is yours to choose and to justify; the constraints are not:

- **The blank-fields-only rule does not change.** A blank field may be filled; a DIFFERING value is
  **offered and never applied** (hard rule 13). That rule lives in `ReceiptAttachMerge` ([PJ.48]) and
  in `GatewayInboxPolicy`; it must still live in one place per concern after this row, not four.
- **The per-field tick survives.** The user decides field by field, and *"leave it as it is"* stays
  the default. An Inbox item with no way to decline is a defect.
- **Every offered field gets a distinct, stable accessibility id.** `"inboxTick_other"` for two
  different fields is a test that cannot fail.
- **A service's fields are its own**: vendor, its line items, its total. An expense's are its total
  and its **category** ([RV.200] decided what an expense recognition produces - read that row's
  outcome before choosing the expense field set).
- **`resolve` must write the right entity.** `upsertFillUp` is hardcoded today.

Then **make the recognition deferrable for those kinds**, so a slow or cloud-assisted read lands in
the Inbox instead of blocking the sheet. The delivery outbox already exists for exactly this
(`docs/API.md`, the RV.53 amendment) and `AppInbox.drainOutbox` already drains it **through the same
`GatewayInboxPolicy.item`** - one policy, two producers. Keep that property.

**If the generalisation is genuinely too large for one row, build the CORE half completely** - one
merge over entry kind, with its tests - **and file the deferral half as its own row with the seam
named.** A half-built generalisation with no row naming the rest is how this codebase produces
sibling defects (`docs/DEFECT-PATTERNS.md`). **Say explicitly which you did.**

## Explicitly out of scope

- `PJ.29` - invoice pages through `/extract`, the cloud half. Separate row.
- Improving recognition accuracy. This row moves a result, it does not read better.
- The backend. The outbox and the gateway exist; do not change the contract.

## Docs to read before writing (in order)

1. `ios/Sources/TankbookCore/Inbox/GatewayInboxPolicy.swift` - **in full**. It is the row.
2. `ios/App/Sources/Inbox/AppInbox.swift`, `InboxView.swift`, `InboxComparison.swift`.
3. `ios/Sources/TankbookCore/Extraction/ReceiptAttachMerge.swift` - [PJ.48]'s rule.
4. `docs/DEFECT-PATTERNS.md` - the sibling-defect shape. This row IS one, being closed.
5. `docs/JOURNEYS.md` -> **J3, J7, J7b**. Amend what each promises about a late reading.
6. `docs/ERRORS.md` -> the Inbox rows. A new offered field is a new user-facing surface.
7. `docs/API.md` -> the delivery outbox amendment, before touching the deferral half.

## Environment axes this crosses

**Locale**: new field labels mean **EN + RU screenshots**, dark theme, of the Inbox card showing a
SERVICE or EXPENSE offer. RU runs 20-30% longer and the comparison is a two-column "yours vs the
receipt" layout - **that is exactly where RU overflows.** Capture lines must be added ([RV.176] fails
CI on a frame no line produces).

## If this adds a failure path, what makes it visible in production?

A late recognition that cannot be matched to its entry, or an entry deleted before its answer
arrives, must not crash and must not silently vanish (hard rule 8). Name what happens and log it by
SHAPE only (hard rule 12 - never a vendor, never an amount).

## Tests you must add

- **L1**: a late service recognition whose values DIFFER produces an Inbox item, **not a write**.
- **L1**: one that only fills blanks applies under the existing rule.
- **L1, and this is the row's spine**: the merge is **ONE function over any entry kind** - assert it
  from a fill-up, a service **and** an expense in the same test file, so the three cannot drift.
- **L1**: declining leaves the entry **byte-identical**, including `updatedAt`.
- **L1**: every offered field has a **distinct** tick id - a test that fails if two collapse.
- **L1**: an answer for an entry that no longer exists is handled, not crashed.
- **L4 `InboxUITests`**: a service recognition arriving after the save is offered per field and is
  **declinable**, EN and RU.

Every expectation names its ORACLE. Report each suite's observed, **non-zero** count.

## The mutation you must run - I am naming it, do not choose your own

**Make the generalised merge apply a `.differs` field without a tick** (delete the tick guard for one
field) and show the "differing value is offered and never applied" L1 goes red **for the SERVICE
case**, not the fill-up one - the fill-up case passing proves nothing about this row. Restore
byte-identical and re-run. Report both outputs verbatim.

## Vacuous traps, named

- **A second merge implementation beside `ReceiptAttachMerge` or `GatewayInboxPolicy`.** This is the
  single thing this row exists to prevent.
- Asserting the Inbox card renders rather than that the entry did **not** change.
- Testing only the fill-up path and calling the generalisation proven.
- A third field-label table.
- Applying a differing value because it "looks better" - hard rule 13, and the whole row.
- An Inbox item the user cannot decline.

## Never stash, move or `git checkout` to get a "clean baseline"

An agent's `git stash` + `mv` loop destroyed three of its own new files on 2026-09-08. **`git log -S`
and `git show` are fine** - they write nothing.

## Never `pgrep -f` for a build process

Your brief is in your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**. Use
`pgrep -x xcodebuild`. **Never `pkill -f`.**

## `simctl launch` on a running app ignores new arguments - `terminate` first

**You cannot see your own screenshots**: state what you captured, never that it looks right. **Never
pass `SKIP_BUILD=1` after changing the source.**

## Concurrent work in this checkout

Another `opencode` run has been growing the receipts corpus since 2026-09-10 and holds uncommitted
changes under `Spike/ReceiptSpike/fixtures/`, `PumpPhotoGate.swift` and
`ios/Tests/TankbookCoreTests/Corpus*`. **Do not touch, revert or `git checkout` any of them.** Also
pre-existing and **not yours**: four `ReminderNotificationActionTests` failures, and
`SyncWriteTriggerTests` ([RV.203]) which fails under machine load and passes alone - six times now;
re-run it alone before reporting it.

## Standing checks

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0 (from `ios/` it exits 2 with ~5000 phantom errors).
3. `cd ios && swift test` - full; report the count. **Run it alone.**
4. **`xcodebuild ... build` for the app target** ([RV.174]).
5. `xcodegen generate`, then each UI suite touched **by suite name**, non-zero count.
6. Localization gate - exit 0; report keys and RU percentage.
7. `bash scripts/check-screenshot-manifest.sh` - exit 0.

Verify by **exit code** (`echo $?`).

## Report back

Whether you generalised fully or built the core half and deferred the rest - **say which, plainly**;
where the ONE field-label table now lives; what you did with `onAttachmentChanged`'s fuel type and
why; what `resolve` writes now; how a late answer for a deleted entry behaves; every check with its
**exit code observed** and counts; **the mutation's red-then-green output verbatim, on the SERVICE
case**; what you captured; and **anything you found and did not fix**.
