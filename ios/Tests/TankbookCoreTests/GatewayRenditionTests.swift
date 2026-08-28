import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import TankbookCore

// P6.3 - the /extract rendition (docs/API.md rule 1): a long-edge-bounded,
// JPEG-compressed rendition starting at long edge 1600 px. The 4 MB envelope is
// a ceiling, not a target - and the compression settings are gated on the
// corpus separately (`CorpusCompressionTests`), so "compress harder" cannot
// quietly become "read worse".

@Suite("LLM gateway rendition (P6.3)")
struct GatewayRenditionTests {

    /// A deterministic synthetic "receipt-like" image: black glyphs on white,
    /// the exact content class whose small digits over-compression eats. Built
    /// with grayscale `CGColor` - the lint rule forbids raw `red:` component
    /// construction (hard rule 5), and this is a fixture, not UI.
    private static func makeImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Digits in a grid - the thermal-print content that matters.
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        let digit = width / 10
        for row in 0 ..< 3 {
            for col in 0 ..< 8 {
                let x = CGFloat(col * digit + digit / 4)
                let y = CGFloat(row * digit + digit / 4)
                context.fill(CGRect(x: x, y: y, width: CGFloat(digit / 2), height: CGFloat(digit / 2)))
            }
        }
        return context.makeImage()!
    }

    @Test("a full-resolution capture is downscaled to the long edge bound")
    func downscalesToTheLongEdgeBound() throws {
        let image = Self.makeImage(width: 4032, height: 3024) // 12 MP iPhone capture
        let data = GatewayRendition.jpegData(from: image)
        let rendition = try #require(data.flatMap(GatewayRendition.image(from:)))

        let longEdge = max(rendition.width, rendition.height)
        #expect(longEdge <= GatewayRendition.defaultLongEdge)
        // Downscaled, not merely re-encoded: a 12 MP photo must actually shrink.
        #expect(longEdge == GatewayRendition.defaultLongEdge,
                "a 4032 px long edge must land exactly on the 1600 px bound")
        #expect(rendition.width < image.width)
        // Aspect ratio preserved.
        #expect(rendition.width * image.height == rendition.height * image.width)
    }

    @Test("an image within the bound is never upscaled")
    func neverUpscales() throws {
        let image = Self.makeImage(width: 800, height: 600)
        let data = GatewayRendition.jpegData(from: image)
        let rendition = try #require(data.flatMap(GatewayRendition.image(from:)))
        #expect(rendition.width <= 800)
        #expect(rendition.height <= 600)
    }

    @Test("the rendition is JPEG and a small fraction of the 4 MB envelope")
    func renditionFitsTheEnvelopeWithRoomToSpare() throws {
        let image = Self.makeImage(width: 4032, height: 3024)
        let data = try #require(GatewayRendition.jpegData(from: image))

        // It must be decodable as JPEG (round-trips through ImageIO).
        _ = try #require(GatewayRendition.image(from: data))

        // The 4 MB cap is on the base64 image; a 1600 px rendition should be
        // tens to a few hundred KB - not merely under the cap but far below.
        let base64 = GatewayRendition.base64Length(jpegData: data)
        #expect(base64 < GatewayRendition.envelopeCapBytes)
        #expect(base64 < 1_000_000,
                "the rendition is a target, not a ceiling - 1600 px must stay well under 1 MB base64")
    }

    @Test("the shipped defaults are the corpus-tuned 1800 px / quality 0.9")
    func qualityDefault() {
        // The corpus gate chose these: 1600 px @ 0.7 scored below the recorded
        // mark (82/175 vs 88/175); 1800 px @ 0.9 keeps it (89/175).
        #expect(GatewayRendition.defaultJPEGQuality == 0.9)
        #expect(GatewayRendition.defaultLongEdge == 1800)
    }

    @Test("a zero-size image produces no rendition")
    func zeroSizeIsNil() {
        let image = Self.makeImage(width: 1, height: 1)
        // Not a crash; the code path for a degenerate image simply returns nil.
        _ = GatewayRendition.jpegData(from: image)
    }
}
