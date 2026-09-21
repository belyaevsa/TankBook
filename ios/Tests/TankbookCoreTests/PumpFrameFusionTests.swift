import CoreGraphics
import Foundation
import Testing
@testable import TankbookCore

/// The frame-fusion seam on synthetic cells, so it is provable without the
/// corpus: the element-wise median, the whole-frame skip on a cell-count
/// mismatch, and the still as the fallback when no frame agrees.
@Suite("PU.19 frame fusion")
struct PumpFrameFusionTests {

    private static let modelURL = PumpReaderTestSupport.repoRoot
        .appendingPathComponent("ios/App/Resources/PumpSegments.mlpackage")

    @Test("the median of three probability vectors is taken element-wise")
    func elementwiseMedian() {
        let first = [0.9, 0.1, 0.4, 0.8]
        let second = [0.1, 0.5, 0.4, 0.2]
        let third = [0.2, 0.9, 0.4, 0.5]
        #expect(PumpReader.elementwiseMedian([first, second, third]) == [0.2, 0.5, 0.4, 0.5])
        // Even count averages the two middle values.
        #expect(PumpReader.elementwiseMedian([first, second]) == [0.5, 0.3, 0.4, 0.5])
    }

    @Test("with no frames the still's own reading is returned unchanged")
    func noFramesFallsBackToTheStill() throws {
        let model = try PumpSegmentsModel(contentsOf: Self.modelURL)
        let reader = PumpReader(model: model)
        let image = Self.stripImage(cells: 3)
        let windows = [PumpReader.Window(field: .total, quad: Self.fullQuad(image))]

        let still = try reader.read(image: image, windows: windows)
        let fused = try reader.readFused(still: image, windows: windows,
                                         frames: [PumpTrackedFrame](), mode: .probabilities)
        #expect(fused.count == still.count)
        #expect(fused.first?.cells == still.first?.cells)
    }

    @Test("a frame whose slicer count differs is skipped whole")
    func mismatchedFrameIsSkipped() throws {
        let model = try PumpSegmentsModel(contentsOf: Self.modelURL)
        let reader = PumpReader(model: model)
        let image = Self.stripImage(cells: 3)
        let windows = [PumpReader.Window(field: .total, quad: Self.fullQuad(image))]

        let still = try reader.read(image: image, windows: windows)
        // The frame shows two glyphs where the still shows three.
        let frameImage = Self.stripImage(cells: 2)
        let frame = PumpTrackedFrame(image: frameImage,
                                     windows: [PumpReader.Window(field: .total, quad: Self.fullQuad(frameImage))])
        let fused = try reader.readFused(still: image, windows: windows, frames: [frame],
                                         mode: .probabilities)
        #expect(fused.first?.cells == still.first?.cells)
    }

    @Test("an agreeing frame is fused, not ignored")
    func agreeingFrameIsUsed() throws {
        let model = try PumpSegmentsModel(contentsOf: Self.modelURL)
        let reader = PumpReader(model: model)
        let image = Self.stripImage(cells: 3)
        let windows = [PumpReader.Window(field: .total, quad: Self.fullQuad(image))]

        let still = try reader.read(image: image, windows: windows)
        // The same three cells under a vertical glare gradient: the frame
        // agrees on the count but its pixels differ, so a fused reading that
        // merely returned the still's vector would be caught.
        let frameImage = Self.glareStrip(cells: 3)
        let frame = PumpTrackedFrame(image: frameImage,
                                     windows: [PumpReader.Window(field: .total, quad: Self.fullQuad(frameImage))])
        let fused = try reader.readFused(still: image, windows: windows, frames: [frame],
                                         mode: .probabilities)
        #expect(fused.first?.cells.count == still.first?.cells.count)
        #expect(fused.first?.cells != still.first?.cells)
    }

    /// A dark-on-light strip of `cells` glyph bodies on a fixed pitch, as an
    /// RGB buffer the slicer and the warp both accept.
    private static func stripImage(cells: Int, ink: UInt8 = 26, background: UInt8 = 217,
                                   offset: Int = 3, barWidth: Int = 12) -> PumpRGBImage {
        let pitch = 24
        let width = cells * pitch
        let height = 40
        var pixels = [UInt8](repeating: background, count: width * height * 4)
        for index in stride(from: 3, to: pixels.count, by: 4) { pixels[index] = 255 }
        for cell in 0..<cells {
            for y in 4..<36 {
                for x in (cell * pitch + offset)..<(cell * pitch + offset + barWidth) {
                    let index = (y * width + x) * 4
                    pixels[index] = ink
                    pixels[index + 1] = ink
                    pixels[index + 2] = ink
                }
            }
        }
        return PumpRGBImage(width: width, height: height, pixels: pixels)
    }

    /// The same strip under a vertical glare gradient: different pixels, the
    /// same three cells.
    private static func glareStrip(cells: Int) -> PumpRGBImage {
        let image = stripImage(cells: cells)
        var pixels = image.pixels
        for y in 0..<image.height {
            let boost = 60 * (image.height - 1 - y) / max(1, image.height - 1)
            for x in 0..<image.width {
                let index = (y * image.width + x) * 4
                for channel in 0..<3 {
                    pixels[index + channel] = UInt8(min(255, Int(pixels[index + channel]) + boost))
                }
            }
        }
        return PumpRGBImage(width: image.width, height: image.height, pixels: pixels)
    }

    private static func fullQuad(_ image: PumpRGBImage) -> [CGPoint] {
        [CGPoint(x: 0, y: 0), CGPoint(x: CGFloat(image.width), y: 0),
         CGPoint(x: CGFloat(image.width), y: CGFloat(image.height)),
         CGPoint(x: 0, y: CGFloat(image.height))]
    }
}
