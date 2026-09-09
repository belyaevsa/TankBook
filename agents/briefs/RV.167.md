# RV.167 - nothing stops a seventh surface from summing money its own way

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create** - assume you are not alone in this
checkout. If a file is in your way or a test is red that is not yours, report it and carry on.

## The defect

The zero-summing defect has been fixed on **six** surfaces, one row at a time: [RV.106], [RV.112],
[RV.145], [RV.147] and - two commits ago, `378ee65` - [RV.166]. A seventh is filed and deferred
([RV.148]). Each fix routed one more caller through `LogStream.MonthTotal.Accumulator`, which is the
one place that decides what a rate-pending row contributes to a figure.

**What is missing is anything that makes bypassing that accumulator fail.** [RV.147]'s brief said
*"do not write a fourth summation"* as prose, and prose does not fail a build. Twice a doc comment
directly above the defect asserted the bug was not there ([RV.166]'s *"never a rate-pending line
summed as zero"* sat one line above `?? Decimal.zero`).

**Cause pinned:** there is no test in `ios/Tests` that reads source and asserts anything about money
aggregation. `grep -rn "Accumulator" ios/Tests` finds only behavioural tests of the accumulator
itself.

## This brief's reading is a hypothesis - confirm it before you change anything

The inventory below was taken on the tree as left, **after `RV.166` landed**. Re-run it. If a site
has moved or a verdict looks wrong to you, **say so** - the row is about encoding the distinction,
so a correction here is worth more than the test.

## Sibling inventory - I ran this, do not repeat the grep

Every `Decimal.zero`-seeded accumulation in `ios/Sources/TankbookCore` and `ios/App/Sources`:

| Site | Class | Must the guard fail on it? |
|---|---|---|
| `Service/MonthlySummaryNotification.swift:178` | **TRUE instance.** Reduces entries into a month spend figure; a rate-pending member contributes zero and the result is presented as the month's total | **YES - this is your failing case** |
| `Import/ImportConversion.swift:483` | **Look-alike.** Sums `fill.money?.amount` - the ORIGINAL amount, which is always known when `money` exists; there is no `homeAmount` and no rate to be pending on. It *does* skip a moneyless fill silently, which is a different and weaker concern | **NO** |
| `Service/ServiceEntryDraft.swift:93-94`, `ServiceEntry/ServiceEntryFormState.swift:95` | **Look-alike.** `cost?.amount ?? .zero` on a **draft form**: a cost the user has not typed yet is genuinely zero-so-far, not an unknown rate | **NO** |
| `Extraction/InvoiceSplitter.swift:113`, `Extraction/MixedReceipt.swift:93,288`, `ConfirmManual/MixedReceiptSection.swift:23` | **Look-alike.** OCR line amounts during extraction - plain `Decimal`s off a receipt, not `Money` pairs with a home currency | **NO** |

**That distinction is the whole row.** A guard that fails on the four look-alike classes is worse
than no guard: it will be silenced by an allowlist entry per site, and an allowlist without reasons
degrades into a skip list. The discriminator is not the word `reduce` - it is **whether the value
being accumulated is a `Money`'s home-currency side, where absent means "the rate is not known yet"**.

## The trap this row is most likely to fall into, named

**`RV.166` already fixed `LogStream.swift:369`, so your guard has exactly ONE known failing case
left.** A pattern tuned until it fails on `MonthlySummaryNotification.swift:178` and nothing else is
a pattern that matches that one line, not the shape. **A guard that passes on its first run means it
is too narrow.** Prove it is not by both of:

- **The negative case must be constructed, not hoped for.** Add a fixture source file (a string in
  the test, or a real file under a test-only directory) carrying a *new* `reduce`-over-`homeAmount`
  and assert the scanner flags it. The scanner must therefore be a **function over source text you
  can call on arbitrary input**, not a monolithic test that only ever walks the real tree.
- **The four look-alike classes above must be asserted as NOT flagged**, by the same function, with
  their real code as the input. If any of them only passes because it is allowlisted by path, you
  have written a skip list.

## What to build

A source-scan architecture test in `ios/Tests/TankbookCoreTests`, following the idiom this repo
already has - `SyncTriggerSourceGuardTests` (RV.157) reads a doc and the sources and asserts a
property; `PaletteAccentGuardTests` and `AccessibilityGuardTests` are the same shape. **Reuse how
those locate the source root**; do not invent a third way.

It must:

1. **Scan both `ios/Sources/TankbookCore` and `ios/App/Sources`.** Three of the six instances lived
   in the app target. A core-only scan is a vacuous pass.
2. **Fail with `file:line`** and a message naming `LogStream.MonthTotal.Accumulator` as the thing to
   use - an architecture test whose message does not say what to do instead gets suppressed.
3. **Treat the accumulator's own file as the allowlist.** Any other allowlisted site is a
   **deliberate, commented exception carrying its reason in the test's own table**; a bare path
   entry must fail the test's own self-check.
4. **Not fix `MonthlySummaryNotification.swift:178`.** It is [RV.148], **deferred by the product
   owner** ("we will come to it later"). The guard must **fail on it**, and you make the suite green
   by adding it as an allowlisted exception whose reason says *deferred, [RV.148], not a licence*.
   That is the honest state: the guard has teeth and the row is parked. **Say in your report that
   you did this** - if you think a deferred row should instead be fixed, report it, do not fix it.

## Generalise the idea, not the regex

The row asks for this explicitly: the same source-scan shape guards other invariants this project
keeps re-breaking - a second re-homing rule, a second station-minting path, a second
receipt-persistence path. **Do not build them.** Name in your report which are worth a row and why,
with the grep that would find each. They are filed separately.

## Explicitly out of scope

- **[RV.148]** - the monthly-summary push. Deferred; allowlist it, do not fix it.
- The four look-alike classes above - do not "tidy" them.
- [RV.162] (screen reachability) and [RV.163] (who-creates-this-entity) - the neighbouring guards,
  their own rows.

## Docs to read before writing (in order)

1. `docs/DEFECT-PATTERNS.md` - the sibling-defect and silently-reachable-fallback shapes; this row
   is the mechanised answer to the first one.
2. `docs/TESTING.md` -> which gates for which change, and where an architecture test sits.
3. `CLAUDE.md` hard rules 2 and 3, and "Code comments: current truth only".

Extend `docs/TESTING.md` in the same change to name this guard and what it catches - a guard nobody
knows exists gets deleted by the next person who sees it fail.

## Environment axes this crosses

**None at runtime** - this is a test-only change; no shipping code path is different. No Release
seam, no locale, no offline, no signed-out state. **No screenshots** (nothing renders). **No new log
line** (hard rule 12; nothing runs in production). Say if you disagree with any of these.

## Tests you must add

- **L1, and it FAILS TODAY**: the scanner flags `MonthlySummaryNotification.swift:178`. **Oracle**:
  that line reduces `Expense`/`FillUp` money into a month figure where a member with no
  `homeAmount` contributes `Decimal.zero` - the same mechanism `RV.112` removed from
  `HomeStats.monthSpend`, which is why `RV.148` was filed against it.
- **L1**: the scanner does **not** flag the four look-alike classes, called on their real source.
  **Oracle**: each accumulates a plain `Decimal` or a draft's untyped cost - there is no
  home-currency side that can be unknown, so a missing value is genuinely zero.
- **L1**: a **newly written** `reduce`-over-`homeAmount`, supplied as source text to the scanner,
  is flagged. This is the case that proves the pattern is the shape and not the one known line.
- **L1**: an allowlist entry with no reason fails the guard's own self-check.

## The mutation you must run - I am naming it, do not choose your own

**Delete the allowlist entry for `MonthlySummaryNotification.swift`.** The guard must go **red**,
naming that file and line. Then restore it and re-run. Report both outputs verbatim.

A second, and it is the one that matters most here: **re-run your scanner with the
`MonthlySummaryNotification` line temporarily rewritten to route through the accumulator** (do not
leave that edit in place - revert it) and confirm the guard then passes for that file without the
allowlist. If it does not, your pattern is matching something other than the shape.

## Vacuous traps, named

- A regex so narrow it matches only `MonthlySummaryNotification.swift:178` - the row's headline trap.
- Scanning only `ios/Sources` and missing `ios/App/Sources`, where three of the six instances lived.
- An allowlist without reasons, which is a skip list.
- Asserting "the guard runs" rather than that it **fails on a known-bad input**.
- A test that walks the real tree only, so it can never be shown a new violation.
- Fixing [RV.148] to make the suite green.

## Never stash, move or `git checkout` to get a "clean baseline"

Write the test, run it against the unmodified tree, then make the change. **Do not** `git stash`,
`git checkout`, or move files out of the tree: an agent did that on 2026-09-08 and a bad `mv` loop
destroyed three of its own new files.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**.
Use `pgrep -x xcodebuild`. **Never `pkill -f`.**

## Standing checks

Re-measure the baseline yourself and report what you observe. As left, `main` is **1818 tests / 211
suites, all green**, **815** localization keys at 100% RU.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0. From the root, **not** `ios/`: the `excluded:`
   paths are root-relative and from `ios/` it exits 2 with thousands of phantom errors.
3. `cd ios && swift test` - full, never subsetted; report the count. It must be **greater** than
   1818.
4. No UI suite is expected. If you touch one, name it and report an observed, **non-zero** count -
   a filter matching nothing prints "0 tests … passed" and still exits 0.
5. Localization gate - exit 0; report keys and RU percentage.
6. No Release build needed (no `#if DEBUG` seam). Say if that changes.

Verify by **exit code** (`echo $?`), and report the codes you observed.

## Report back

Every check with the **exit code you observed** and the observed counts; whether each test was **run
or only written**; **the named mutation's red-then-green output, verbatim**; the second mutation's
result; whether you disagree with any verdict in the sibling inventory; which further source-scan
guards you think are worth filing, with the grep for each; and **anything you found and did not fix**.
