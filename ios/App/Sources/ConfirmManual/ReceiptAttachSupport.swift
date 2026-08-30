import SwiftUI
import UIKit
import TankbookCore

// MARK: - PJ.48 the shared attach seam

// The pieces both surfaces of "attach a receipt to a typed entry" reuse: the
// photo write (the same `VehiclePhotoStore` pool PJ.2's scan save uses - never
// a second photo-writing path), the single-shot camera door, and the
// blank-fields-only apply. The RULE itself - which fields are blank - lives in
// core (`ReceiptAttachMerge`); these are the app-side hands that call it.

/// Writes a freshly-attached receipt photo into the shared attachments pool and
/// builds the `Attachment` row to upsert. Reuses `VehiclePhotoStore.save` (the
/// exact seam `ManualFillUpView.writeReceiptAttachment` uses) so there is one
/// photo-writing path, never two (docs/SYNC.md -> Attachments: one blob pool).
enum ReceiptAttachmentWriter {
    static func write(id: AttachmentID, image: UIImage, ocrLines: [OCRLine],
                      extraction: FuelExtraction) throws -> Attachment {
        guard let jpeg = image.jpegData(compressionQuality: 0.8) else {
            throw ReceiptAttachmentError.notEncodable
        }
        let (sha256, relativePath) = try VehiclePhotoStore.save(jpeg, id: id)
        let thumbnail = (try? AttachmentRendition.thumbnailBase64(for: jpeg, kind: .photo)) ?? nil
        let ocrText = ocrLines.isEmpty ? nil : ocrLines.map(\.text).joined(separator: "\n")
        let timestamp = extraction.date.flatMap { ConfirmDate.parse($0) }
        let now = Date()
        return Attachment(
            id: id, createdAt: now, updatedAt: now, deletedAt: nil,
            kind: .photo, file: LocalFileRef(sha256: sha256, relativePath: relativePath),
            extractedTimestamp: timestamp, ocrText: ocrText, thumbnailBase64: thumbnail)
    }
}

/// The camera half of the "Add receipt" source picker: a single-shot
/// `UIImagePickerController` with the `.camera` source. The Photos half reuses
/// the existing `PhotoPickerView`. Callers offer the camera button only when
/// `isAvailable` is true - the simulator has none, and a dead camera button is
/// the "never a dead end" violation hard rule 15 names.
struct ReceiptCameraPicker: UIViewControllerRepresentable {
    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var onPick: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate,
                             UINavigationControllerDelegate {
        private let onPick: (UIImage?) -> Void
        init(onPick: @escaping (UIImage?) -> Void) { self.onPick = onPick }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onPick(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onPick(nil)
        }
    }
}

/// The shared "camera or Photos" source choice for attaching a receipt. Wraps
/// the confirmation dialog and its two pickers (Photos -> `PhotoPickerView`,
/// camera -> `ReceiptCameraPicker`) so the Edit-entry and typed-Confirm sheets
/// share one door instead of each forking its own.
private struct ReceiptAttachSourceModifier: ViewModifier {
    @Binding var isPresented: Bool
    let title: LocalizedStringKey
    let onImage: (UIImage) -> Void

    @State private var showPhotoPicker = false
    @State private var showCamera = false

    func body(content: Content) -> some View {
        content
            .confirmationDialog(title, isPresented: $isPresented, titleVisibility: .visible) {
                if ReceiptCameraPicker.isAvailable {
                    Button("Camera") { showCamera = true }
                }
                Button("Photos") {
                    if let fixture = ReceiptAttachFixture.image() {
                        onImage(fixture)
                    } else {
                        showPhotoPicker = true
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showPhotoPicker) {
                PhotoPickerView(isPresented: $showPhotoPicker) { image in
                    if let image { onImage(image) }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                ReceiptCameraPicker { image in
                    showCamera = false
                    if let image { onImage(image) }
                }
            }
    }
}

extension View {
    /// Presents the "Add receipt" / "Attach receipt" source choice and hands
    /// the picked image to `onImage`. `title` names the dialog per surface.
    func receiptAttachSource(isPresented: Binding<Bool>, title: LocalizedStringKey,
                             onImage: @escaping (UIImage) -> Void) -> some View {
        modifier(ReceiptAttachSourceModifier(isPresented: isPresented, title: title, onImage: onImage))
    }
}

/// The `-attachReceiptFixtureImage <path>` test double. The out-of-process
/// Photos picker cannot be driven from XCUITest, so a UI test (or a screenshot
/// run) passes a host-path fixture image that the "Photos" button resolves to
/// directly - the same pattern `CaptureView` uses for the scan door. Production
/// never passes the argument.
enum ReceiptAttachFixture {
    static func image() -> UIImage? {
        guard let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-attachReceiptFixtureImage"),
              ProcessInfo.processInfo.arguments.indices.contains(index + 1) else { return nil }
        return UIImage(contentsOfFile: ProcessInfo.processInfo.arguments[index + 1])
    }
}

// MARK: - Applying the suggestions to the form

extension ManualFillUpFormState {
    /// PJ.48: applies an attached receipt's OCR to the fields `ReceiptAttachMerge`
    /// declared blank. The three pump-card numbers land dimmed until confirmed
    /// (hard rule 13) - exactly like the scan path's own pre-fill - and currency
    /// applies directly, as it does on the scan path. A field the merge did NOT
    /// return is a typed value and is never touched.
    mutating func applyAttachedSuggestions(_ suggestions: Set<FieldRef>,
                                           extraction: FuelExtraction) {
        for ref in suggestions {
            switch ref {
            case .total:
                if let total = extraction.total {
                    self.total = ConfirmFormat.string(decimal: total, fractionDigits: 2)
                    resolvedByExtraction.insert(.total)
                }
            case .unitPrice:
                if let price = extraction.unitPrice {
                    self.pricePerL = ConfirmFormat.string(decimal: price, fractionDigits: 3)
                    resolvedByExtraction.insert(.unitPrice)
                }
            case .currency:
                if let currency = extraction.currency {
                    self.currency = currency
                }
            default:
                break
            }
        }
    }

    /// A `FillUp` whose nil fields name exactly which form fields are blank -
    /// the input `ReceiptAttachMerge.suggestions` expects. `money` is nil when
    /// no total has been typed (so total and currency are blank) and `unitPrice`
    /// is nil when no price has been typed. `volumeL` is irrelevant to the merge
    /// (a `FillUp` never treats volume as blank), so zero stands in.
    func blankDetectingEntry(vehicle: Vehicle) -> FillUp {
        let now = Date()
        let money = totalDecimal.map { Money(amount: $0, currency: currency,
                                             homeCurrency: vehicle.homeCurrency) }
        return FillUp(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: date, odometer: odometerValue,
            money: money, note: nil, attachments: [], provenance: .manual,
            conflict: .none, purchaseGroupId: nil, volumeL: 0,
            unitPrice: pricePerLDecimal, fuelKind: fuelKind, fuelGrade: nil,
            isFull: isFull, tankLevelAfterPct: tankLevelAfterPct, stationId: nil,
            crossCheck: .notApplicable, extraction: nil)
    }
}
