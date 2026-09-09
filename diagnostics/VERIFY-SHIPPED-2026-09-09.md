# VERIFY-SHIPPED 2026-09-09 - do the last 30 ticked rows still hold?

Read-only source audit. No build/test/toolchain was run (another agent owns it; the
machine is memory-constrained). Every verdict is read from the code, never from a
green suite, a comment or a doc. Rows are the ones named in the dispatch, oldest first.

## Method note

`RV.141` is **not a ticked row**: `docs/TASKS.md:708` still shows it as `[ ]` open.
It was listed in Group A by mistake. I did not verify it as shipped, but see the
observation at the bottom - the code already carries most of its wiring.

`RV.117a`/`RV.117b` are one row (`RV.117`, `TASKS-DONE.md:448`) shipped in two
halves; both halves are verified against `TimelineValidator`.

---

## Group A - shipped before the refactors

### RV.126 - HOLDS
The `km`-hardcoded conflict quote is gone. `OdometerConflict.quote(day:odometer:distanceUnit:)`
switches on `DistanceUnit` with a full localised sentence per unit - `.km` and `.mi` -
and `odometerConflict(vehicle:existingEntries:distanceUnit:)` passes the vehicle's unit
through. Citation: `ios/App/Sources/ConfirmManual/ManualFillUpFormState.swift:246-255` and
`:278-281`. No sibling `"%@ km"` shape remains in the file.

### RV.128 - HOLDS
The per-row helper is now called at the call site. `ImportOdometerCell` receives
`distanceUnit: model.distanceUnit(for: row)` at
`ios/App/Sources/Import/ImportReviewView.swift:267-268` (also `:211` and `:216`), and the
helper resolves each row's car through `row.fill?.vehicleId ?? row.nonFuelVehicleID`
(`ios/App/Sources/Import/ImportFlowModel.swift:122-128`). The zero-references dead helper
is no longer dead.

### RV.131 - HOLDS
The duplicate card renders both members, not one sentence. `HomeDuplicateCard` draws
`group.counted` and `group.excluded` as two `memberRow`s, each a `NavigationLink(value:
Route.editEntry(member.id))`, with time, odometer, amount and attachment - and the
`ForEach(members)` runs over both (`ios/App/Sources/Home/HomeDuplicateCard.swift:43-48`,
`:94-116`). Counting is untouched: the card only renders; the S2 single-count invariant
lives in `LogStream`/`HomeStats`, which this card does not feed.

### RV.132 - HOLDS
The demand drain is user-initiated and reports outcomes. `MoneyBackfillService.demandDrain`
calls `store.fetchSpan(..., trigger: .userInitiated)`
(`ios/Sources/TankbookCore/Rates/MoneyBackfillService.swift:121-122`), and
`LowPowerPolicy.defers` only defers `.ratePackRefresh` when the trigger is `.background`
(`ios/Sources/TankbookCore/Power/PowerState.swift:83-84`) - so a user tap is never
postponed by Low Power Mode. Outcomes are distinct: `demandOutcomeMessage` maps
`.nothingPending` -> "up to date" and a drained fill -> "converted N"
(`ios/App/Sources/ConfirmManual/ManualFillUpCurrencySupport.swift:181-195`); the immediate
acknowledgement is `PendingRatesFootnote.beginCheck` (`isChecking = true` before the await,
`ios/App/Sources/Shared/PendingRatesFootnote.swift:109-115`). The automatic launch pass
stays silent (S8 comment at `:13-15`).

### RV.133 - HOLDS
Swipe-to-accept (no dialog) and swipe-to-delete (one confirmation) are hand-rolled on the
non-`List` surface. `FlaggedSwipeRow` implements the drag
(`ios/App/Sources/Settings/FlaggedEntriesView.swift:512-547`) with a trailing two-action
tray, and `onQuickAccept` (`:461`) accepts with no dialog while `onDelete` opens the single
confirmation (`:110-116`). Delete tombstones through the per-kind `softDelete*` path, never
hard-deletes (`:242-263`). Both actions are exposed as accessibility actions (`:461-462`),
and the Accept-with-reason door is retained (`:461` and `performAccept`).

### RV.135 - HOLDS
`EcbRateFeed` now serves historical dates. `FetchAsync` routes by days-back: today from the
daily file, `<= RecentWindowDays` (60) from `eurofxref-hist-90d.xml`, older from
`eurofxref-hist.xml` (`backend/src/Tankbook.Api/Rates/EcbRateFeed.cs:86-95`), both history
files cached on the instance (`:108-141`) so a pass over N dates fetches once per file. The
date guard is intact: `QuotesFor` answers only from a row whose own `time` equals the
requested date (`:183-194`). Never serves today's rate for another date.

