import CoreGraphics
import Foundation
import Testing
@testable import TankbookCore

/// The row angle finder on synthetic seven-segment rows: a turned row is found
/// at its turn, a level row is left alone, and an italic font - vertical
/// strokes leaning, horizontal segments level - is not mistaken for a turn.
@Suite("Pump row deskew")
struct PumpRowDeskewTests {
    private static let width = 480, height = 240
    private static let centre = CGPoint(x: 240, y: 120)
    private static let rowWidth: CGFloat = 300, rowHeight: CGFloat = 70

    /// A row of five `8`s: seven segments each, dark on light, turned by
    /// `degrees` about the image centre; `italic` leans the vertical strokes
    /// by that many degrees without turning the row.
    private static func row(degrees: Double, italic: Double = 0) -> PumpRGBImage {
        let cellWidth = rowWidth / 5, stroke: CGFloat = 8, inset: CGFloat = 8
        let turn = degrees * .pi / 180, lean = CGFloat(tan(italic * .pi / 180))
        var pixels = [UInt8](repeating: 220, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                // Into the row's own frame: undo the turn about the centre.
                let dx = CGFloat(x) - centre.x, dy = CGFloat(y) - centre.y
                let u = dx * CGFloat(cos(turn)) + dy * CGFloat(sin(turn)) + rowWidth / 2
                let v = -dx * CGFloat(sin(turn)) + dy * CGFloat(cos(turn)) + rowHeight / 2
                guard u >= 0, u < rowWidth, v >= 0, v < rowHeight else { continue }
                let cell = floor(u / cellWidth)
                // An italic font shifts a stroke sideways by how high it sits.
                let local = u - cell * cellWidth + lean * (v - rowHeight / 2)
                let left = inset, right = cellWidth - inset
                let top = inset, middle = rowHeight / 2, bottom = rowHeight - inset
                let horizontal = local >= left && local <= right
                    && (abs(v - top) < stroke / 2 || abs(v - middle) < stroke / 2 || abs(v - bottom) < stroke / 2)
                let vertical = v >= top && v <= bottom
                    && (abs(local - left) < stroke / 2 || abs(local - right) < stroke / 2)
                if horizontal || vertical {
                    let i = (y * width + x) * 4
                    pixels[i] = 30; pixels[i + 1] = 30; pixels[i + 2] = 30
                }
            }
        }
        return PumpRGBImage(width: width, height: height, pixels: pixels)
    }

    /// The upright box a detector would return around the turned row.
    private static func uprightBox(degrees: Double) -> [CGPoint] {
        let corners = PumpRowDeskew.rotatedRect(centre: centre, width: rowWidth, height: rowHeight, degrees: degrees)
        let xs = corners.map(\.x), ys = corners.map(\.y)
        return [CGPoint(x: xs.min()!, y: ys.min()!), CGPoint(x: xs.max()!, y: ys.min()!),
                CGPoint(x: xs.max()!, y: ys.max()!), CGPoint(x: xs.min()!, y: ys.max()!)]
    }

    @Test("a turned row is found at its turn", arguments: [-20.0, -6.0, -3.0, 3.0, 6.0, 20.0])
    func findsTheTurn(degrees: Double) {
        let found = PumpRowDeskew.deskew(Self.uprightBox(degrees: degrees), in: Self.row(degrees: degrees))
        #expect(abs(found.degrees - degrees) <= 0.6, "turned \(degrees), found \(found.degrees)")
    }

    @Test("a row turned past the large-turn limit gets the row's own size back")
    func largeTurnRecoversTheRowSize() {
        let found = PumpRowDeskew.deskew(Self.uprightBox(degrees: 20), in: Self.row(degrees: 20))
        let length = hypot(found.quad[1].x - found.quad[0].x, found.quad[1].y - found.quad[0].y)
        let height = hypot(found.quad[3].x - found.quad[0].x, found.quad[3].y - found.quad[0].y)
        // The upright box is ~306 x ~168 around a 300 x 70 row turned 20 degrees.
        #expect(abs(length - Self.rowWidth) < 0.08 * Self.rowWidth, "length \(length)")
        #expect(abs(height - Self.rowHeight) < 0.2 * Self.rowHeight, "height \(height)")
    }

    @Test("levelling a photo by the rows' angle leaves them level", arguments: [-15.0, 15.0])
    func levelledTurnsClockwise(degrees: Double) {
        // A row turned by `degrees` (clockwise, y down), then the whole photo
        // turned back by the same amount, must read as level.
        let level = PumpRowDeskew.levelled(Self.row(degrees: degrees), degrees: -degrees)
        let found = PumpRowDeskew.deskew(Self.uprightBox(degrees: 0), in: level)
        #expect(abs(found.degrees) <= 1.0, "levelled a \(degrees) row, still turned \(found.degrees)")
        // And a point maps back to where it was in the photo.
        let p = CGPoint(x: 300, y: 80)
        let back = PumpRowDeskew.unlevelled(p, degrees: -degrees, width: 480, height: 240)
        let r = degrees * .pi / 180
        let expected = CGPoint(x: 240 + (p.x - 240) * CGFloat(cos(r)) - (p.y - 120) * CGFloat(sin(r)),
                               y: 120 + (p.x - 240) * CGFloat(sin(r)) + (p.y - 120) * CGFloat(cos(r)))
        #expect(abs(back.x - expected.x) < 0.01 && abs(back.y - expected.y) < 0.01)
    }

    @Test("a level row keeps its upright box")
    func levelStaysUpright() {
        let box = Self.uprightBox(degrees: 0)
        let found = PumpRowDeskew.deskew(box, in: Self.row(degrees: 0))
        #expect(found.degrees == 0)
        #expect(found.quad == box)
    }

    @Test("an italic font is not read as a turn")
    func italicIsNotATurn() {
        let found = PumpRowDeskew.deskew(Self.uprightBox(degrees: 0), in: Self.row(degrees: 0, italic: 10))
        #expect(abs(found.degrees) <= 0.6, "an italic row was turned by \(found.degrees)")
    }

    @Test("the transform sums along the slope, and the criterion carries the paper's sec^3 weight")
    func transformAndWeight() {
        // A 4 x 4 image with a single lit pixel per column on the staircase that
        // rises one row per column: slope 3 (of n = 4) sums all four at offset 0.
        var image = [Float](repeating: 0, count: 16)
        for x in 0..<4 { image[x * 4 + x] = 1 }
        let hough = PumpFastHough.transform(image, width: 4, height: 4)
        #expect(hough.n == 4)
        #expect(hough.sums[3 * hough.rows + 0] == 4)
        // Equal raw SSG on every slope: the criterion must scale by (1 + s^2)^1.5,
        // s = t / (n - 1), so slope 3 weighs 2^1.5 against level.
        var flat = [Float](repeating: 0, count: 4 * 8)
        for t in 0..<4 { flat[t * 8 + 3] = 1 }
        let values = PumpRowDeskew.criteria((n: 4, rows: 8, sums: flat)).values
        #expect(abs(values[3] / values[0] - pow(2.0, 1.5)) < 1e-9)
    }


    @Test("the padded transform drops a pattern's shift off the end instead of wrapping it")
    func transformDoesNotWrap() {
        // Width 2, height 1, pixels (1, 2): slope 1 at the last offset reaches
        // past the padded rows, so it holds only the left pixel's zero padding.
        let hough = PumpFastHough.transform([1, 2], width: 2, height: 1)
        #expect(hough.sums[1 * hough.rows + hough.rows - 1] == 0)
    }

    @Test("a turned row and a level one both carry the curve's confidence")
    func confidenceIsAlwaysReported() {
        let turned = PumpRowDeskew.deskew(Self.uprightBox(degrees: 6), in: Self.row(degrees: 6))
        let confidence = try? #require(turned.confidence)
        #expect((confidence?.peakRatio ?? 0) >= 1 + PumpRowDeskew.minimumGain)
        let level = PumpRowDeskew.deskew(Self.uprightBox(degrees: 0), in: Self.row(degrees: 0))
        #expect(level.confidence != nil)
    }


    @Test("an edge between two transform slopes is found between them")
    func subSlopeRefinement() {
        // A 256-wide strip (the transform's own width, one slope step =
        // atan(1/255) = 0.225 deg) with a bright band whose edges fall 10.5
        // rows across it: 2.358 deg lies halfway between slopes 10 and 11.
        // The dyadic patterns' own approximation bias keeps the estimate from
        // the exact half-step (agents/research/PU.69.md §2.2), so the pin is
        // the note's F2 - within one slope step; the refinement's gain is
        // measured on the corpus instead (median 0.63 -> 0.60 deg).
        let width = 256, height = 96
        var pixels = [Float](repeating: 0, count: width * height)
        for x in 0..<width {
            let top = 30.0 + 10.5 * Double(x) / 255.0
            for y in 0..<height where Double(y) >= top && Double(y) < top + 30 { pixels[y * width + x] = 1 }
        }
        let found = PumpRowDeskew.angle(of: PumpGrayscale(width: width, height: height, pixels: pixels))
        let truth = atan(10.5 / 255.0) * 180 / .pi
        #expect(abs((found?.degrees ?? 0) - truth) < 0.225, "found \(found?.degrees ?? .nan), truth \(truth)")
    }


    @Test("slanted strokes alone are not a turn: only horizontal structure is scored")
    func slantedStrokesAreNotATurn() {
        // Italic-style strokes slanted 10 deg from vertical, full height, and no
        // horizontal edge anywhere: the mostly-horizontal band sees nothing to
        // turn to. Fusing the paper's vertical band would read the slant as a
        // 10 deg turn.
        let width = 256, height = 96
        var pixels = [Float](repeating: 0, count: width * height)
        let slant = tan(10.0 * .pi / 180)
        for stroke in stride(from: 20, to: 236, by: 24) {
            for y in 0..<height {
                let x = stroke + Int((Double(y) * slant).rounded())
                for dx in 0..<6 where x + dx < width { pixels[y * width + x + dx] = 1 }
            }
        }
        let found = PumpRowDeskew.angle(of: PumpGrayscale(width: width, height: height, pixels: pixels))
        #expect(found?.turned != true, "turned to \(found?.degrees ?? .nan)")
    }

}
