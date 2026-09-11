# PJ.63 - the field guard cannot see the entities the schema never documented

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** **Agents never tick `docs/TASKS.md` and
never commit.**

**Scenario: `no-scenario: guard completeness`** - this is infrastructure, and the rule
(`CLAUDE.md`, 2026-09-10) requires saying so rather than leaving it blank.

## The defect

`REVIEW-SERVICE`'s walk found it (`diagnostics/REVIEW-SERVICE-2026-09-10.md`):
**`TireSet` and `ServiceItem` have no `###` section in `docs/SCHEMA.md`.**

Both [RV.163]'s entity guard and [RV.196]'s field guard **read the schema to know what to check**, so
an entity the schema does not document is invisible to them. `RV.196` is **green right now while
three fields in this loop are dead**:

| Field | State |
|---|---|
| `TireSet.purchaseExpenseId` | written `nil` only (`TireSetDraft.swift:35`), read nowhere - and a comment one line below promises a rename *"must never overwrite it"* |
| `ServiceItem.partNumber` | `nil` at `ServiceEntryDraft.swift:12` and `ImportConversion.swift:147`, read nowhere |
| `ServiceItem.lifetime` | preserved on save ([PJ.23]) and settable nowhere |

**This blind spot is what let `purchaseExpenseId` ship dead in the first place.** It is also why this
row must land **before [PJ.26]**: PJ.26 writes `purchaseExpenseId`, and the guard should be the thing
that PROVES it fixed something rather than a test that was always green.

## What to build

1. **Give `TireSet` and `ServiceItem` their own `###` sections in `docs/SCHEMA.md`**, in the shape the
   existing entity sections use. They are real persisted entities with migrations and screens; the
   schema is the authority and it is silent about them.
2. **Add their `entityFieldSpecs` entries** in `FieldWriterScanner` so the field guard reads them.
3. **Re-run the guard and let it REPORT the three fields above as unwritten.** Each becomes a
   reasoned exception whose reason **names the row that will write it** (`PJ.26` for
   `purchaseExpenseId`, `PJ.22` for `lifetime`, `PJ.61`'s decision for `partNumber`), so the
   exception is removed in the same change that ships the writer - the mechanism that already made
   `PJ.45` delete its own exception hours after `RV.196` shipped.

## This brief's reading is a hypothesis - confirm it before you change anything

Four of the orchestrator's diagnoses were wrong in one session and an agent caught every one -
including, on `RV.196` itself, a claim about what the entity guard's exception list contained.
**Re-run both guards yourself** and report what they actually say before and after. In particular:

- **Do these two entities belong under their OWN headings, or as fields of an existing one?**
  `ServiceItem` is a child of `ServiceRecord`, which HAS a heading (`ServiceRecord & Expense`) -
  so the honest fix might be to document its fields there rather than invent a section. **Say which
  you chose and why.** The scanner's entry shape decides this as much as the prose does.
- **Does adding the headings report anything you did NOT expect?** The three fields above are the
  orchestrator's list. If the guard finds a fourth, that is the row's best finding.

## Explicitly out of scope

- **Writing any of the three fields.** Each is a decision that belongs to its own row - `PJ.26`,
  `PJ.22`, `PJ.61`. **A phantom writer added to silence the guard is the worst possible outcome here.**
- `RV.163`'s entity-level guard and its update-only-writer limit ([RV.196]'s row records it).
- Any other entity missing from `SCHEMA.md`. If you find more, **report them as a list**; widening
  this row to every entity is how it stops landing.

## Docs to read before writing (in order)

1. `ios/Tests/TankbookCoreTests/SchemaFieldWriterGuardTests.swift` and `FieldWriterScanner.swift` -
   especially `entityFieldSpecs` and the reasoned-exception self-check.
2. `docs/SCHEMA.md` - the shape an entity section takes, and where these two belong.
3. `diagnostics/REVIEW-SERVICE-2026-09-10.md` sections 4 and 5 - the walk that filed this.
4. `docs/TESTING.md` - where a guard is declared; extend it if the coverage statement changes.

## Environment axes this crosses

**None at runtime** - schema prose and a test-target scanner; no shipping code path differs. Say so.
**No screenshots** (a scanner is not a screen), and say that rather than shipping one.

## If this adds a failure path, what makes it visible in production?

None - it runs in CI and on a developer's machine, never in the app. Say so.

## Tests you must add

- **L1, and it FAILS the moment the headings land**: `TireSet.purchaseExpenseId` is reported as
  having no production writer **before** any exception is written for it. Report the guard's full
  output at that point - that list is the row's deliverable.
- **L1**: each exception's reason **names the row that will write the field**, and a blank reason
  still fails the self-check.
- **L1, the calibration**: a field that IS written on these entities - `TireSet.name`,
  `ServiceItem.title` - is **not** reported. A guard that flags everything on a newly-visible entity
  is mis-tuned, and this pair is what proves it discriminates.
- **L1**: the stale-exception check fires if an excepted field gains a writer, so the list cannot
  rot. (`PJ.45` proved this works; assert it for the new entries too.)

Every expectation names its ORACLE - the line you read to know a field is or is not written. Report
each suite's observed, **non-zero** count, filtered **by suite name**.

## The mutation you must run - I am naming it, do not choose your own

**Delete the `ServiceItem` (or `TireSet`) entry from `entityFieldSpecs`** and show the guard goes
green again - reproducing exactly today's blind spot. Then restore byte-identical and re-run.
Report both outputs verbatim.

That is the mutation because the defect here is a guard that passes for the wrong reason, and the
only way to demonstrate it is to make it pass for that reason again.

## Vacuous traps, named

- **Adding the headings and allowlisting all three fields**, which converts a defect list into a
  config file. The exceptions must name their writing row and be removable.
- Adding a phantom writer so the guard goes green.
- Documenting the entities in prose the scanner cannot parse - then the schema says one thing and
  the guard still sees nothing.
- Reporting a field the entity does not actually have because the heading's field list was written
  from memory rather than from the Swift type.

## Never stash, move or `git checkout` to get a "clean baseline"

An agent's `git stash` + `mv` loop destroyed three of its own new files on 2026-09-08.

## Never `pgrep -f` for a build process

Your brief is in your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**. Use
`pgrep -x xcodebuild`. **Never `pkill -f`.**

## Concurrent work in this checkout

Another `opencode` run has been growing the receipts corpus since 2026-09-10 19:57 and holds
uncommitted changes in `Spike/ReceiptSpike/fixtures/`,
`ios/Sources/TankbookCore/Config/PumpPhotoGate.swift` and `ios/Tests/TankbookCoreTests/Corpus*`.
**Do not touch, revert or `git checkout` any of them.** Also pre-existing and **not yours**: four
`ReminderNotificationActionTests` failures, and `SyncWriteTriggerTests` ([RV.203]), which fails under
machine load and passes alone - re-run it alone before reporting it.

## Standing checks

As left, `main` is **1935 tests / 233 suites**, **838** localization keys at 100% RU.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0 (from `ios/` it exits 2 with ~5000 phantom errors).
3. `cd ios && swift test` - full; report the count. **Run it alone.**
4. **`xcodebuild ... build` for the app target** ([RV.174]).

Verify by **exit code** (`echo $?`).

## Report back

**The guard's full output the moment the headings landed** - that list is the deliverable; whether
you gave `ServiceItem` its own heading or documented it under `ServiceRecord & Expense`, and why;
any entity beyond these two that `SCHEMA.md` does not document; every check with its **exit code
observed** and counts; **the mutation's red-then-green output verbatim**; and **anything you found
and did not fix**.
