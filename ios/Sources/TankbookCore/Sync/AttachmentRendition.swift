import CoreGraphics
import Foundation
import ImageIO

/// Pure rendition + thumbnail generation for the sync blob pipeline
/// (docs/SYNC.md -> Attachments: the blob pipeline). A sync rendition is a JPEG
/// whose long edge is <= 2048 px at quality ~0.8; PDFs pass through unmodified,
/// capped at 10 MB. A ~120 px thumbnail rides inside the Attachment payload.
///
/// No `UIImage`, no `URLSession`, no file I/O - `CGImageSource`/`CGImageDestination`
/// only, so the whole type is testable under `swift test` on macOS and the caps
/// can be asserted deterministically.
public enum AttachmentRendition {
    /// Long-edge cap for the uploaded rendition (docs/SYNC.md).
    public static let maxLongEdge = 2048
    /// The inline thumbnail's long edge.
    public static let thumbnailLongEdge = 120
    /// PDF pass-through cap (docs/SYNC.md -> 10 MB).
    public static let pdfSizeCap = 10 * 1024 * 1024
    /// JPEG quality for the sync rendition (~80).
    public static let renditionQuality: Double = 0.8
    /// JPEG quality for the inline thumbnail (~5 KB target).
    public static let thumbnailQuality: Double = 0.6

    public enum Error: Swift.Error, Equatable, Sendable {
        /// A PDF over the 10 MB cap is refused before upload (docs/SYNC.md).
        case pdfTooLarge
        /// The source bytes are not a decodable image.
        case unreadableImage
    }

    /// The bytes that sync: a JPEG capped to `maxLongEdge` (never upscaled), or
    /// the PDF passed through byte-identical (capped at `pdfSizeCap`).
    public static func rendition(for data: Data, kind: AttachmentKind) throws -> (data: Data, contentType: String) {
        switch kind {
        case .pdf:
            guard data.count <= pdfSizeCap else { throw Error.pdfTooLarge }
            return (data, "application/pdf")
        case .photo:
            return try jpeg(data: data, longEdge: maxLongEdge, quality: renditionQuality)
        }
    }

    /// A base64 JPEG thumbnail (~`thumbnailLongEdge` px), or nil for a PDF
    /// (rendered as a glyph, not a photo chip).
    public static func thumbnailBase64(for data: Data, kind: AttachmentKind) throws -> String? {
        guard kind == .photo else { return nil }
        let (jpeg, _) = try jpeg(data: data, longEdge: thumbnailLongEdge, quality: thumbnailQuality)
        return jpeg.base64EncodedString()
    }

    // MARK: - JPEG scaling

    /// Decodes `data`, scales so the long edge is at most `longEdge` (never
    /// upscaling an image already under it), and re-encodes as JPEG at `quality`.
    static func jpeg(data: Data, longEdge: Int, quality: Double) throws -> (data: Data, contentType: String) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw Error.unreadableImage
        }

        let width = image.width
        let height = image.height
        let largest = max(width, height)
        let scale = largest > longEdge ? Double(longEdge) / Double(largest) : 1.0
        let targetWidth = max(1, Int((Double(width) * scale).rounded()))
        let targetHeight = max(1, Int((Double(height) * scale).rounded()))

        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw Error.unreadableImage }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        guard let scaled = context.makeImage() else { throw Error.unreadableImage }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else {
            throw Error.unreadableImage
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, scaled, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Error.unreadableImage }
        return (output as Data, "image/jpeg")
    }
}
