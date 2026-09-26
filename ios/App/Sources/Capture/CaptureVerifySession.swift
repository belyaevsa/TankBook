import Observation
import SwiftUI
import TankbookCore
import UIKit

/// One capture on the verify screen: the photo, the recognition running behind
/// it, and the three numbers the user checks. The photo is shown the moment it
/// exists; recognition starts at once and fills the fields when it returns, so
/// the user can already type (and a re-take costs only the recognition it
/// cancels).
@MainActor
@Observable
final class CaptureVerifySession: Identifiable {
    let id = UUID()
    let image: UIImage
    let volumeUnit: VolumeUnit
    private(set) var prefill: ConfirmPrefill?
    private(set) var reading = true
    var form = CaptureVerifyForm()
    /// Quarter turns the user added with the rotate control.
    var userTurns = 0
    /// Continue was tapped while recognition was still running: the session
    /// goes on the moment it returns, so the reading is never thrown away.
    private(set) var continuePending = false
    private var onReady: (() -> Void)?
    private var task: Task<Void, Never>?

    init(image: UIImage, volumeUnit: VolumeUnit) {
        self.image = image
        self.volumeUnit = volumeUnit
    }

    /// Runs `recognize` once and applies its answer to the fields the user has
    /// not typed in.
    func start(_ recognize: @escaping @MainActor () async -> ConfirmPrefill) {
        guard task == nil else { return }
        task = Task {
            let result = await recognize()
            guard !Task.isCancelled else { return }
            prefill = result
            form.applyRecognition(result, volumeUnit: volumeUnit)
            reading = false
            onReady?()
            onReady = nil
        }
    }

    /// Runs `action` once recognition has returned - at once when it already
    /// has.
    func afterRecognition(_ action: @escaping () -> Void) {
        guard reading else { return action() }
        continuePending = true
        onReady = action
    }

    func cancel() {
        task?.cancel()
    }

    /// The clockwise rotation the photo is shown at: the turn the pump display
    /// was read at, plus the user's own.
    var rotationDegrees: Double {
        Double(((prefill?.displayRotationCW ?? 0) + userTurns * 90) % 360)
    }

    var notices: [CaptureVerifyNotice] {
        CaptureVerifyNotice.resolve(
            provenance: prefill?.provenance ?? .receiptScan, hasPhoto: true,
            extraction: prefill?.extraction, pumpAlpha: prefill?.pumpAlpha ?? false,
            pumpCaution: prefill?.pumpCaution, crossCheck: form.crossCheck(volumeUnit: volumeUnit),
            reading: reading)
    }

    /// What Confirm opens with: the recognition as it came, the photo, and the
    /// numbers as the user left them here. Before recognition has returned it
    /// is a prefill of the photo and the typed numbers alone.
    func confirmedPrefill() -> ConfirmPrefill {
        var out = prefill ?? ConfirmPrefill(extraction: FuelExtraction(), sourceImage: image)
        if out.sourceImage == nil { out.sourceImage = image }
        out.verified = form.numbers
        return out
    }
}
