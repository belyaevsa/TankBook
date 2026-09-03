import SwiftUI
import UIKit

/// A system share sheet (`UIActivityViewController`) as a SwiftUI sheet - the
/// vehicle-export hand-off and the "send us the file" affordance. UIKit is used
/// because sharing a directory of files needs the activity controller's file
/// support; `ShareLink` covers single items only.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    /// The share's outcome, called exactly once when the sheet settles:
    /// `completed == true` when the user chose an activity and it finished,
    /// `false` when they dismissed without one. The caller uses it to log shape
    /// only (RV.17); nil when no caller cares.
    var completion: ((Bool) -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            completion?(completed)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
