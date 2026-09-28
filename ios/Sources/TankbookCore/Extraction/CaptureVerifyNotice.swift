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
    /// A pump read the arithmetic checked nothing on, with a field missing:
    /// the numbers shown could not be checked, and the empty one is to type.
    case pumpUnchecked
    /// A photo that reads as a workshop invoice or a shop receipt, not fuel
    /// (`CaptureDocumentHint`): the Service and Expense forms are offered,
    /// the suggested one first. It replaces the "couldn't read" admission -
    /// the document was read, it just is not a fill-up.
    case notFuel(suggested: CaptureEntryForm)

    /// The notices for one verify screen, most important first. Nothing is
    /// said while recognition is still running (`reading`), and a pump alpha
    /// notice never frames a reading that did not happen.
    public static func resolve(provenance: Provenance, hasPhoto: Bool, extraction: FuelExtraction?,
                               pumpAlpha: Bool, pumpCaution: PumpReadingCaution?,
                               crossCheck: CrossCheckState?, reading: Bool,
                               documentHint: CaptureEntryForm? = nil) -> [CaptureVerifyNotice] {
        guard !reading else { return [] }
        if PumpReadFailure.applies(provenance: provenance, extraction: extraction, hasPhoto: hasPhoto) {
            return [.pumpNothingRead]
        }
        if hasPhoto, provenance != .pumpPhoto, let documentHint {
            return [.notFuel(suggested: documentHint)]
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
        // An unclosed pump read with all three numbers is the same warning as a
        // form whose numbers do not multiply up, said once. With a number
        // missing there is nothing to disagree with, only nothing checked.
        if case .mismatch? = crossCheck {
            out.append(.numbersDisagree)
        } else if pumpCaution == .unclosed {
            out.append(extraction?.readsAllThree == true ? .numbersDisagree : .pumpUnchecked)
        }
        return out
    }
}
