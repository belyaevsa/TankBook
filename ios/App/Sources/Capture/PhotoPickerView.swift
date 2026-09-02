import PhotosUI
import SwiftUI

/// `PHPickerViewController` wrapper for the Photos action (docs/JOURNEYS.md
/// J6 and the F8 denied-state next step). P2.1 only holds the picked image -
/// parsing the receipt is P2.2. Runs out of process, so it needs no photo
/// library permission of its own.
struct PhotoPickerView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onPick: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = 1
        configuration.filter = .images
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, onPick: onPick)
    }

    @MainActor
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let isPresented: Binding<Bool>
        private let onPick: (UIImage?) -> Void

        init(isPresented: Binding<Bool>, onPick: @escaping (UIImage?) -> Void) {
            self.isPresented = isPresented
            self.onPick = onPick
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            isPresented.wrappedValue = false
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else { return }

            // The Coordinator is kept ALIVE across the load. Setting isPresented above
            // dismisses the sheet, which tears down the representable and
            // releases this Coordinator - so a `[weak self]` here is very often
            // already nil by the time the load finishes, and the pick is
            // silently dropped. That shipped: on a real device, choosing a photo
            // from the library did nothing at all and the app stayed on capture.
            //
            // It is a RACE, which is why it survived review and the simulator: a
            // small local image can finish before the teardown, while an iCloud
            // photo that has to be downloaded never does. Holding a strong
            // reference makes the outcome independent of how long the load takes,
            // and there is no cycle: the closure is released once it runs.
            // The load completes on its own queue; the result is handed to the
            // main actor through a Sendable box. The image is freshly created
            // by the load and owned by no one else, so the hand-off is safe.
            // `self` is captured STRONGLY - a @MainActor class is Sendable, and
            // holding it for the duration of the load is the whole point.
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                let box = PickedImage(image: object as? UIImage)
                Task { @MainActor in
                    self.onPick(box.image)
                }
            }
        }
    }
}

/// `UIImage` is not Sendable; this box is the deliberate, documented exception
/// for an image created exclusively by the picker load and handed to the main
/// actor for storage (P2.1 holds the image; P2.2 parses it).
private struct PickedImage: @unchecked Sendable {
    let image: UIImage?
}
