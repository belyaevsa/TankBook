import Foundation
import TankbookCore

// MARK: - Form state

/// Everything the ConfirmManual sheet collects, plus the derived math that
/// drives the three-number card (docs/SCHEMA.md -> FillUp, the `unitPrice`
/// paragraph). The sheet is also the fallback the whole capture pipeline
/// degrades to, so it stands alone: no camera, no OCR, no network.
///
/// The three numbers are total money, volume (litres) and price per litre.
/// Typed strings are the user's own digits; when exactly two of the three are
/// typed the third derives on save and `crossCheck = .notApplicable` (with only
/// two independent values there is no redundancy left to check). Typing all
/// three runs the cross-check.
struct ManualFillUpFormState: Equatable {
    var total = ""
    var liters = ""
    var pricePerL = ""

    /// The entry's original currency. Defaults to the vehicle's home currency
    /// (loading); a foreign pick makes the money pair rate-pending (F9).
    var currency: CurrencyCode = .eur
    /// Whether the user has opened the folded currency section.
    ///
    /// Lives in the FORM STATE, not in the section's own `@State`: the section
    /// is rebuilt whenever the parent form re-renders, which resets a local
    /// `@State` to false immediately after the tap that set it. The measured
    /// symptom was a currency row that could be tapped and never opened -
    /// `collapsed.exists=true, chip.exists=false` right after the tap - so the
    /// control was inert for the user, not merely awkward for the test.
    var isCurrencyExpanded = false
    var fuelKind: FuelKind = .petrol95
    var isFull = true
    /// The tank level after this fill-up (docs/SCHEMA.md: 0-100, 100 = full).
    /// Set through the tank-level sheet (P1.9); `nil` on a bare partial fill.
    /// The 100 ⇔ full invariant is enforced on save: full always writes 100.
    var tankLevelAfterPct: Double?
    /// The odometer in the vehicle's distance unit, pre-filled from the last
    /// known value; the live "+N km since last" caption under it (PJ.14)
    /// reacts to what is typed here.
    var odometer = ""
    var date = Date()

    /// The user's typed manual rate (F9, hard rule 13): the ORIGINAL per HOME
    /// rate for this entry, as the user typed it. Empty string = none entered;
    /// a valid positive parse (`manualRateDecimal`) makes the conversion state
    /// `.converted(.manual)` at the ENTRY's date and writes through
    /// `Money.applyingManualRate` on save. The raw string is kept so the field
    /// shows exactly what the user's keypad produced (a Russian locale types
    /// `4,2706`; reformatting it would fight the user's own digits).
    var manualRate = ""

    /// Whether the manual-rate editor has been engaged, so it stays open even
    /// if the field is cleared mid-edit (the same state-in-the-form rule as
    /// `isCurrencyExpanded`: a local `@State` in the card does not survive the
    /// parent's re-renders). Without it, clearing the field on a feed-converted
    /// card flips it back to the feed and the input vanishes while the user is
    /// typing in it - a hard-rule-13 "edit it once" bug in the opposite
    /// direction.
    var isManualRateEditorOpen = false

    /// P2.3: which pump-card fields the extraction RESOLVED (never nil fields,
    /// never a QR-authoritative total - that is exact, not OCR-derived). Feeds
    /// the dimming gate: a resolved-but-unconfirmed field renders dimmed, and
    /// stays fully editable (hard rule 13).
    var resolvedByExtraction: Set<ManualFillUpMath.Field> = []

    /// P2.3: the pump-card fields the user has engaged with since the pre-fill
    /// (tapped or edited). "Low-confidence OCR fields render at 60% opacity
    /// until confirmed by tap or edit" (docs/DESIGN.md) - engagement lifts the
    /// dim, permanently.
    var userConfirmedFields: Set<ManualFillUpMath.Field> = []

    /// Snapshots for the discard guard: the form is "dirty" only for real
    /// edits, not for the odometer/date pre-fill (SCREENMAP rule 1 - typed
    /// input asks before discarding, convenience pre-fills do not). The
    /// extraction pre-fill is a convenience pre-fill exactly like the odometer:
    /// opening a scanned sheet and closing it untouched discards silently.
    var initialOdometer = ""
    var initialDate = Date()
    var initialTotal = ""
    var initialLiters = ""
    var initialPricePerL = ""
    var initialManualRate = ""

    // MARK: Parsing

