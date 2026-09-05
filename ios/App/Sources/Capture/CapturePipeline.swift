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
    @MainActor
    static func process(_ image: UIImage, source: ExtractionSource,
                        bandProvider: (any FuelPriceBandProvider)? = nil) async -> ConfirmPrefill {
        // OB.2: the recognition duration rides the prefill so the
        // `capture.pipeline` line emitted at the confirm commit can carry it.
        // The duration covers OCR + QR + assembly, not the user's editing time.
        let startedAt = Date()
        let assembly: CaptureAssembly
        let lines: [OCRLine]
        // Both halves are load-bearing: RV.49's orientation (an in-app photo
        // reaches Vision sideways without it) and RV.48's band provider (the
        // resolution ladder's steps 3 and 4 are dead without it).
        if let cgImage = image.cgImage {
            let box = CGImageBox(image: cgImage, orientation: cgImagePropertyOrientation(of: image))
            (assembly, lines) = await recognize(box: box, source: source, bandProvider: bandProvider)
        } else {
            assembly = CaptureAssembly(extraction: FuelExtraction(), qrAnchor: nil, cropRects: [:])
            lines = []
        }
        return ConfirmPrefill(
            extraction: assembly.extraction,
            crops: cropEvidence(assembly.cropRects, image: image),
            qrAnchor: assembly.qrAnchor,
            ocrLines: lines,
            sourceImage: image,
            pipelineDurationMs: Int(Date().timeIntervalSince(startedAt) * 1000))
    }

    // MARK: - Off-main work

    /// OCR + QR detection + assembly, off the main actor: Vision recognition is
    /// CPU-bound and must never block the UI. Only Sendable values cross.
    private static func recognize(box: CGImageBox,
                                  source: ExtractionSource,
                                  bandProvider: (any FuelPriceBandProvider)?) async -> (CaptureAssembly, [OCRLine]) {
        await Task.detached(priority: .userInitiated) {
            let cgImage = box.image
            let lines = (try? VisionTextRecognizer.recognizeText(image: cgImage,
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
