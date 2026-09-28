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
    /// Returns the folder the scan will be kept in, so the entry it opens can
    /// record its outcome there; nil when there is no history.
    @discardableResult
    static func record(image: UIImage, prefill: ConfirmPrefill, requestedSource: ExtractionSource?,
                       resolvedSource: ExtractionSource, detection: PumpDisplayCapture.Detection?,
                       trace: Data?) -> URL? {
        guard let history else { return nil }
        let box = ImageBox(image: image)
        let capturedAt = Date()
        let extraction = prefill.extraction ?? FuelExtraction()
        let lines = prefill.ocrLines
        let provenance = "\(prefill.provenance)"
        let durationMs = prefill.pipelineDurationMs ?? 0
        let rotation = prefill.provenance == .pumpPhoto ? prefill.displayRotationCW : nil
        let build = Bundle.main.object(forInfoDictionaryKey: "TankbookBuildCommit") as? String
        let kinds = prefill.scanKinds
        let shadow = prefill.scanShadow
        let id = UUID().uuidString
        let folder = history.folder(at: capturedAt, id: id)
        Task.detached(priority: .utility) {
            guard let jpeg = box.image.jpegData(compressionQuality: 0.9) else { return }
            var record = ScanRecord(capturedAt: capturedAt, requestedSource: requestedSource,
                                    resolvedSource: resolvedSource, provenance: provenance,
                                    durationMs: durationMs, extraction: extraction)
            record.ocrLines = lines
            record.detection = detection
            record.pumpRotationCW = rotation
            record.build = build
            record.prefillKinds = kinds.isEmpty ? nil : kinds
            record.shadow = shadow
            history.record(photo: jpeg, record: record.data, trace: trace, at: capturedAt, id: id)
        }
        return folder
    }

    /// Records how a pump scan's entry ended beside the scan (`ScanOutcome`):
    /// saved with what the user did to each pre-filled field, discarded, or
    /// re-taken. A receipt scan, or a prefill with no kept scan, records nothing.
    static func recordOutcome(_ prefill: ConfirmPrefill?, result: ScanOutcome.Result,
                              saved: ScanSavedValues? = nil) {
        guard let history, let prefill, let folder = prefill.scanFolder, !prefill.scanKinds.isEmpty else { return }
        let data = ScanOutcome.data(result: result, at: Date(), kinds: prefill.scanKinds,
                                    prefilled: prefill.extraction ?? FuelExtraction(), saved: saved)
        Task.detached(priority: .utility) { history.recordOutcome(data, in: folder) }
    }
}
#endif
