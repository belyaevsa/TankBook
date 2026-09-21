import CoreGraphics
import ImageIO
import UIKit
import Vision
import TankbookCore

// MARK: - PJ.1 the app-side capture pipeline shell
//
// This is deliberately a THIN shell. Everything that decides anything lives in
// `TankbookCore.ExtractionAssembler` (L1-testable from `[OCRLine]`); this type
// only does what the brief allows: `UIImage -> CGImage`, calls Vision (OCR +
// QR), and wraps the result in `ConfirmPrefill` with the image attached. If a
// decision needs an app-side test, it has been put in the wrong tier.

enum CapturePipeline {
    /// The recognition languages Vision is pointed at, matching the corpus gate
    /// (receipts arrive in RU/KZ/EE with Latin and Cyrillic text).
    static let languages = ["en-US", "de-DE", "pl-PL", "cs-CZ", "ru-RU"]

    /// The whole path: image in, a `ConfirmPrefill` out. A `UIImage` with no
    /// `CGImage`, or OCR that resolves nothing, produces an all-nil extraction -
    /// which the Confirm sheet renders as the ordinary empty manual form, never
    /// an error and never a dead end (hard rule 15).
    /// The classifier the pump reader runs on and the row detector that finds
    /// its windows (PU.33); loaded once from the bundle's compiled models. A
    /// missing classifier means every frame classifies as a receipt, as before
    /// PU.29; a missing detector leaves the Vision + classical locator alone.
    nonisolated(unsafe) static var pumpReader: PumpReaderHandle? = PumpDisplayCapture.makeReader(
        modelURL: Bundle.main.url(forResource: "PumpSegments", withExtension: "mlmodelc"),
        detectorURL: Bundle.main.url(forResource: "DigitRows", withExtension: "mlmodelc"))

    /// The whole path: image in, a `ConfirmPrefill` out. With `source` nil the
    /// frame is CLASSIFIED first - a pump display (the reader vouches for rows
    /// of seven-segment digits) runs the pump reader and arrives at Confirm as
    /// `.pumpPhoto` with the alpha notice; anything else runs the receipt path.
    /// The same classification runs whether the photo is a first capture or a
    /// later attach / re-attach / replace (PU.29). A `UIImage` with no
    /// `CGImage`, or OCR that resolves nothing, produces an all-nil extraction -
    /// which the Confirm sheet renders as the ordinary empty manual form, never
    /// an error and never a dead end (hard rule 15).
    @MainActor
    static func process(_ image: UIImage, source: ExtractionSource? = nil,
                        bandProvider: (any FuelPriceBandProvider)? = nil) async -> ConfirmPrefill {
        // OB.2: the recognition duration rides the prefill so the
        // `capture.pipeline` line emitted at the confirm commit can carry it.
        // The duration covers OCR + QR + assembly, not the user's editing time.
        let startedAt = Date()
        var assembly: CaptureAssembly
        var lines: [OCRLine] = []
        var resolvedSource = source ?? .receipt
        var pumpReading: PumpDisplayCapture.Reading?
        // Both halves are load-bearing: RV.49's orientation (an in-app photo
        // reaches Vision sideways without it) and RV.48's band provider (the
        // resolution ladder's steps 3 and 4 are dead without it).
        if let cgImage = image.cgImage {
            let box = CGImageBox(image: cgImage, orientation: cgImagePropertyOrientation(of: image))
            if source == nil || source == .pump {
                if let reader = pumpReader, let upright = uprightCGImage(of: image) {
                    let classifyStartedAt = Date()
                    let classified = await readPumpDisplay(UprightBox(image: upright), reader: reader,
                                                           bandProvider: bandProvider)
                    pumpReading = classified.reading
                    if pumpReading != nil { resolvedSource = .pump }
                    let detection = classified.detection
                    AppLog.shared.emit(CaptureClassify(
                        reader: "loaded", display: detection.isPumpDisplay, rows: detection.displayRows,
                        textLines: detection.textLines, widestRow: detection.widestRow, tallestRow: detection.tallestRow,
                        durationMs: Int(Date().timeIntervalSince(classifyStartedAt) * 1000),
                        path: detection.path.rawValue))
                } else {
                    // The models are missing from the bundle: every frame is a receipt, and
                    // the line says so rather than leaving the pump path silently dead.
                    AppLog.shared.emit(CaptureClassify(reader: "missing", display: false, rows: 0, textLines: 0,
                                                       widestRow: 0, tallestRow: 0, durationMs: 0))
                }
            }
            (assembly, lines) = await recognize(box: box, source: resolvedSource, bandProvider: bandProvider)
            if let pumpReading {
                // The reader's committed fields win over the rules arm's; an
                // abstained field falls through to what the rules read, and
                // the crops point at the display windows.
                assembly.extraction.liters = pumpReading.extraction.liters ?? assembly.extraction.liters
                assembly.extraction.unitPrice = pumpReading.extraction.unitPrice ?? assembly.extraction.unitPrice
                assembly.extraction.total = pumpReading.extraction.total ?? assembly.extraction.total
                if pumpReading.extraction.crossCheck == .lock { assembly.extraction.crossCheck = .lock }
                assembly.cropRects.merge(pumpReading.cropRects.mapValues(flippedToVision)) { _, pump in pump }
            }
        } else {
            assembly = CaptureAssembly(extraction: FuelExtraction(), qrAnchor: nil, cropRects: [:])
        }
        var prefill = ConfirmPrefill(
            extraction: assembly.extraction,
            crops: cropEvidence(assembly.cropRects, image: image),
            qrAnchor: assembly.qrAnchor,
            ocrLines: lines,
            sourceImage: image,
            pipelineDurationMs: Int(Date().timeIntervalSince(startedAt) * 1000))
        if resolvedSource == .pump {
            prefill.provenance = .pumpPhoto
            prefill.pumpAlpha = PumpPhotoCapture.outcome(
                pumpPhotoEnabled: PumpPhotoGate.allowsPumpPhoto, extraction: assembly.extraction).alpha
        }
        return prefill
    }

