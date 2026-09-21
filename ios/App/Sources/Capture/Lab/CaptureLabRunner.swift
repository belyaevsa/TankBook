#if DEBUG
import CoreGraphics
import Foundation
import SwiftUI
import TankbookCore
import UIKit

/// PU.39 - the run model behind `CaptureLabView`. One press shoots every
/// selected preset back to back on the same scene, times each apply → capture →
/// deliver, keeps the camera's own bytes, scores each through the production
/// pipeline and writes `Documents/CaptureLab/<session>/`.
@MainActor
@Observable
final class CaptureLabRunner {
    /// Which pipeline scores the shot. Pump classifies first, exactly as a real
    /// capture; receipt forces the receipt path.
    var source: CaptureLabSource = .pump
    /// All presets on by default; the control is always measured unless the
    /// owner unchecks it.
    var selected: Set<CaptureLabPreset> = Set(CaptureLabPreset.allCases)

    private(set) var isRunning = false
    private(set) var progress = 0
    private(set) var total = 0
    private(set) var results: [CaptureLabResult] = []
    /// The session folder once the run wrote it - the Share button's payload.
    private(set) var sessionDirectory: URL?
    /// A next step when the run cannot proceed (no camera, no preset). Never a
    /// crash.
    private(set) var message: LocalizedStringKey?

    private let store: CaptureLabLogStore

    init(store: CaptureLabLogStore = CaptureLabLogStore(root: CaptureLabLogStore.defaultRoot)) {
        self.store = store
    }

    var canRun: Bool { !isRunning && !selected.isEmpty }

    /// The presets in catalogue order, selected only.
    var runPresets: [CaptureLabPreset] {
        CaptureLabPreset.allCases.filter { selected.contains($0) }
    }

    /// Shoots every selected preset and writes the session. The caller owns the
    /// `CameraController` (the same session the preview shows), so a captured
    /// frame is the frame the preview was showing.
    func run(controller: CameraController) async {
        guard !isRunning else { return }
        let presets = runPresets
        guard !presets.isEmpty else {
            message = "Choose at least one preset."
            return
        }
        isRunning = true
        message = nil
        results = []
        progress = 0
        total = presets.count
        sessionDirectory = nil

        var directory: URL?
        do {
            directory = try store.makeSessionDirectory()
        } catch {
            message = "Could not create the session folder."
        }

        var collected: [CaptureLabResult] = []
        for preset in presets {
            guard let result = await shoot(preset, controller: controller, directory: directory) else {
                message = "The camera is not available."
                break
            }
            collected.append(result)
            results = collected
            progress += 1
        }

        if let directory, !collected.isEmpty {
            let log = CaptureLabRunLog(
                startedAt: CaptureLabLogStore.sessionName(for: Date()),
                source: source.rawValue,
                device: Self.deviceModel,
                results: collected)
            if (try? store.write(log, to: directory)) != nil {
                sessionDirectory = directory
            }
        }
        isRunning = false
    }

    /// One preset's apply → capture → deliver, timed, with the camera's bytes
    /// written and the frame scored. nil when no camera delivered a frame.
    private func shoot(_ preset: CaptureLabPreset, controller: CameraController,
                       directory: URL?) async -> CaptureLabResult? {
        let plan = preset.plan(capabilities: controller.labCapabilities)
        let startedAt = Date()
        await controller.applyLabPlan(plan)
        guard let frame = await controller.captureLabFrame(plan) else { return nil }
        let captureMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        if let directory {
            try? CaptureLabLogStore.writePhoto(frame.data, preset: preset, to: directory)
        }
        let scored = await Self.score(frame.image, source: source)
        return CaptureLabResult(
            preset: preset.id,
            applied: plan.applied,
            captureMs: captureMs,
            bytes: frame.data.count,
            width: frame.pixelWidth,
            height: frame.pixelHeight,
            exif: Self.exif(from: frame.metadata),
            classifyPath: scored.classifyPath,
            isDisplay: scored.isDisplay,
            rows: scored.rows,
            textLines: scored.textLines,
            committed: scored.committed,
            pipelineMs: scored.pipelineMs,
            resolvedFields: scored.resolvedFields,
            crossCheck: scored.crossCheck)
    }

    // MARK: - Scoring