    private static func decimal(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Decimal(string: trimmed)
    }

    var totalDecimal: Decimal? { Self.decimal(total) }
    var pricePerLDecimal: Decimal? { Self.decimal(pricePerL) }

    /// The typed manual rate, parsed. Accepts the device's own decimal
    /// separator (a Russian keypad produces `4,2706`); refuses 0, negative and
    /// unparseable text (returns nil - the entry stays rate-pending, F9).
    var manualRateDecimal: Decimal? {
        ManualRate.parse(manualRate)
    }

    var odometerValue: Int? {
        let trimmed = odometer.trimmingCharacters(in: .whitespaces)
        // Format-on-blur puts a thin-space grouped string back into the field
        // (HANDOVER.md open item 0); grouping is DISPLAY only, so the model
        // strips it before parsing.
        return trimmed.isEmpty ? nil : Int(OdometerFormat.ungrouped(trimmed))
    }

    // MARK: The third value derives

    /// The three numbers as the deriver wants them: volume ALWAYS litres,
    /// money in the entry's original currency.
    func mathFields(volumeUnit: VolumeUnit) -> ManualFillUpMath.Fields {
        .init(total: totalDecimal,
              volumeL: litersDisplayDouble.map { ManualFillUpMath.volumeL(from: $0, unit: volumeUnit) },
              unitPrice: pricePerLDecimal)
    }

    private var litersDisplayDouble: Double? {
        Self.decimal(liters).map { NSDecimalNumber(decimal: $0).doubleValue }
    }

    /// The fully-specified triple + cross-check verdict, or `nil` when fewer
    /// than two of the three numbers are typed (the artboard's "Enter total
    /// and liters to save" state).
    func derived(volumeUnit: VolumeUnit) -> ManualFillUpMath.Derived? {
        ManualFillUpMath.derive(from: mathFields(volumeUnit: volumeUnit))
    }

    /// The total that will actually be saved: the derived total (which covers
    /// the typed-total case too) when two of three are present, else the typed
    /// total, else nil. Used by the foreign-currency card so its converted
    /// figure matches what Save writes.
    func effectiveTotal(volumeUnit: VolumeUnit) -> Decimal? {
        derived(volumeUnit: volumeUnit)?.total ?? totalDecimal
    }

    /// The value a field displays: the typed digits if the user has typed, else
    /// the derived value when this is the field the deriver fills in, else nil.
    func displayText(for field: ManualFillUpMath.Field, volumeUnit: VolumeUnit) -> String? {
        switch field {
        case .total:
            if !total.isEmpty { return total }
            guard let derived = derived(volumeUnit: volumeUnit) else { return nil }
            return ManualFillUpFormat.decimal(derived.total, fractionDigits: 2)
        case .volume:
            if !liters.isEmpty { return liters }
            guard let derived = derived(volumeUnit: volumeUnit) else { return nil }
            let display = ManualFillUpMath.displayVolume(from: derived.volumeL, unit: volumeUnit)
            return ManualFillUpFormat.decimal(display, fractionDigits: 2)
        case .unitPrice:
            if !pricePerL.isEmpty { return pricePerL }
            guard let derived = derived(volumeUnit: volumeUnit) else { return nil }
            return ManualFillUpFormat.decimal(derived.unitPrice, fractionDigits: 3)
        }
    }

    /// True once two of the three numbers exist - the save gate.
    func canSave(volumeUnit: VolumeUnit) -> Bool {
        derived(volumeUnit: volumeUnit) != nil
    }

    // MARK: Discard guard

    /// Real edits only: typed numbers (against the pre-fill snapshots), an
    /// odometer changed from its pre-fill, a date moved, a fuel/currency/full-
    /// tank choice made. Opening the sheet and closing it with just the
    /// convenience pre-fills discards silently.
    func hasEdits(vehicle: Vehicle) -> Bool {
        if total != initialTotal || liters != initialLiters || pricePerL != initialPricePerL { return true }
        // A tank level set on a partial fill is a real edit (100 on a full
        // fill is the toggle's own state, not an edit).
        if !isFull && tankLevelAfterPct != nil { return true }
        // Format-on-blur puts a thin-space grouped string back into the field
        // (HANDOVER.md open item 0); it is not an edit, so compare ungrouped.
        if OdometerFormat.ungrouped(odometer) != OdometerFormat.ungrouped(initialOdometer) { return true }
        if !Calendar.current.isDate(date, inSameDayAs: initialDate) { return true }
        if !isFull { return true }
        if fuelKind != (vehicle.fuelKinds.first ?? .petrol95) { return true }
        if currency != vehicle.homeCurrency { return true }
        if manualRate != initialManualRate { return true }
        return false
    }
}

