import Foundation
import TankbookCore

// MARK: - FillUp pre-fill + rebuild

extension ManualFillUpFormState {
    /// Loads an existing `FillUp`'s stored values as editable defaults
    /// (hard rule 13: the app suggests, the user decides - a stored value is a
    /// default input, never a fact). The three numbers come back in the
    /// vehicle's display units; `odometer` is pre-grouped for display, and the
    /// field strips grouping while focused (the format-on-blur contract).
    mutating func load(from fill: FillUp, vehicle: Vehicle) {
        let displayVolume = ManualFillUpMath.displayVolume(from: fill.volumeL,
                                                           unit: vehicle.units.volume)
        total = fill.money.map { ManualFillUpFormat.decimal($0.amount, fractionDigits: 2) } ?? ""
        liters = ManualFillUpFormat.decimal(displayVolume, fractionDigits: 2)
        pricePerL = fill.unitPrice.map { ManualFillUpFormat.decimal($0, fractionDigits: 3) } ?? ""
        currency = fill.money?.currency ?? vehicle.homeCurrency
        manualRate = Self.loadedManualRate(from: fill.money)
        isManualRateEditorOpen = fill.money?.rateSource == .manual
        fuelKind = fill.fuelKind
        isFull = fill.isFull
        tankLevelAfterPct = fill.tankLevelAfterPct
        odometer = fill.odometer.map(OdometerFormat.grouped) ?? ""
        date = fill.date
        // RV.31: pin the discard-guard snapshots to the LOADED values. An
        // existing entry's stored values are a convenience pre-fill exactly
        // like the odometer/date pre-fill on a NEW entry - the entry is not
        // "edited" until the user changes something. `initialDate` in
        // particular defaults to `Date()` at instantiation, so a pristine form
        // rebuilt later for the discard comparison would never equal the
        // loaded one unless the snapshot is taken here.
        initialTotal = total
        initialLiters = liters
        initialPricePerL = pricePerL
        initialOdometer = odometer
        initialDate = date
        initialManualRate = manualRate
    }

    /// A stored USER-set rate loads back into the manual-rate field (hard rule
    /// 13, "and again afterwards"): the conversion card then shows it as
    /// Manual and it stays editable. A feed-written rate is NOT loaded - the
    /// feed's number is a suggestion, and the manual field only ever holds the
    /// user's own decision.
    private static func loadedManualRate(from money: Money?) -> String {
        guard let money, money.rateSource == .manual, let rate = money.rate else { return "" }
        return ManualFillUpFormat.decimal(rate, fractionDigits: 4)
    }

    /// The edited `FillUp` from the form + the entry's original identity.
    /// `provenance`, attachments, purchaseGroupId, extraction and fuelGrade are
    /// carried over untouched; money is edited through the Money pair's shared
    /// edit rule (`Money.edited`, docs/SCHEMA.md -> Money): a money-fact change
    /// re-pends the pair and re-homes it to the vehicle's CURRENT home
    /// currency, a no-touch save leaves it byte-identical (hard rule 3). The
    /// timeline flag is re-derived from the validator on the edited timeline: a
    /// save-anyway keeps the flag.
    func buildUpdatedFill(from original: FillUp, vehicle: Vehicle,
                          derived: ManualFillUpMath.Derived,
                          otherEntries: [any Entry], stationID: UUID?) -> FillUp {
        var updated = original
        updated.updatedAt = Date()
        updated.date = date
        updated.odometer = odometerValue
        updated.money = Money.edited(original: original.money,
                                     amount: derived.total,
                                     currency: currency,
                                     homeCurrency: vehicle.homeCurrency)
        updated.volumeL = derived.volumeL
        updated.unitPrice = derived.unitPrice
        updated.fuelKind = fuelKind
        updated.isFull = isFull
        updated.tankLevelAfterPct = isFull ? 100 : tankLevelAfterPct
        updated.stationId = stationID
        updated.crossCheck = derived.crossCheck

        let validations = TimelineValidator.validate(entries: otherEntries + [updated],
                                                     vehicle: vehicle)
        let validation = validations.first { $0.entryID == updated.id }
        updated.conflict = validation?.conflict ?? .none
        // RV.104: the acceptance the validator keeps (nil once the accepted
        // facts are edited or the timeline heals) rides the saved entry - a
        // save that edits only the note must not silently drop the acceptance
        // and re-flag a still-accepted entry.
        updated.flagAcceptance = validation?.acceptance
        return updated
    }
}

// MARK: - Non-FillUp entry form