    /// What the reader made of one frame. Intermediate to `CaptureLabResult` so
    /// the camera/EXIF half and the reader half stay separate.
    struct Score {
        var classifyPath: String?
        var isDisplay: Bool
        var rows: Int
        var textLines: Int
        var committed: CaptureLabCommitted
        var pipelineMs: Int
        var resolvedFields: Int?
        var crossCheck: String?
    }

    /// The production path decides: `CapturePipeline.process` with `source` nil
    /// for pump (the classification runs) and `.receipt` for receipts. The
    /// classification's own path, row count and text-line count come from the
    /// same reader (`PumpDisplayCapture.detect`) so the table can name what the
    /// classifier counted; the committed values come from `process`.
    private static func score(_ image: UIImage, source: CaptureLabSource) async -> Score {
        var classifyPath: String?
        var isDisplay = false
        var rows = 0
        var textLines = 0
        if source == .pump, let detection = await detect(image) {
            classifyPath = detection.path.rawValue
            isDisplay = detection.isPumpDisplay
            rows = detection.displayRows
            textLines = detection.textLines
        }
        let prefill = await CapturePipeline.process(image, source: source.extractionSource)
        let extraction = prefill.extraction
        return Score(
            classifyPath: classifyPath,
            isDisplay: isDisplay,
            rows: rows,
            textLines: textLines,
            committed: CaptureLabCommitted(liters: extraction?.liters,
                                           unitPrice: extraction?.unitPrice,
                                           total: extraction?.total),
            pipelineMs: prefill.pipelineDurationMs ?? 0,
            resolvedFields: source == .receipt ? extraction.map(resolvedCount) : nil,
            crossCheck: source == .receipt ? extraction.map { describe($0.crossCheck) } : nil)
    }

    /// The reader's classification of one frame, off the main actor (the
    /// locator and detector are CPU-bound). nil when the models are missing.
    private static func detect(_ image: UIImage) async -> PumpDisplayCapture.Detection? {
        guard let reader = CapturePipeline.pumpReader, let upright = uprightCGImage(of: image) else {
            return nil
        }
        let box = LabImageBox(image: upright)
        return await Task.detached(priority: .userInitiated) {
            PumpDisplayCapture.detect(image: box.image, reader: reader)
        }.value
    }

    /// The frame with its orientation baked in, which the pump reader's
    /// geometry needs (it takes no orientation of its own).
    private static func uprightCGImage(of image: UIImage) -> CGImage? {
        if image.imageOrientation == .up { return image.cgImage }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }.cgImage
    }

    /// How many of a receipt's fields resolved. `crossCheck` and `digitRepair`
    /// are verdicts, not values read off the paper, so they do not count.
    private static func resolvedCount(_ extraction: FuelExtraction) -> Int {
        [extraction.liters != nil, extraction.unitPrice != nil, extraction.total != nil,
         extraction.currency != nil, extraction.fuelKind != nil, extraction.date != nil]
            .filter { $0 }.count
    }

    /// The cross-check state as a stable token for the table and the log.
    private static func describe(_ crossCheck: ExtractionCrossCheck) -> String {
        switch crossCheck {
        case .lock: return "lock"
        case .reconciled: return "reconciled"
        case .mixed: return "mixed"
        case .mismatch: return "mismatch"
        case .notApplicable: return "notApplicable"
        }
    }

    // MARK: - EXIF

    /// Exposure time, ISO and focal length from `photo.metadata`, when present.
    /// The simulator's test frame carries none, so this is nil there.
    static func exif(from metadata: [String: Any]) -> CaptureLabExif? {
        guard let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] else {
            return nil
        }
        let exposure = exif[kCGImagePropertyExifExposureTime as String] as? Double
        let focal = exif[kCGImagePropertyExifFocalLength as String] as? Double
        let iso = (exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Int])?.first.map(Double.init)
        guard exposure != nil || focal != nil || iso != nil else { return nil }
        return CaptureLabExif(exposureTime: exposure, iso: iso, focalLength: focal)
    }

    private static var deviceModel: String {
        var system = utsname()
        uname(&system)
        let capacity = MemoryLayout.size(ofValue: system.machine)
        let identifier = withUnsafePointer(to: &system.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) {
                String(cString: $0)
            }
        }
        return identifier.isEmpty ? "unknown" : identifier
    }
}

/// `CGImage` is not Sendable; this box is the documented exception for a frame
/// created only to classify and handed across to a detached task - the same
/// pattern `CapturePipeline` uses.
private struct LabImageBox: @unchecked Sendable {
    let image: CGImage
}
#endif
