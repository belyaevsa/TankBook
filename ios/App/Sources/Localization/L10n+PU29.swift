import Foundation

// PU.29: the pump-display alpha notice on the Confirm sheet (decision 7,
// docs/EXTRACTION.md -> "The pump reader").
extension L10n {
    /// Shown beside a reading taken from a pump display while the build is
    /// below the pump-photo gate. Names the next step (hard rule 7): check
    /// every field.
    static var pumpDisplayAlphaMessage: String {
        localize("Read from the pump display – this is in alpha. Check every field before saving.")
    }
}
