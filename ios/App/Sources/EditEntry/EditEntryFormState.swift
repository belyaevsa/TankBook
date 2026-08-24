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
        fuelKind = fill.fuelKind
        isFull = fill.isFull
        tankLevelAfterPct = fill.tankLevelAfterPct
        odometer = fill.odometer.map(OdometerFormat.grouped) ?? ""
        date = fill.date
    }

    /// The edited `FillUp` from the form + the entry's original identity.
    /// `provenance`, attachments, purchaseGroupId, extraction and fuelGrade are
    /// carried over untouched; money is edited via the Money pair's snapshot
    /// rules (docs/SCHEMA.md: editing amount/currency clears the snapshot for
    /// re-conversion - hard rule 3). The timeline flag is re-derived from the
    /// validator on the edited timeline: a save-anyway keeps the flag.
    func buildUpdatedFill(from original: FillUp, vehicle: Vehicle,
                          derived: ManualFillUpMath.Derived,
                          otherEntries: [any Entry], stationID: UUID?) -> FillUp {
        var updated = original
        updated.updatedAt = Date()
        updated.date = date
        updated.odometer = odometerValue
        updated.money = Self.updatedMoney(originalMoney: original.money,
                                          currency: currency,
                                          derivedTotal: derived.total,
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
        updated.conflict = validations.first { $0.entryID == updated.id }?.conflict ?? .none
        return updated
    }

    private static func updatedMoney(originalMoney: Money?, currency: CurrencyCode,
                                     derivedTotal: Decimal,
                                     homeCurrency: CurrencyCode) -> Money? {
        guard let money = originalMoney else {
            return Money(amount: derivedTotal, currency: currency, homeCurrency: homeCurrency)
        }
        let withCurrency = currency == money.currency ? money : money.replacingCurrency(currency)
        return withCurrency.replacingAmount(derivedTotal)
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

    var amountDecimal: Decimal? {
        let trimmed = amount.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : Decimal(string: trimmed)
    }

    var odometerValue: Int? {
        let trimmed = odometer.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : Int(OdometerFormat.ungrouped(trimmed))
    }

    /// The money pair, edited through the snapshot rules: any amount or
    /// currency edit clears the snapshot for re-conversion (hard rule 3).
    func editedMoney(original: Money?, homeCurrency: CurrencyCode) -> Money? {
        guard let amount = amountDecimal else { return original }
        let base = original ?? Money(amount: amount, currency: currency, homeCurrency: homeCurrency)
        let withCurrency = currency == base.currency ? base : base.replacingCurrency(currency)
        return withCurrency.replacingAmount(amount)
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
