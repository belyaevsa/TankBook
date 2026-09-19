import Foundation

// MARK: - The reading's own arithmetic (RV.288)

/// A fuel reading's three numbers with a zero read as nil: a display or a
/// receipt never prints a zero volume, price or total for a fill that
/// happened, so `0.00` is a field the model could not read, never a value to
/// offer (docs/EXTRACTION.md -> The four cross-check outcomes, the inbox as
/// the fourth consumer).
struct FuelReadingNumbers {
    let volume: Double?
    let unitPrice: Decimal?
    let total: Decimal?

    init(_ extraction: GatewayExtraction) {
        volume = extraction.volume.map(\.value).flatMap { $0 > 0 ? $0 : nil }
        unitPrice = extraction.unitPrice.map(\.value).flatMap { $0 > 0 ? $0 : nil }
        total = extraction.total.map(\.value).flatMap { $0 > 0 ? $0 : nil }
    }

    var presentCount: Int {
        [volume != nil, unitPrice != nil, total != nil].filter { $0 }.count
    }
}

extension GatewayInboxPolicy {
    /// Whether the reading's numbers may be offered at all: the same
    /// `TimelineValidator.crossCheck` a tick runs afterwards, run BEFORE the
    /// offer. Three numbers that cannot coexist (0.56 L x 1.954 = 0.00) are
    /// not three plausible corrections but one bad read, and offering them
    /// independently is how a self-contradicting reading reached the card as
    /// three separate "the receipt says" rows. Two numbers are checked against
    /// the user's third; one number alone has nothing to fail against.
    public static func fuelNumbersAddUp(_ extraction: GatewayExtraction, _ entry: FillUp) -> Bool {
        let read = FuelReadingNumbers(extraction)
        guard read.presentCount >= 2 else { return true }
        let volume = read.volume ?? entry.volumeL
        guard let unitPrice = read.unitPrice ?? entry.unitPrice,
              let total = read.total ?? entry.money?.amount else { return true }
        return TimelineValidator.crossCheck(volumeL: volume, unitPrice: unitPrice, amount: total) == .verified
    }
}