// MARK: - Display formatting

/// Plain decimal formatting for the pump-card figures. No thousands grouping:
/// the odometer grouping formatter is deliberately deferred to P1.4
/// (HANDOVER.md open item 0), so digits render as the Add-car screen does today
/// and the fix lands once.
enum ManualFillUpFormat {
    static func decimal(_ value: Decimal, fractionDigits: Int) -> String {
        let formatter = Self.formatter(fractionDigits: fractionDigits)
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? ""
    }

    static func decimal(_ value: Double, fractionDigits: Int) -> String {
        let formatter = Self.formatter(fractionDigits: fractionDigits)
        return formatter.string(from: NSNumber(value: value)) ?? ""
    }

    private static func formatter(fractionDigits: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        // A DERIVED figure sits in the same card as the two the user typed, and
        // typed text is raw ("71.02"). Left to Locale.current this formatter
        // used the region's separator - on a device with Estonian regional
        // settings, 1.6789 rendered as "1,679" beside "71.02" and "42.30", so
        // one card showed two different decimal separators and a price per litre
        // that read as one thousand six hundred. Pin the separator to the one
        // the input fields use; presentation-level localisation of numerals is
        // P5's job, and must then change BOTH sides together.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }
}

// MARK: - F9a timeline support

/// The odometer-conflict quote for the F9a warn (docs/ERRORS.md -> Confirm).
/// Produced from the validation engine's flag - the check lives in
/// TankbookCore, never in UI-side logic.
struct OdometerConflict: Equatable {
    let quote: String?
    let flagKind: ConflictState.ConflictKind
}

extension ManualFillUpFormState {
    /// Runs the candidate entry through `TimelineValidator` against the
    /// vehicle's existing timeline. Returns the conflicting-entry quote when the
    /// candidate breaks the order invariant (the documented F9a state); a plain
    /// timeline-flag marker otherwise.
    func odometerConflict(vehicle: Vehicle,
                          existingEntries: [any Entry],
                          distanceUnit: DistanceUnit) -> OdometerConflict? {
        guard let odo = odometerValue else { return nil }
        let candidate = candidate(vehicle: vehicle)
        let validations = TimelineValidator.validate(entries: existingEntries + [candidate],
                                                     vehicle: vehicle)
        guard let validation = validations.first(where: { $0.entryID == candidate.id }),
              let flag = validation.flags.first else {
            return nil
        }
        let unit = L10n.distanceUnit(distanceUnit)
        switch flag.detail {
        case .order(let previousOdometer, let previousDate, _, _):
            if let previousOdometer, let previousDate, odo <= previousOdometer {
                let day = previousDate.formatted(.dateTime.month(.abbreviated).day())
                let quote = String(format: L10n.localize("%@ already recorded %d km."), day, previousOdometer)
                return OdometerConflict(quote: quote, flagKind: flag.kind)
            }
            return OdometerConflict(quote: nil, flagKind: flag.kind)
        case .pace:
            return OdometerConflict(quote: nil, flagKind: flag.kind)
        }
    }

    /// A best-effort candidate `FillUp` used ONLY to run the timeline check; the
    /// entry actually saved is built by the save path with the derived third
    /// value and the engine's verdict.
    func candidate(vehicle: Vehicle) -> FillUp {
        let now = Date()
        let derived = derived(volumeUnit: vehicle.units.volume)
        let money = Money(amount: derived?.total ?? 0, currency: currency,
                          homeCurrency: vehicle.homeCurrency)
        return FillUp(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: date, odometer: odometerValue,
            money: money, note: nil, attachments: [], provenance: .manual,
            conflict: .none, purchaseGroupId: nil,
            volumeL: derived?.volumeL ?? 0,
            unitPrice: derived?.unitPrice,
            fuelKind: fuelKind, fuelGrade: nil, isFull: isFull,
            tankLevelAfterPct: isFull ? 100 : tankLevelAfterPct, stationId: nil,
            crossCheck: derived?.crossCheck ?? .notApplicable, extraction: nil)
    }
}
