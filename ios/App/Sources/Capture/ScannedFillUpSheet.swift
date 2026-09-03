import SwiftUI
import TankbookCore
import UIKit

// MARK: - PJ.1 the scanned Confirm sheet

/// What the capture screen can present over the camera. One enum drives one
/// `.sheet` modifier (two `.sheet` modifiers on one view is a known SwiftUI
/// pitfall - only the last one is honoured).
///
/// PJ.6: the manual form carries the mode's entry form so "Type it" opens the
/// form for the mode the user selected (`CaptureMode.manualEntryForm`), not a
/// fill-up form in Service mode. The form is part of the identity so a Service
/// "Type it" cannot be confused with a Fill-up one.
enum CaptureSheet: Identifiable {
    case manualForm(CaptureEntryForm)
    case photoPicker
    case documentCamera
    case scanned(ConfirmPrefill)

    var id: String {
        switch self {
        case .manualForm(let form): return "manualForm_" + form.rawValue
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
    /// RV.12: what the capture screen wants done once the entry is safely
    /// written - tear the capture modal down, so Save does not uncover the
    /// camera. Opt-in from the presenter; the sheet itself knows nothing about
    /// tabs or covers. Never called for a cancel or a save that threw.
    var onSaved: () -> Void = {}
    @State private var hasUnsavedChanges = false

    var body: some View {
        DiscardAwareSheet(policy: .askBeforeDiscarding, hasUnsavedChanges: $hasUnsavedChanges) {
            ManualFillUpView(prefill: prefill,
                             hasUnsavedChanges: $hasUnsavedChanges,
                             onSaved: onSaved)
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

// MARK: - PJ.6: the mode's entry form -> the sheet to present

extension CaptureEntryForm {
    /// The `SheetRoute` that renders this form, resolved so the capture screen
    /// does not need a per-mode switch at either "Type it" call site. The
    /// mode -> form half of the mapping lives in core
    /// (`CaptureMode.manualEntryForm`, unit-pinned); this is only the
    /// presentation half, and every case is handled explicitly - dropping one
    /// fails the compile, it cannot silently fall through.
    var sheetRoute: SheetRoute {
        switch self {
        case .fillUp: return .confirmManual
        case .service: return .serviceEntry
        case .expense: return .expenseEntry
        }
    }
}
