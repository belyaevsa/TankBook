# REVIEW-SCENARIO: F9a · first walk

- **Run:** REVIEW-SCENARIO-F9a-2026-09-11b
- **Scenario:** `F9a` (`docs/JOURNEYS.md:661`)
- **Verdict: NOT IMPLEMENTED**

## Ticked rows found to be untrue

None. Every closed row naming F9a (`P1.8`, `PJ.11`, `PJ.34`, `PJ.45`, `RV.117`, `RV.141`, `RV.192`, `RV.211`, `RV.218`) is true as walked. The two gaps are a ticked row that under-delivered its own text (PJ.34's "move entry") and an OPEN row (RV.230) - neither is a ticked-but-false row.

## Promise-to-code map

| Journey promise | Status | Evidence |
|---|---|---|
| Invariant: sorted by date, reading never falls, strictly increases only between travel-measuring kinds (FillUp, ChargeSession); ServiceRecord/Expense may share a reading | **MET** | `TimelineValidator.invariantHolds` (`ios/Sources/TankbookCore/Validation/TimelineValidator.swift:103-116`); `measuresTravel` = FillUp or ChargeSession (`:551-553`) |
| Checks on every write, not just capture: order against date-neighbours + implied pace (default ~1500 km/day, per-vehicle tunable) | **MET** | CHECK 1 order (`:251-268`), CHECK 2 pace (`:270-301`); default `paceLimitKmPerDay = 1500` (`docs/SCHEMA.md:45`); all write paths stamp (`PJ11TimelineWritePathsTests`); editable via Vehicle detail (PJ.45, `docs/TASKS-DONE.md:364`) |
| Discrepancy shown inline - amber underline on offending field + conflicting entry quoted | **PARTIAL** | Fill-up create/Confirm: `ManualFillUpSections.swift:448` (`warn: conflict != nil`) + `ManualFillUpFormState.odometerConflict` quote (`:336-347`). Fill-up edit: `EditEntryView.swift:204-210`, `:552-555`. Service create: `ServiceEntryView.swift:97` + `ServiceEntryConflictWarning`. **MISSING for service/expense/charge EDIT** - see RV.230 below |
| Ranked suggestions: fix odometer · fix date · move entry | **PARTIAL** | fix odometer + fix date render via `F9aFixRow` (`ios/App/Sources/ConfirmManual/F9aFixRow.swift:53-67`), produced by `TimelineValidator.suggestions` (`:368-393`). **"move entry" has no code** - no `moveEntry` case in `ResolutionSuggestion` (`:46-56`); PJ.34 explicitly did NOT build it (`docs/TASKS-DONE.md:363`) |
| Ranking is a fill-up's; service/expense presents the single odometer fix | **MET** | `F9aFixPresentation.fixes(_:for:)` collapses service/expense to `[.fixOdometer]` (`ios/Sources/TankbookCore/Validation/F9aFixPresentation.swift:31-41`); RV.211 |
| Receipt priority: printed timestamp is ground truth, fix-odometer preselected, date override needs explicit confirmation naming the date | **MET** | `TimelineValidator.suggestions` receipt branch (`:380-385`); Confirm passes `receiptEvidence` as attachments (`ManualFillUpView.swift:285-290`); `F9aFixRow` date confirmation + `dateConfirmationMessage` (`F9aFixRow.swift:58-67`, `ManualFillUpFormState.swift:290-296`); PJ.34 |
| Saving anyway always allowed | **MET** | Validator returns advisory results only (`isSaveable` always true, `:93`); save paths never block on `conflict` |
| Amber conflict badge on the entry | **MET** | `HomeSections.swift:471-481` (`conflictBadgeButton`, `NavigationLink(Route.editEntry)`); `isConflicted` derived from `conflict != .none` (`LogStream.swift:593`) |
| Segment excluded from consumption math until resolved | **MET** | `ConsumptionEngine.swift:259-318` (segments touching an unresolved conflict excluded) |
| Trends footnotes the exclusion | **MET** | `ExcludedEntriesFootnote` on `TrendsView.swift:91`; excluded list `ExcludedEntriesView.swift` |
| Resolving is one tap from the badge into edit with the discrepancy pre-highlighted | **PARTIAL** | Fill-up: badge → `EditEntryView` renders the warn + neighbourhood + `F9aFixRow` (pre-highlighted). **Non-fill (service/expense/charge): badge → `EditEntryView` renders NO warning** - `EditEntryNonFillView` has no conflict surface (RV.230) |

## Sequence trace

One user, one thing: the user edits a service odometer into a value that contradicts its date.

1. Open the service in Edit entry → `EditEntryNonFillView` renders the odometer row with no conflict surface (`EditEntryNonFillView.swift:338-363`).
2. Save → `saveNonFill` → `writeNonFill` runs `TimelineValidator.validate` and stamps `.flagged` on the record (`EditEntryView+NonFillSave.swift:44-47`), then writes it (`:60-73`).
3. Home reloads; the row now carries the amber badge (`HomeSections.swift:471-481`). The user taps it.
4. The badge pushes `Route.editEntry` → `EditEntryNonFillView` again, which renders **no warn row, no quote, no fix**. The user cannot see what is wrong.
5. The only resolution surface is Settings → "Needs a look" (`FlaggedEntriesView`), where Accept lives (`:221-231`); it is a second, disconnected door and does not name why this entry is flagged.

Where a fact stops being carried: **the flag written at step 2 is never surfaced to the user at step 4.** The stamp is real, the badge is real, but the "discrepancy pre-highlighted" promise dies between the badge and the non-fill edit form - the exact `RV.98`/"moves to Recently deleted" shape (a screen exists, the behaviour it promises does not). This is RV.230, already filed and OPEN.

## Proposed rows

| Finding | Deliverable | Journey stage | Consequence today | Severity | Check (L1/L4) | Scenario |
|---|---|---|---|---|---|---|
| Non-fill edit never surfaces its flag | Render the same warn row + single *Fix* (`F9aFixPresentation`, RV.211's rule) on `EditEntryNonFillView`; cover charge as well as service/expense (all three share `writeNonFill`) | "discrepancy shown inline" + "resolve pre-highlighted" | A service/expense/charge edited into a conflict carries a flag the user can never see or clear from the entry (hard rules 7 and 8) | **bug** | L1: non-fill edit into a conflict exposes the flag in the view model; L4 `EditEntryUITests` EN+RU: amber row + *Fix* on a seeded conflicting service; flag clears through `flagAcceptance` | F9a |
| "move entry" is promised and absent | Reconcile `docs/JOURNEYS.md:665`: drop "move entry" (aligning with `docs/ERRORS.md:279` and PJ.34's "NOT built" note) OR define and file a row that builds it | "ranked suggestions: fix odometer · fix date · move entry" | The spec names an affordance no screen shows; no user is stranded (fix odometer / fix date / save-anyway cover the conflict) | **polish** | L1: a doc-only change needs no suite; a build would need a defined operation and an L4 in the affected path | F9a |

## Not settled

- **Service quote hardcodes "km".** `ServiceEntryFormState.swift:274` uses `L10n.localize("%@ already recorded %@ km.")` while the fill-up path uses `OdometerConflict.quote(day:odometer:distanceUnit:)` which switches km/mi (`ManualFillUpFormState.swift:273-282`). A service conflict on a mi-based car quotes "km". Same shape as RV.126's fix on the fill-up; the service path was not carried along. Minor (mi vehicles are rare in the shipped locales), so noted here rather than filed as a blocking row; a one-line fix if the product owner wants it.
- **Charge is inside RV.230's blast radius but outside its text.** `writeNonFill` stamps and `EditEntryNonFillView` renders nothing for `ChargeSession` exactly as for service/expense; RV.230's title names only "service or expense". The fix should treat the charge as a third non-fill kind, not leave it as an invisible flag.
