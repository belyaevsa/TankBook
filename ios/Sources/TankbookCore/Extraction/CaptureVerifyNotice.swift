import Foundation

/// What the capture verify step says about a recognition, above its fields
/// (docs/ERRORS.md -> Capture verify). The verify screen is where a scan is
/// checked against its photo, so it is where the app admits what it could not
/// read - the entry form that follows no longer repeats it.
public enum CaptureVerifyNotice: Equatable, Sendable {
    /// A pump display none of whose three numbers was read.
    case pumpNothingRead
    /// A receipt (or a frame the app did not take for a display) nothing was read from.
    case nothingRead
    /// A pump reading from a build below the accuracy gate, or with the
    /// owner's flag off: check every field.
    case pumpAlpha
    /// A pump pair whose shown price differs from the price the pair implies.
    case pumpPriceDiffers(shown: Decimal, implied: Decimal)
    /// The three numbers on the screen do not multiply up.
    case numbersDisagree

    /// The notices for one verify screen, most important first. Nothing is
    /// said while recognition is still running (`reading`), and a pump alpha
    /// notice never frames a reading that did not happen.
    public static func resolve(provenance: Provenance, hasPhoto: Bool, extraction: FuelExtraction?,
                               pumpAlpha: Bool, pumpCaution: PumpReadingCaution?,
                               crossCheck: CrossCheckState?, reading: Bool) -> [CaptureVerifyNotice] {
        guard !reading else { return [] }
        if PumpReadFailure.applies(provenance: provenance, extraction: extraction, hasPhoto: hasPhoto) {
            return [.pumpNothingRead]
        }
        let readAny = extraction?.liters != nil || extraction?.unitPrice != nil || extraction?.total != nil
        if hasPhoto, !readAny {
            return [.nothingRead]
        }
        var out: [CaptureVerifyNotice] = []
        if provenance == .pumpPhoto, pumpAlpha { out.append(.pumpAlpha) }
        if case .shownPriceDiffers(let shown, let implied)? = pumpCaution {
            out.append(.pumpPriceDiffers(shown: shown, implied: implied))
        }
        if case .mismatch? = crossCheck { out.append(.numbersDisagree) }
        return out
    }
}