### RV.137 - HOLDS
Make/model/year suggestions now exist on the edit screen via the shared
`VehicleCatalogSuggestionsArea` (`ios/App/Sources/VehicleDetail/VehicleDetailSuggestions.swift:31-39`),
a pick writes make/model/year as text with no catalog id (`:47-53`, "nothing here stores a
catalog id" header at `VehicleDetailView.swift:15-16`). The fuel-chip clipping is fixed: the
pinned Save bar is a `safeAreaInset(edge: .bottom)` that renders only when `focus == nil`, so
it steps aside while the keyboard is up
(`ios/App/Sources/VehicleDetail/VehicleDetailView.swift:130-134`).

### RV.140 - HOLDS
Both halves are in. (1) Re-home: `VehicleDetailView.save` calls
`MoneyBackfillService.rehome(vehicleID:to:)` when the home currency changed
(`ios/App/Sources/VehicleDetail/VehicleDetailView.swift:321-328`), and `rehome` re-homes only
rate-pending pairs (`MoneyBackfillService.swift:232-248`), snapshotting same-currency rows
at rate 1 with no fetch via `Money.rehomed(to:)` (`Money.swift:186-198`). (2) Show original:
`LogEntryAmount` renders the original amount + original currency symbol, dimmed, when no home
figure exists (`ios/App/Sources/Home/HomeSections+LogStream.swift:200-218`), replacing the
old `guard ... homeAmount ... else { return nil }`.

### RV.142 - HOLDS
(1) Station id no longer dropped on import: `ImportConverter.makeFill` resolves the source
station name to a `Station` id via `ImportStationResolver.station` and writes
`stationId: station?.id` (`ios/Sources/TankbookCore/Import/ImportConversion.swift:53-66`).
(2) The duplicate fuel-kind is gone: `LogEntry.showsFuelKind` is true only when
`stationId` resolves to a live station AND the kind earns its place
(`ios/Sources/TankbookCore/Consumption/LogStream.swift:588-593`, `:645-647`). (3) Per-fill
consumption is plumbed: `consumptionPer100` is keyed by `closingFillID` from
`ConsumptionEngine.recompute` (`LogStream.swift:302-317`) and rendered in
`HomeSections.segmentView(.consumption:)` (`HomeSections.swift:537-541`); absent, never
zero, for a fill closing no segment.

### RV.82 - HOLDS
The suite states its own preconditions. `launch(replaying:seed:)` sets
`["-homeResetDatabase", seed, "-replayNotificationResponse", identifier]`
(`ios/App/UITests/RemindersDeepLinkUITests.swift:23-30`) - it plants its own DB/session seed
(`-seedRemindersDeepLink`) rather than inheriting whatever an earlier suite left in the
Keychain. `waitForCar` still asserts the real landing (`:124-133`).

### RV.112 - HOLDS
The shared accumulator is the single place a pending row's contribution is decided.
`LogStream.MonthTotal.Accumulator.add(_:)` counts a pending pair and never sums it as zero
(`ios/Sources/TankbookCore/Consumption/LogStream+Accumulator.swift:46-52`); `HomeStats.monthSpend`
(`HomeStats.swift:171-184`) and `TrendsStats.monthlySpendSeries`/`monthlyCostSeries`
(`TrendsStats.swift:157-207`) all reduce through it, so a pending month is `.partial`/`.pending`
(rendered as a marked figure or a gap), never a bare understated number.

---

## Group B - shipped during the refactors

### RV.144 - HOLDS
The edit path re-homes to the current home currency through the shared rule.
`buildUpdatedFill` uses `Money.edited(original:amount:currency:homeCurrency:
vehicle.homeCurrency)` (`ios/App/Sources/EditEntry/EditEntryFormState.swift:66-69`), and
`Money.edited` re-pends first then `rehomed(to:)`, snapshotting a now-same-currency pair at
rate 1 with no fetch (`ios/Sources/TankbookCore/Domain/Money.swift:235-246`). The
`?? .eur` fallback is gone from the production edit path (only the form's `= .eur` default
and test seeds remain).

### RV.145 - HOLDS
`MonthTotal` now carries the currency axis. The enum has `.complete/.partial/.mixed/.pending`
(`ios/Sources/TankbookCore/Consumption/LogStream.swift:63-86`); every amount is paired with
its `CurrencyCode` (`SpendSubtotal`, `LogGroup.grandTotalCurrency`, `CostPerKmFigure`). The
accumulator banks each known amount under its own `homeCurrency` and classifies `.mixed` when
known figures span currencies (`LogStream+Accumulator.swift:26-95`). Every surface renders
through `HomeFormat.spend(_:)`, which prints the figure's own symbol and the per-currency
breakdown for `.mixed` (`HomeSections+LogStream.swift:222-251`): the divider (`:103-154`),
the vitals tile (`HomeSections.swift:247-251`), the guest strip
(`HomeGuestLayout.swift:118-123`, cost-per-km carries its currency at `:107`), `VehicleVitals`
(`VehicleVitals.swift:27-33`), and the Trends spend/cost series (`TrendsStats.swift:171-204`).
Symbol travels with the figure everywhere; a pending row shows its original + original symbol,
dimmed (`HomeSections+LogStream.swift:200-218`).

### RV.146 - HOLDS
The hardcoded four chips are gone. `CurrencyChipRow` takes `offer: [CurrencyCode]`
(`ios/App/Sources/ConfirmManual/ManualFillUpSections.swift:15-19`); the offer is built on
device by `CurrencyOfferBuilder.offer` - home currency first, then history (most recent
first via `CurrencyHistory.recentCurrencies`), then the bundled region table, then a stable
default (`ios/Sources/TankbookCore/Catalog/CurrencyOffer.swift:40-57`). The lying hint is
rewritten to "Your currency first, then recent and nearby ..."
(`ManualFillUpCurrencySupport.swift:582`), which the code now implements. No network, no
second literal list.

### RV.147 - HOLDS
The windowed cost-per-km reuses the shared accumulator and refuses a bare ratio.
`ConsumptionEngine.costPerKm` feeds the window's moneys through
`LogStream.MonthTotal.Accumulator` and returns a figure only on `.complete`; `.partial`,
`.mixed` and `.pending` all return nil (`ios/Sources/TankbookCore/Consumption/ConsumptionEngine.swift:232-252`).
`TrendsStats` keys its cost/km span label off that same nil (`TrendsStats.swift:140-142`), so
no caption describes a figure that is not there.

### RV.117a / RV.117b - HOLDS
The bidirectional interval is derived in the same pass as the flags. `EntryValidation` carries
`validRange: TimelineValidRange?` (`ios/Sources/TankbookCore/Validation/TimelineValidator.swift:62`),
computed by `validRange(odometer:date:previous:next:limit:)` (`:269`) from the SAME neighbour
walk and `limit` the flags use (`:136-137`), so the interval and the flag cannot disagree.
Open-ended bounds are modelled (`.bounded(lower: nil, upper: nil)`, `:321`); it is computed,
never stored, never auto-applied. The UI half (neighbourhood chart) rides on this in the
flagged list via `FlaggedEntriesView`'s `-openFirstFlaggedEdit` seam and the shared
`pushedEditEntry` push (`FlaggedEntriesView.swift:141-145`).

### PJ.19 - HOLDS
The ranking ladder is written exactly as the docs specify - favourite within 300 m, last-used
within 300 m, this car's most-recent station, else nothing
(`ios/Sources/TankbookCore/Domain/StationSuggestion.swift:116-154`) - pure over injected
coordinates/permission. The dead `Not set` label is gone: the station row shows
"Choose station" and an add door instead of the inert placeholder
(`ManualFillUpStationRow.swift:39-45`, `:72-87`).

### PJ.25 - HOLDS
The parts shelf is reachable from Vehicle detail/Garage: the management row pushes
`Route.partsShelf(vehicle.id)` (`ios/App/Sources/VehicleDetail/VehicleDetailView.swift:167-173`),
the same `PartsShelfView` the nested service sheet shows (never a second implementation).

### PJ.28 - HOLDS
The scanned receipt is persisted with the expense. `ExpenseEntryView.save` writes the scan's
receipt via `ExpenseReceiptWrite.write(scan:repository:)` and stores
`attachments: attachmentIDs` (no longer `attachments: []`), with provenance `.receiptScan`
(`ios/App/Sources/ServiceEntry/ExpenseEntryView.swift:194-215`). The photo-write failure
degrades to "saved without the photo" and names it (hard rule 7), never blocking the save.

---

## Group C - shipped last (spot-checked here anyway)

### RV.136 - HOLDS
`RecordMerge.recordsEqual` now has a `Vehicle` case and a case per synced entity type
(`ios/Sources/TankbookCore/Sync/RecordMerge.swift:147-167`), each decoding and comparing
typed entities; the byte fallback (`default:`) is reachable only by a type this build does
not know. The exhaustive-coverage test (`SyncVehicleByteEchoTests` /
`SyncVehicleFieldMergeEchoTests`) is the seam that makes a missing case fail.

### RV.150 - HOLDS
The save stamps the fields the ranking reads. `StationStamp.applied` writes `lastUsedAt`,
`defaults` (fuel kind/grade, blanks-fill-only) and adopts a location only when the station has
none (`ios/Sources/TankbookCore/Domain/StationStamp.swift:30-44`); the Confirm save path calls
it via `stampChosenStation` (`ManualFillUpView+StationStamp.swift:21-36`) through
`repository.stampStation`, an ordinary `.dirty` write.

### RV.151 - HOLDS
The cross rate through the pack's base is derived on device. `RateStore.snapshot` tries the
direct row, then its inverse, then derives `(base, original) / (base, home)` from two
same-day legs (`ios/Sources/TankbookCore/Rates/RateStore.swift:86-121`); a missing leg stays a
miss, never a nearby-day or today substitution.

### RV.153 - HOLDS
The total finder now makes it right or abstains. `resolveTotal` outranks with the printed
fuel-line sum (`printedFuelLineSum`, `FuelExtractorTotalFinder.swift:183-202`) and, on a
disagreement between a single printed total and the product, requires corroboration
(`isCorroboratedTotal` / `isPrintedMoneyValue`) and otherwise returns nil
(`ios/Sources/TankbookCore/Extraction/FuelExtractor.swift:338-408`, the nil return at `:407`).
The tie-break in `modal` is nil on an unbreakable tie (`FuelExtractorTotalFinder.swift:290-304`).
No exception list or quarantine; the whole-class `noReceiptTotalIsConfidentlyWrong` property
is the guard this abstention serves.

### RV.154 - HOLDS
`ApplyBatchAsync` collapsed the round trips: one multi-row `WHERE id = ANY(@Ids) FOR UPDATE`
read (`backend/src/Tankbook.Api/Sync/SyncRepository.cs:203-207`), one
`ScnAllocator.AllocateRangeAsync` for the whole batch (`:281`), and one multi-row INSERT (plus
one UPDATE) (`:299-307`). Per-record outcomes (accepted/conflict/replay) are still computed
in the resolution pass (`:224-270`), and partial acceptance is preserved (conflicts settle as
no-ops inside the transaction, `:245-263`).

### RV.156 - HOLDS
The station row is interactive in both states and creation exists. `ManualFillUpStationRow`
offers "Add station" on an empty set (`:72-87`) and the same entry at the end of the populated
menu (`:102-108`); `createStation(named:)` routes through `ImportStationResolver.station` so a
matching name resolves (never mints a duplicate) and an unmatched name writes `.dirty`
(`ios/Sources/TankbookCore/Persistence/Repository+StationCreate.swift:30-42`). `upsertStation`
now has a non-seed caller. The stale "until PJ.19 ships" comment is gone.

### RV.157 - HOLDS
The debounced write trigger is wired to the database write signal. `AppSync` observes
`repository.database.writeSignal` (`ios/App/Sources/Settings/AppSync.swift:352-357`), and
`noteLocalWrite` nudges a lazily-built `SyncWriteScheduler` (debounced) through the same
`.background` door as the foreground pass (`:364-373`, `:132-135`). The save never awaits the
network - the write committed before the poke.

---

## Observations (not verdicts)

### RV.141 is open, and the code already carries most of its wiring
`HomeStats` already derives `excluded` (with per-row reasons), `excludedEntryCount` and
`excludedEntryIDs` (`ios/Sources/TankbookCore/Consumption/HomeStats.swift:92-98`, `:153-156`),
and Home's footnote routes N==1 -> `.editEntry` and N>1 -> `.excludedEntries`
(`ios/App/Sources/Home/HomeSections.swift:406-411`). Whether the destination list states the
per-row reason and whether `docs/ERRORS.md` rows 56/257 are reconciled is not verifiable here
without opening `ExcludedEntriesFootnote`/the destination screen's copy. The row remains
`[ ]` in `docs/TASKS.md`; whoever closes it should confirm those two remaining claims before
ticking.

### Residual: a rate-pending member inside a duplicate card shows no money
`HomeDuplicateCard.amountText` guards on `homeAmount` and returns nil for a pending member
(`ios/App/Sources/Home/HomeDuplicateCard.swift:184-188`), while the ordinary row
(`LogEntryAmount`) now shows the original. A duplicate pair whose counted member is still
rate-pending would therefore render with no amount. This is an incidental edge of RV.140's
"show the original always" and predates it; it is not the row's headline claim, but it is the
same shape the row fixed one surface away. No existing row appears to cover it - flag for a
future pass, not a re-open of RV.140.

---

## Summary

- Rows verified: **27** ticked rows (11 Group A, 8 Group B counting RV.117's two halves as
  one row, 8 Group C). `RV.141` was in the list but is not a ticked row - it is still `[ ]`.
- **BROKEN: 0.** Every ticked row's headline claim is still present in the code, each with a
  `file:line` seam. The four refactors named as highest risk (`RV.145`, `RV.153`, `RV.156`,
  `RV.157`) all landed cleanly and did not undo any earlier row's behaviour.
- No DEFECT-PATTERNS Part 2 shape was found among the ticked rows (no unreachable screen, no
  reader without a writer, no copy naming a missing thing, no dead end). The one residual
  noted above (duplicate-card pending amount) is the only thing worth a follow-up.
