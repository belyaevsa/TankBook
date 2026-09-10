# RV.200 - an Expense scan reads the money and never the KIND

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** **Agents never tick `docs/TASKS.md` and
never commit.**

**Scenario: J7b · Parts, tires, consumables** - *"a shop receipt is an expense"*. A change to what
the user is promised edits `docs/JOURNEYS.md` **in the same change** (`CLAUDE.md`, 2026-09-10).

## The defect

Product owner, 2026-09-10, asking whether the capture chips recognise anything: **they do.**
`CaptureView.acceptExpenseScan` runs the **same `CapturePipeline` as a fuel receipt**, and
`ExpensePrefillBuilder` carries total, currency and date into `ExpenseEntry` while deliberately
dropping the fuel-only fields.

**The category is never inferred.** `ExpenseEntrySession.pendingPreset` exists, and its own doc
comment says *"`pendingPrefill` only by Capture; `pendingPreset` only by ServiceEntry; they never
race"* - so a scanned expense **always opens at the `.accessory` default**. A parking receipt, a
toll, a car wash and an insurance invoice are indistinguishable to the form that receives them.

**[RV.195] made this sharper hours ago**: the category is now a visible, editable field on the edit
screen, so the wrong default is something the user must correct on every single scan.

## What to build

Infer the category from what the scan read, and **offer it as a suggestion** (hard rule 13):
pre-selected, editable at the moment it is offered and afterwards, and **never presented as a fact**.

**Reuse `pendingPreset`** rather than adding a second channel - and **update its doc comment**, which
currently states as an invariant the thing you are changing. A comment that documents the old
behaviour beside the new one is the defect shape `docs/DEFECT-PATTERNS.md` catalogues.

**An unrecognised kind opens at the default and says nothing.** No guess presented as a fact, no
error, no empty state (hard rule 7).

## The real work is the vocabulary, and it is bilingual

The separable kinds are `parking`, `toll`, `fine`, `insurance`, `tax`, `accessory`, `parts`, and
`.other("wash")` - see `ExpenseCategory.entryCases`. **The words that identify them differ per
locale and the RU set is the one that matters here** (the product owner's own receipts are Russian).
Put the vocabulary where the other extraction vocabularies live and say where that is.

## The ORACLE, and the trap it exists to avoid

**Ground truth comes from the fixture FILENAMES**, which the product owner wrote from the images
before any extractor existed, cross-checked against the OCR dump - which is the extractor's INPUT.

**Never score against the extractor's own output.** `RV.161` added a corpus column, scored **46 of
46**, and it was a tautology: the ground truth had been written from the thing under test, and
because the scorer skips an empty cell rather than counting it a miss, every failure was silently
blank. **A 100% score on a new class is evidence of circularity, not quality.**

## This brief's reading is a hypothesis - confirm it before you change anything

Read `acceptExpenseScan`, `ExpensePrefillBuilder` and `ExpenseEntrySession` first. Then: **how many
of the corpus receipts are actually non-fuel?** If the corpus has three parking receipts and nothing
else, say so - **the measurement is the row's cheapest half and its result may be that the
vocabulary cannot be built yet.** That is a legitimate finding, and far better than a keyword list
tuned to two images.

## Explicitly out of scope

- `RV.201` (late-arriving recognition). **This row decides what an expense recognition PRODUCES**,
  which is why it is sequenced first.
- `RV.202` (attaching to an existing entry).
- The Service-mode invoice path (`ServiceInvoiceScanner` + `InvoiceSplitter`) - it already splits
  items with categories.
- Changing what `ExpensePrefillBuilder` carries beyond the category.

## Docs to read before writing (in order)

1. `docs/EXTRACTION.md` - the pipeline, the named failure modes and **where a vocabulary belongs**.
   **Extend it with this one in the same change.**
2. `docs/SCHEMA.md` -> **Expense**, `ExpenseCategory` and its `.other(String)` escape hatch.
3. `docs/JOURNEYS.md` -> **J7b**. **Amend it**: what a scan is promised to read is changing.
4. `Spike/ReceiptSpike/fixtures/README.md` - the accuracy-gate workflow and the oracle rules.
5. `CLAUDE.md` hard rules 12 and 13, and the note about a 100% score.

## Environment axes this crosses

**Locale is the row's own subject** - the vocabulary is per-language, and a keyword list that works
only in EN is half a feature. **Screenshots EN and RU** of an Expense-mode scan landing with a
category preselected, with capture lines added ([RV.176]). **Offline**: recognition is local here;
nothing may require the network (hard rule 1).

## If this adds a failure path, what makes it visible in production?

A category guessed wrong is worse than none guessed. Add the shape-only event that answers *"did the
scan infer a category, and did the user change it?"* - **the category CODE and a boolean, never the
receipt's text** (hard rule 12). That is the same `userCorrected` signal `capture.pipeline` already
records for fuel, and it is what would let a future run measure whether this helps at all.

## Tests you must add

- **L1, and it FAILS TODAY**: a fixture parking receipt yields `.parking`. Oracle: **the fixture
  filename**, and cite it.
- **L1**: a wash yields `.other("wash")` - the escape hatch, not a forced standard case.
- **L1**: an unreadable or ambiguous receipt yields **nil**, and the form opens at its default. A
  vocabulary that always answers is a vocabulary that guesses.
- **L1, RU**: at least one Russian fixture, because the vocabulary is bilingual and the owner's
  receipts are Russian.
- **L4 `CaptureUITests`**: an Expense-mode scan opens the expense form with the inferred category
  **preselected and editable** (hard rule 13).

Every expectation names its ORACLE. Report each suite's observed, **non-zero** count.

## The mutation you must run - I am naming it, do not choose your own

**Make the inference always return nil** and show the parking-receipt L1 goes red. Then restore
byte-identical and re-run. Report both outputs verbatim.

## Vacuous traps, named

- **Scoring against the extractor's own output** - `RV.161`'s 46/46.
- A vocabulary tuned until the two fixtures you have both pass. Say how many you measured.
- Returning a category for everything, so `nil` never happens and the default is unreachable.
- Writing `pendingPreset` and leaving its doc comment asserting the old invariant.
- Presenting the guess as a fact - no "Category: Parking" that cannot be changed before saving.

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
uncommitted changes in `Spike/ReceiptSpike/fixtures/` - **which is where your fixtures live.**
**Do not touch, revert or `git checkout` any of its files**, and if a corpus test fails, say so and
say it is not yours. Also pre-existing and **not yours**: four `ReminderNotificationActionTests`
failures, and `SyncWriteTriggerTests` under machine load.

## Standing checks

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0.
3. `cd ios && swift test` - full; report the count. **Run it alone.**
4. **`xcodebuild ... build` for the app target** ([RV.174]).
5. `xcodegen generate`, then each UI suite touched **by suite name**, non-zero count.
6. Localization gate - exit 0; report keys and RU percentage.
7. `bash scripts/check-screenshot-manifest.sh` - exit 0.

Verify by **exit code** (`echo $?`).

## Report back

**How many non-fuel receipts the corpus actually holds**, and whether the vocabulary is measurable
at all; the oracle you used for each expectation; every check with its **exit code observed** and
counts; **the mutation's red-then-green output verbatim**; what you captured in both locales; how you
amended `EXTRACTION.md` and `JOURNEYS.md`; and **anything you found and did not fix**.