/// Editable fields for the other three entry types (docs/SCHEMA.md, Entry).
/// Everything the artboard's edit card shows for a non-fill entry, as defaults
/// loaded from the stored row - hard rule 13 applies here too.
struct EditEntryNonFillForm: Equatable {
    var amount = ""
    var currency: CurrencyCode = .eur
    var date = Date()
    var odometer = ""
    var note = ""
    var energyKWh = ""
    var provider = ""
    var vendor = ""
    var title = ""
    /// The expense's category (docs/SCHEMA.md, Expense). It is a stored fact
    /// the user can set - and for an imported row it is what the importer
    /// GUESSED from the source file's kind column - so it must be editable
    /// here, not only at creation (hard rule 13). Ignored for every other kind.
    var category: ExpenseCategory = .accessory
    /// A service's line items (docs/SCHEMA.md, ServiceItem): the actual work,
    /// its category and its cost. Loaded from the stored record so it is
    /// editable "again afterwards" (hard rule 13) - an imported service gets
    /// its items from the source file's kind column, which is a guess. Reuses
    /// the create screen's `ServiceEntryItemDraft` so the two paths cannot
    /// drift. Ignored for every other kind.
    var items: [ServiceEntryItemDraft] = []

    var amountDecimal: Decimal? {
        let trimmed = amount.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : Decimal(string: trimmed)
    }

    var odometerValue: Int? {
        let trimmed = odometer.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : Int(OdometerFormat.ungrouped(trimmed))
    }

    /// The money pair, edited through the shared edit rule (`Money.edited`,
    /// docs/SCHEMA.md -> Money): a money-fact change clears the snapshot for
    /// re-conversion (hard rule 3) and re-homes the pair to the vehicle's
    /// CURRENT home currency; a no-touch save leaves it byte-identical. An
    /// empty amount (a non-fill form with nothing typed) keeps the stored money
    /// untouched.
    func editedMoney(original: Money?, homeCurrency: CurrencyCode) -> Money? {
        Money.edited(original: original, amount: amountDecimal, currency: currency,
                     homeCurrency: homeCurrency)
    }

    // MARK: - Line item collection

    /// Appends a blank editable row - the screen's "Add line item". The row is
    /// the user's to fill or delete; nothing is written until Save, so an
    /// abandoned blank row is discarded with the form.
    mutating func addServiceItem() {
        items.append(ServiceEntryItemDraft())
    }

    /// Removes the row with `id`, preserving the order of the rest. Deleting
    /// the LAST row is legal (see the delete affordance on `EditEntryNonFillView`
    /// for why), so this never guards a minimum count.
    mutating func removeServiceItem(id: UUID) {
        items.removeAll { $0.id == id }
    }

    /// Whether this save set or changed any line item's lifetime. The post-save
    /// reminder offer responds to the user stating a maintenance interval
    /// (PJ.22), not to every unrelated edit - the create door already offers for
    /// a category interval, and re-offering on a note edit would be the "three
    /// oil reminders" annoyance J7d warns about. Each draft's `original` is the
    /// stored item it loaded from, so a newly added row with a lifetime also
    /// counts (its `original` is nil).
    var serviceLifetimeChanged: Bool {
        items.contains { $0.lifetime != $0.original?.lifetime }
    }

    // MARK: - Line sum vs Amount (RV.199)

    /// The service's line sum, classified by currency - the SAME rule the
    /// create screen's header uses, so the two doors cannot state different
    /// totals for the same items. Meaningful only for a service; the other
    /// kinds carry no items.
    func lineSum(homeCurrency: CurrencyCode) -> ServiceItemSum {
        items.lineSum(homeCurrency: homeCurrency)
    }

    /// True when the Amount and the line sum both state a figure and disagree,
    /// or the lines span currencies so no single figure can match. ATTENTION,
    /// never a gate: the Amount stays independently editable - an invoice's
    /// grand total legitimately differs from its lines (tax, a discount, an
    /// un-itemised line) and the user's value is theirs (hard rule 13) - so the
    /// entry always saves. `false` when no item carries a cost, so there is
    /// nothing to compare.
    func lineSumDiffersFromAmount(homeCurrency: CurrencyCode) -> Bool {
        switch lineSum(homeCurrency: homeCurrency) {
        case .none:
            return false
        case .summed(let amount, let currency):
            guard let typed = amountDecimal else { return true }
            return typed != amount || currency != self.currency
        case .mixed:
            return true
        }
    }
}

// MARK: - The delta toast copy

/// The "Consumption updated: 6.9 -> 6.8 L/100km" message (docs/ERRORS.md ->
/// Edit entry, row 4). Old and new come from the engine, before and after the
/// save; this layer only rounds to display precision and composes the
/// localised phrase (a full phrase per language - never value concatenation,
/// which is how a composed string broke in Russian on P1.4). Returns nil when
/// no figure actually changed: an edit that moves nothing shows no toast.
enum EditConsumptionDelta {
    static func message(before: Headline?, after: Headline?,
                        unit: ConsumptionUnit) -> String? {
        guard let beforeValue = ConsumptionDelta.displayedValue(before),
              let afterValue = ConsumptionDelta.displayedValue(after),
              beforeValue != afterValue else { return nil }
        let format = L10n.localize("Consumption updated: %1$@ → %2$@ %3$@")
        return String(format: format,
                      ManualFillUpFormat.decimal(beforeValue, fractionDigits: 1),
                      ManualFillUpFormat.decimal(afterValue, fractionDigits: 1),
                      L10n.consumptionUnit(unit))
    }
}
