import SwiftUI
import UIKit

/// A system share sheet (`UIActivityViewController`) as a SwiftUI sheet - the
/// vehicle-export hand-off and the "send us the file" affordance. UIKit is used
/// because sharing a directory of files needs the activity controller's file
/// support; `ShareLink` covers single items only.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
