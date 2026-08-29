import SwiftUI
import TankbookCore
import UIKit

// MARK: - PJ.1 the scanned Confirm sheet

/// What the capture screen can present over the camera. One enum drives one
/// `.sheet` modifier (two `.sheet` modifiers on one view is a known SwiftUI
/// pitfall - only the last one is honoured).
enum CaptureSheet: Identifiable {
    case manualForm
    case photoPicker
    case documentCamera
    case scanned(ConfirmPrefill)

    var id: String {
        switch self {
        case .manualForm: return "manualForm"
        case .photoPicker: return "photoPicker"
        case .documentCamera: return "documentCamera"
        case .scanned: return "scanned"
        }
    }
}

extension CaptureSheet: Equatable {
    /// Two cases are equal when they are the same sheet kind; the scanned
    /// prefill's payload is not compared (it carries a `UIImage`, which is not
    /// `Equatable`). The only comparison in use is `activeSheet == .photoPicker`.
    static func == (lhs: CaptureSheet, rhs: CaptureSheet) -> Bool {
        lhs.id == rhs.id
    }
}

/// The Confirm sheet the capture pipeline lands in: the existing
/// `ManualFillUpView`, now carrying the `ConfirmPrefill` the scan produced.
/// A nil extraction inside the prefill IS the ordinary manual form (hard rule
/// 15), so this wrapper is used for every scan - resolved or not - and never
/// presents an error state.
struct ScannedFillUpSheet: View {
    let prefill: ConfirmPrefill
    @State private var hasUnsavedChanges = false

    var body: some View {
        DiscardAwareSheet(policy: .askBeforeDiscarding, hasUnsavedChanges: $hasUnsavedChanges) {
            ManualFillUpView(prefill: prefill, hasUnsavedChanges: $hasUnsavedChanges)
                .navigationTitle("Manual fill-up")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

extension Array where Element == String {
    /// The `-captureFixtureImage <path>` override, if present. Lets a UI test
    /// drive the capture pipeline from a host-path image on a simulator that has
    /// no camera. Production never passes the argument.
    var captureFixtureImagePath: String? {
        guard let index = firstIndex(of: "-captureFixtureImage"), index + 1 < count else { return nil }
        return self[index + 1]
    }
}
