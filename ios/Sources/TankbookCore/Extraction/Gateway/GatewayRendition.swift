import CoreGraphics
import Foundation
import ImageIO

// MARK: - P6.3 the /extract rendition (docs/API.md -> "The device's side of
// /extract", rule 1).
//
// A full-resolution iPhone capture is several megabytes; uploading one over a
// forecourt's cell signal is the slowest step in the whole flow by an order of
// magnitude, and the 4 MB envelope cap is a ceiling, not a target. The device
// therefore sends a long-edge-bounded, JPEG-compressed rendition.
//
// Compression is a measurable trade, not a free one: fuel receipts are thermal
// print, the digits that matter are small, and over-compression eats exactly
// them. So the settings here are gated on the corpus - `CorpusCompressionTests`
// re-scores the receipt fixtures through this exact step with the existing
// scorer and tolerance, and the settings may not fall below the recorded mark
// (docs/API.md, same paragraph).
//
// API.md starts at long edge 1600 px / quality 0.7 and says "tune down only
// against the corpus". The corpus answered, and the shipped values are the
// tune: 1600 px @ 0.7 scored 82/175 against the recorded 88/175, so the
// shipped defaults are **long edge 1800 px @ quality 0.9**, which scores 89/175
// at a median ~360 KB base64 rendition (max ~830 KB across the receipt corpus)
// - comfortably under the 4 MB ceiling, and it does not read the receipt worse.

/// The on-device rendition of a captured image sent to `POST /extract`.
/// Pure image work - CoreGraphics + ImageIO, no Vision, no network - so it is
/// testable in a plain `swift test` process (macOS is a supported platform of
/// the package).
public enum GatewayRendition {
    /// The long-edge bound of the rendition. The 4 MB envelope is a ceiling,
    /// not a target; the corpus gate (`CorpusCompressionTests`) chose this
    /// value: it scores the receipt corpus above the recorded mark where the
    /// doc's starting point (1600 px) did not.
    public static let defaultLongEdge: Int = 1800
    /// The JPEG quality of the rendition, chosen by the same corpus gate
    /// (docs/API.md: "tune down only against the corpus").
    public static let defaultJPEGQuality: Double = 0.9

    /// The base64 size of the envelope cap, in bytes, BEFORE base64 expansion:
    /// a base64 image over this cap answers `413` (docs/API.md -> /extract).
    /// The client's rendition targets far below it; the constant exists so the
    /// "the 4 MB envelope is a ceiling" guarantee is checked, not assumed.
    public static let envelopeCapBytes: Int = 4 * 1024 * 1024

    /// Downscales `image` so its long edge is at most `longEdge` px and encodes
    /// it as JPEG at `quality`. An image already within the bound is not
    /// upscaled - only re-encoded, so a small image never becomes a larger
    /// upload than it started as.
    public static func jpegData(
        from image: CGImage,
        longEdge: Int = defaultLongEdge,
        quality: Double = defaultJPEGQuality
    ) -> Data? {
        let width = image.width
        let height = image.height
        let longSide = max(width, height)
        guard longSide > 0 else { return nil }

        let target: CGImage
        if longSide > longEdge {
            let scale = Double(longEdge) / Double(longSide)
            let targetWidth = max(1, Int((Double(width) * scale).rounded()))
            let targetHeight = max(1, Int((Double(height) * scale).rounded()))
            guard let resized = resize(image, to: CGSize(width: targetWidth, height: targetHeight)) else {
                return nil
            }
            target = resized
        } else {
            target = image
        }
        return jpeg(from: target, quality: quality)
    }

    /// Decodes a JPEG/PNG/HEIC `Data` payload into a `CGImage`. The inverse of
    /// `jpegData(from:)`: the L5 gate OCRs the *rendition*, so it must be able
    /// to hand the compressed bytes back to Vision.
    public static func image(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// The base64 the client would upload for `jpegData`: the envelope cap is
    /// enforced on the base64 string (docs/API.md), so this is the number that
    /// must stay under `envelopeCapBytes`.
    public static func base64Length(jpegData: Data) -> Int {
        ((jpegData.count * 4) + 2) / 3
    }

    // MARK: - CoreGraphics plumbing

    private static func resize(_ image: CGImage, to size: CGSize) -> CGImage? {
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func jpeg(from image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        let properties = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
