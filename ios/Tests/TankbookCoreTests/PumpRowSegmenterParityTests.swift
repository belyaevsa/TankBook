import CoreGraphics
import CoreML
import CoreVideo
import ImageIO
import Foundation
@testable import TankbookCore

import Testing

/// Parity: the Swift decode reproduces `segeval`'s Python quads on the heldout
/// stills it wrote (`<run>/heldout-quads.json`), so the Swift arms measure the
/// model the rotated gate scored. Opt-in: `PUMP_SEGMENTER=<.mlpackage>` and
/// `PUMP_SEGMENTER_QUADS=<heldout-quads.json>`.
@Suite("PU.76 spike: the Swift segmenter decode matches Python")
struct PumpRowSegmenterParityTests {
    @Test("the same rows, within a hundredth of the image, on the heldout stills")
    func swiftMatchesPython() throws {
        let env = ProcessInfo.processInfo.environment
        guard let modelPath = env["PUMP_SEGMENTER"], let quadsPath = env["PUMP_SEGMENTER_QUADS"] else { return }
        let segmenter = try PumpRowSegmenter(contentsOf: URL(fileURLWithPath: modelPath))
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: quadsPath))) as? [String: Any]
        let images = root?["images"] as? [String: [[String: Any]]] ?? [:]
        let dir = URL(fileURLWithPath: quadsPath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("seg/heldout")
        var rows = 0, matched = 0, countMismatch: [String] = [], worst = 0.0
        for (name, python) in images.sorted(by: { $0.key < $1.key }) {
            guard let src = CGImageSourceCreateWithURL(dir.appendingPathComponent(name) as CFURL, nil),
                  let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { continue }
            let swift = segmenter.rows(in: cg)
            if swift.count != python.count { countMismatch.append("\(name): swift \(swift.count) python \(python.count)") }
            for p in python {
                rows += 1
                let pq = (p["quad"] as? [[Double]] ?? []).map { CGPoint(x: $0[0], y: $0[1]) }
                let best = swift.map { s in zip(s.quad, pq).map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? 1 }.min() ?? 1
                worst = max(worst, best)
                if best < 0.01 { matched += 1 }
            }
        }
        print("PU.76 parity: \(matched)/\(rows) python rows within 0.01 of a swift row; worst corner \(worst); "
              + "count mismatches \(countMismatch.count): \(countMismatch.prefix(8))")
        #expect(rows > 200)
        #expect(Double(matched) >= 0.97 * Double(rows))
    }
}

/// The segmenter's two inputs agree and its map read survives any storage layout.
@Suite("Row segmenter: camera frames and map storage")
struct PumpRowSegmenterInputTests {
    private static let model = PumpReaderTestSupport.repoRoot.appendingPathComponent("ios/App/Resources/RowSeg.mlpackage")

    @Test("a camera frame yields the rows the same frame decoded to an image does", .pumpFixturesPresent)
    func pixelBufferMatchesImage() throws {
        let segmenter = try PumpRowSegmenter(contentsOf: Self.model)
        let image = try #require(PumpQuadWarp.loadOrientedImage(from: PumpReaderTestSupport.pumpFixturesRoot
            .appendingPathComponent("pump-032-gilbarco-circlek-ee-clean.jpg")))
        var buffer: CVPixelBuffer?
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true]
        CVPixelBufferCreate(nil, image.width, image.height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &buffer)
        let pixels = try #require(buffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        let context = try #require(CGContext(
            data: CVPixelBufferGetBaseAddress(pixels), width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixels), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        CVPixelBufferUnlockBaseAddress(pixels, [])
        let fromImage = segmenter.rows(in: image)
        let fromBuffer = segmenter.rows(in: pixels)
        #expect(fromImage.count == 3)
        #expect(fromBuffer.count == fromImage.count)
        for row in fromImage {
            let best = fromBuffer.map { other in zip(row.quad, other.quad).map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? 1 }.min() ?? 1
            #expect(best < 0.01)
        }
    }

    @Test("the map read follows the array's strides, contiguous or not")
    func floatsFollowStrides() throws {
        // A 2 x 3 float32 array laid out column-major: strides [1, 2], not the row-major [3, 1].
        var storage: [Float] = [1, 4, 2, 5, 3, 6]
        let strided = try storage.withUnsafeMutableBytes { raw in
            try MLMultiArray(dataPointer: raw.baseAddress!, shape: [2, 3], dataType: .float32,
                             strides: [1, 2], deallocator: nil)
        }
        #expect(PumpRowSegmenter.floats(strided) == [1, 2, 3, 4, 5, 6])
        let contiguous = try MLMultiArray(shape: [2, 3], dataType: .float32)
        for i in 0..<6 { contiguous[i] = NSNumber(value: Float(i + 1)) }
        #expect(PumpRowSegmenter.floats(contiguous) == [1, 2, 3, 4, 5, 6])
    }
}
