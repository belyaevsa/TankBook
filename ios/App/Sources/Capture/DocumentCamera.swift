import SwiftUI
import UIKit
import VisionKit

/// The system multi-page document scanner (VNDocumentCameraViewController),
/// wrapped for SwiftUI. This is the scanner J7 names for invoices ("document
/// camera, multi-page") - the system builds the page-stitching UI, we do not.
/// iOS 13+, so no availability guard is needed against the 18.0 floor.
struct DocumentCamera: UIViewControllerRepresentable {
    var onCancel: @MainActor @Sendable () -> Void
    var onResult: @MainActor @Sendable ([UIImage]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCancel: onCancel, onResult: onResult)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController,
                                context: Context) {}

    /// **Not** `@MainActor`, unlike `PhotoPickerView.Coordinator`, and the
    /// difference is forced rather than chosen: `PHPickerViewControllerDelegate`
    /// is main-actor isolated in the SDK, and `VNDocumentCameraViewControllerDelegate`
    /// is not - marking this class `@MainActor` fails with "conformance ...
    /// crosses into main actor-isolated code".
    ///
    /// So the callbacks stay nonisolated and hop to the main actor carrying
    /// **only `Sendable` values**: the closures are copied into locals first
    /// (referencing a stored property would capture `self`, which is the
    /// "Sending 'self' risks causing data races" error), and the pages travel in
    /// the same kind of documented box `PhotoPickerView` uses.
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onCancel: @MainActor @Sendable () -> Void
        private let onResult: @MainActor @Sendable ([UIImage]) -> Void

        init(onCancel: @escaping @MainActor @Sendable () -> Void,
             onResult: @escaping @MainActor @Sendable ([UIImage]) -> Void) {
            self.onCancel = onCancel
            self.onResult = onResult
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            let pages = ScannedPages(images: (0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
            let handler = onResult
            Task { @MainActor in handler(pages.images) }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            let handler = onCancel
            Task { @MainActor in handler() }
        }

        /// A failed scan degrades to the ordinary typed form, which is already
        /// on screen behind the scanner - the manual path is a peer, never an
        /// error state (hard rule 15).
        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            let handler = onCancel
            Task { @MainActor in handler() }
        }
    }
}

/// `UIImage` is not Sendable; this box is the same deliberate, documented
/// exception `PhotoPickerView.PickedImage` makes, for images created
/// exclusively by the scan and handed to the main actor for storage.
private struct ScannedPages: @unchecked Sendable {
    let images: [UIImage]
}
