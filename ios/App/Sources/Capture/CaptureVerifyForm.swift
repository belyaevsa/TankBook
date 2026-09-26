import Foundation
import TankbookCore

/// The capture verify screen's three numbers, in the car's display units -
/// the same texts Confirm's fields hold, so what the user checks against the
/// photo is exactly what Confirm opens with.
///
/// Recognition arrives after the photo does. It fills a field only while the
/// user has not typed in it: a value the user entered is theirs, and a late
/// recognition never replaces it (hard rule 13).
struct CaptureVerifyForm: Equatable {
    var total = ""
    var volume = ""
    var unitPrice = ""
    private(set) var edited: Set<ManualFillUpMath.Field> = []

    /// A user edit: the field is the user's from here on.
    mutating func set(_ field: ManualFillUpMath.Field, to text: String) {
        edited.insert(field)
        switch field {
        case .total: total = text
        case .volume: volume = text
        case .unitPrice: unitPrice = text
        }
    }

    func text(_ field: ManualFillUpMath.Field) -> String {
        switch field {
        case .total: total
        case .volume: volume
        case .unitPrice: unitPrice
        }
    }

    /// Fills each field the user has not typed in from the recognition. The
    /// total is the one Confirm would show: the fiscal QR's where it outranks
    /// the text, the fuel line on a mixed receipt (hard rule 4).
    mutating func applyRecognition(_ prefill: ConfirmPrefill, volumeUnit: VolumeUnit) {
        guard let extraction = prefill.extraction else { return }
        if !edited.contains(.total), let value = Self.recognizedTotal(extraction, qrAnchor: prefill.qrAnchor) {
            total = ConfirmFormat.string(decimal: value, fractionDigits: 2)
        }
        if !edited.contains(.volume), let liters = extraction.liters {
            volume = ManualFillUpFormState.prefillVolumeText(liters: liters, unit: volumeUnit)
        }
        if !edited.contains(.unitPrice), let price = extraction.unitPrice {
            unitPrice = ManualFillUpFormState.prefillUnitPriceText(perLitre: price, unit: volumeUnit)
        }
    }

    static func recognizedTotal(_ extraction: FuelExtraction, qrAnchor: FiscalQRAnchor?) -> Decimal? {
        switch ConfirmQRTotal.resolve(extraction: extraction, qrAnchor: qrAnchor) {
        case .noAnchor(let total): total
        case .ocrConfirmed(let total), .qrAuthoritative(let total), .fuelLineStands(let total): total
        }
    }

    /// Whether the three numbers on the screen multiply up, by the same
    /// arithmetic Confirm uses; nil while fewer than two are filled.
    func crossCheck(volumeUnit: VolumeUnit) -> CrossCheckState? {
        var state = ManualFillUpFormState()
        state.total = total
        state.liters = volume
        state.pricePerL = unitPrice
        return state.derived(volumeUnit: volumeUnit)?.crossCheck
    }

    var numbers: CaptureVerifiedNumbers {
        CaptureVerifiedNumbers(total: total, volume: volume, unitPrice: unitPrice)
    }
}
