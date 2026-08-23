import Foundation

/// The ConfirmManual third-value derivation (docs/SCHEMA.md -> FillUp).
///
/// Receipts print all three numbers and the redundancy IS the confidence signal;
/// when the user types only two, the third derives on save and
/// `crossCheck = .notApplicable` - with only two independent values there is no
/// redundancy left to check. Typing all three runs the cross-check
/// (`volumeL x unitPrice ~= money.amount`, tolerance `max(0.02, 0.5%)`).
///
/// All math is `Decimal` at full precision. A derived value that does not divide
/// evenly (71.02 / 42.30 = 1.6789598...) is stored unrounded so the stored pair
/// never drifts: `volumeL x unitPrice` re-rounds to the typed total, and
/// re-deriving from any two of the three reproduces the third. Display rounding
/// happens in the UI, never here.
public enum ManualFillUpMath {

    /// The three numbers on the pump card.
    public enum Field: String, Sendable, CaseIterable {
        case total
        case volume
        case unitPrice
    }

    /// The typed (or missing) values. `volumeL` is ALWAYS litres - the vehicle's
    /// display unit is converted before this is called and the result is stored
    /// in litres regardless of how the vehicle displays volume.
    public struct Fields: Equatable, Sendable {
        /// Total money in the entry's original currency.
        public var total: Decimal?
        /// Volume in litres.
        public var volumeL: Double?
        /// Price per litre in the entry's original currency.
        public var unitPrice: Decimal?

        public init(total: Decimal? = nil, volumeL: Double? = nil, unitPrice: Decimal? = nil) {
            self.total = total
            self.volumeL = volumeL
            self.unitPrice = unitPrice
        }

        /// How many of the three values are present (0-3).
        public var typedCount: Int {
            var count = 0
            if total != nil { count += 1 }
            if volumeL != nil { count += 1 }
            if unitPrice != nil { count += 1 }
            return count
        }
    }

    /// The fully-specified triple plus the cross-check verdict written on save.
    public struct Derived: Equatable, Sendable {
        public var total: Decimal
        public var volumeL: Double
        public var unitPrice: Decimal
        public var crossCheck: CrossCheckState
    }

    /// Derives the third value from the other two. Returns `nil` when fewer than
    /// two values are present (the artboard's "Enter total and liters to save"
    /// state). With exactly two typed values the third derives at full precision
    /// and `crossCheck = .notApplicable`; with all three the cross-check applies.
    public static func derive(from fields: Fields) -> Derived? {
        switch fields.typedCount {
        case 0, 1: return nil
        case 2: return deriveThird(fields)
        default: return crossChecked(fields)
        }
    }

    // MARK: - Volume unit conversion

    /// Litres per unit of a volume unit (docs/SCHEMA.md: `volumeL` is always
    /// stored in litres regardless of the vehicle's display unit).
    public static func litresPerUnit(_ unit: VolumeUnit) -> Double {
        switch unit {
        case .l: return 1.0
        case .galUS: return 3.785411784
        case .galUK: return 4.54609
        }
    }

    /// Converts a typed display volume (e.g. 10 gal) into litres for storage.
    public static func volumeL(from display: Double, unit: VolumeUnit) -> Double {
        display * litresPerUnit(unit)
    }

    /// Converts a litre value back into the vehicle's display unit.
    public static func displayVolume(from litres: Double, unit: VolumeUnit) -> Double {
        litres / litresPerUnit(unit)
    }

    // MARK: - Private

    private static func deriveThird(_ fields: Fields) -> Derived? {
        switch (fields.total, fields.volumeL, fields.unitPrice) {
        case (let total?, let volumeL?, nil):
            // total + volume -> price per litre, at full precision.
            return Derived(total: total, volumeL: volumeL,
                           unitPrice: total / Decimal(volumeL),
                           crossCheck: .notApplicable)
        case (let total?, nil, let unitPrice?):
            // total + price -> volume, in litres.
            let volume = total / unitPrice
            return Derived(total: total, volumeL: double(volume),
                           unitPrice: unitPrice, crossCheck: .notApplicable)
        case (nil, let volumeL?, let unitPrice?):
            // volume + price -> total.
            let total = Decimal(volumeL) * unitPrice
            return Derived(total: total, volumeL: volumeL,
                           unitPrice: unitPrice, crossCheck: .notApplicable)
        default:
            return nil
        }
    }

    private static func crossChecked(_ fields: Fields) -> Derived? {
        guard let total = fields.total, let volumeL = fields.volumeL, let unitPrice = fields.unitPrice else {
            return nil
        }
        return Derived(total: total, volumeL: volumeL, unitPrice: unitPrice,
                       crossCheck: TimelineValidator.crossCheck(volumeL: volumeL,
                                                                unitPrice: unitPrice,
                                                                amount: total))
    }

    private static func double(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}
