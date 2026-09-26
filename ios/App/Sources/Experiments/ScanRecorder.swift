#if EXPERIMENTS
import Foundation
import TankbookCore
import UIKit

/// Keeps each capture's photo, record and pump trace in `ScanHistory` so a
/// debug case the tester chooses to send (About -> Experiments -> Send
/// diagnostics) carries what the pipeline saw. Compiled into builds that carry
/// experiments only; the store build records nothing.
enum ScanRecorder {
    static let history = ScanHistory.standard()

    /// A `UIImage` is safe to encode off the main actor; the box carries it there.
    private struct ImageBox: @unchecked Sendable {
        let image: UIImage
    }

    /// Records one capture off the main actor, so the entry opens without
    /// waiting on the JPEG encode.
    static func record(image: UIImage, prefill: ConfirmPrefill, requestedSource: ExtractionSource?,
                       resolvedSource: ExtractionSource, detection: PumpDisplayCapture.Detection?, trace: Data?) {
        guard let history else { return }
        let box = ImageBox(image: image)
        let capturedAt = Date()
        let extraction = prefill.extraction ?? FuelExtraction()
        let lines = prefill.ocrLines
        let provenance = "\(prefill.provenance)"
        let durationMs = prefill.pipelineDurationMs ?? 0
        let rotation = prefill.provenance == .pumpPhoto ? prefill.displayRotationCW : nil
        let build = Bundle.main.object(forInfoDictionaryKey: "TankbookBuildCommit") as? String
        Task.detached(priority: .utility) {
            guard let jpeg = box.image.jpegData(compressionQuality: 0.9) else { return }
            var record = ScanRecord(capturedAt: capturedAt, requestedSource: requestedSource,
                                    resolvedSource: resolvedSource, provenance: provenance,
                                    durationMs: durationMs, extraction: extraction)
            record.ocrLines = lines
            record.detection = detection
            record.pumpRotationCW = rotation
            record.build = build
            history.record(photo: jpeg, record: record.data, trace: trace, at: capturedAt)
        }
    }
}
#endif