    /// The pump reader, off the main actor: the locator, the classifier and
    /// the law are CPU-bound. The reading is `nil` when the frame is not a
    /// display; the detection says what was counted either way.
    private static func readPumpDisplay(
        _ box: UprightBox, reader: PumpReaderHandle, bandProvider: (any FuelPriceBandProvider)?
    ) async -> (detection: PumpDisplayCapture.Detection, reading: PumpDisplayCapture.Reading?) {
        await Task.detached(priority: .userInitiated) {
            let currency: CurrencyCode? = Locale.current.currency.flatMap { CurrencyCode(rawValue: $0.identifier) }
            return PumpDisplayCapture.classify(
                image: box.image, reader: reader, currency: currency,
                priceBand: bandProvider?.currencyBand(currency: currency))
        }.value
    }

    /// The photo with its orientation baked in, which the pump reader's
    /// geometry needs (it takes no orientation of its own).
    private static func uprightCGImage(of image: UIImage) -> CGImage? {
        if image.imageOrientation == .up { return image.cgImage }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }.cgImage
    }

    /// The reader's rects are top-left-origin; the assembler's are Vision's
    /// bottom-left, which `pixelRect` below expects.
    private static func flippedToVision(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
    }

    // MARK: - Off-main work

    /// OCR + QR detection + assembly, off the main actor: Vision recognition is
    /// CPU-bound and must never block the UI. Only Sendable values cross.
    private static func recognize(box: CGImageBox,
                                  source: ExtractionSource,
                                  bandProvider: (any FuelPriceBandProvider)?) async -> (CaptureAssembly, [OCRLine]) {
        await Task.detached(priority: .userInitiated) {
            let cgImage = box.image
            let lines = (try? await VisionTextRecognizer.recognizeText(image: cgImage,
                                                                       orientation: box.orientation,
                                                                       languages: languages)) ?? []
            let qrPayload = CaptureQRDetector.detectPayload(in: cgImage, orientation: box.orientation)
            let assembly = ExtractionAssembler.assemble(lines: lines,
                                                        qrPayload: qrPayload,
                                                        source: source,
                                                        bandProvider: bandProvider)
            return (assembly, lines)
        }.value
    }

    // MARK: - Crop evidence

    /// Converts the assembler's Vision-normalised crop rects into image-pixel
    /// `CropEvidence`, attaching the source image. This is the "UIImage crop is
    /// app-side" half - the rects stayed values in core, the image stays here.
    private static func cropEvidence(
        _ rects: [ManualFillUpMath.Field: CGRect],
        image: UIImage
    ) -> [ManualFillUpMath.Field: CropEvidence] {
        let pixelSize = CGSize(width: image.size.width * image.scale,
                               height: image.size.height * image.scale)
        return rects.mapValues { rect in
            CropEvidence(image: image, rect: pixelRect(rect, imageSize: pixelSize))
        }
    }

    /// Vision's bounding box has a bottom-left origin and normalised 0-1
    /// coordinates; an image crop needs top-left-origin pixel coordinates.
    private static func pixelRect(_ normalized: CGRect, imageSize: CGSize) -> CGRect {
        CGRect(x: normalized.minX * imageSize.width,
               y: (1 - normalized.maxY) * imageSize.height,
               width: normalized.width * imageSize.width,
               height: normalized.height * imageSize.height)
    }
}

// MARK: - QR detection (Vision)

/// Finds the first barcode payload in an image - the fiscal QR's `String`,
/// which `ExtractionAssembler` hands to `FiscalQRParser`. No QR is a plain
/// absence (`nil`), never an error.
enum CaptureQRDetector {
    static func detectPayload(in image: CGImage, orientation: CGImagePropertyOrientation) -> String? {
        let request = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
        try? handler.perform([request])
        return (request.results ?? []).compactMap(\.payloadStringValue).first
    }
}

/// `CGImage` is not Sendable; this box is the deliberate, documented exception
/// for an image created exclusively for OCR and handed across to a detached
/// task - the same pattern `PhotoPickerView.PickedImage` uses. The orientation
/// travels with the pixels because a `CGImage` alone carries none (RV.49).
private struct UprightBox: @unchecked Sendable {
    let image: CGImage
}

private struct CGImageBox: @unchecked Sendable {
    let image: CGImage
    let orientation: CGImagePropertyOrientation
}

/// Maps a `UIImage`'s orientation onto Vision's `CGImagePropertyOrientation` so
/// the recognizer is told the truth about how the pixels are held. The camera
/// shutter's `UIImage(data:)` preserves the EXIF orientation; `process` must
/// not drop it (a `CGImage` has no orientation of its own).
private func cgImagePropertyOrientation(of image: UIImage) -> CGImagePropertyOrientation {
    switch image.imageOrientation {
    case .up: return .up
    case .down: return .down
    case .left: return .left
    case .right: return .right
    case .upMirrored: return .upMirrored
    case .downMirrored: return .downMirrored
    case .leftMirrored: return .leftMirrored
    case .rightMirrored: return .rightMirrored
    @unknown default: return .up
    }
}
