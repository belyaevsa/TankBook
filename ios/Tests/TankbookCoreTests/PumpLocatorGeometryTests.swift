import CoreGraphics
import Foundation
import Testing
@testable import TankbookCore

/// The locator's geometry after the detector (PU.35): the margin on a detected
/// box, the stacked-row rescue below the confidence cut, the keypad test.
@Suite("PU.35 locator geometry")
struct PumpLocatorGeometryTests {
    private static func quad(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> [CGPoint] {
        [CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y0), CGPoint(x: x1, y: y1), CGPoint(x: x0, y: y1)]
    }

    @Test("a detected box is widened sideways by the margin and clamped at the frame")
    func margin() {
        let image = PumpRGBImage(width: 1000, height: 1000, pixels: [UInt8](repeating: 0, count: 1000 * 1000 * 4))
        let widened = PumpReader.widened(Self.quad(300, 200, 700, 300), in: image)
        // A 100 px tall row gains a tenth of its height each side and nothing
        // vertically - the measured margin (see `detectedMarginHorizontal`).
        #expect(widened[0].x == 290 && widened[1].x == 710)
        #expect(widened[0].y == 200 && widened[2].y == 300)
        // The margin never leaves the frame.
        let atEdge = PumpReader.widened(Self.quad(0, 200, 1000, 300), in: image)
        #expect(atEdge[0].x == 0 && atEdge[1].x == 1000)
    }

    @Test("a low-confidence row under a passing row of the same span is rescued; one off to the side is not")
    func rescue() {
        let passing = PumpRowDetector.Row(quad: Self.quad(0.30, 0.25, 0.65, 0.34), confidence: 0.6)
        let stacked = PumpRowDetector.Row(quad: Self.quad(0.42, 0.36, 0.64, 0.40), confidence: 0.2)
        let aside = PumpRowDetector.Row(quad: Self.quad(0.80, 0.30, 0.95, 0.35), confidence: 0.2)
        let kept = PumpReader.rescueStackedRows([passing, stacked, aside])
        #expect(kept.map(\.confidence) == [0.6, 0.2])
        #expect(kept.contains { $0.quad == stacked.quad } && !kept.contains { $0.quad == aside.quad })
        // Nothing is rescued when no row passes on its own.
        #expect(PumpReader.rescueStackedRows([stacked, aside]).isEmpty)
    }

    @Test("a row of square keys off the display's span is a keypad; a ladder cell of tall glyphs is not")
    func keypad() {
        let total = CGRect(x: 300, y: 200, width: 400, height: 80)
        let liters = CGRect(x: 420, y: 300, width: 280, height: 60)
        let keys = CGRect(x: 800, y: 300, width: 200, height: 60)
        #expect(PumpReader.isKeypadRow(keys, widest: total, siblings: [total, liters], cellAspect: 0.57))
        // pump-056's ladder price cell: tall glyphs, kept.
        #expect(!PumpReader.isKeypadRow(keys, widest: total, siblings: [total, liters], cellAspect: 0.94))
        // Square cells INSIDE the display's span are a display row (a wide LCD), kept.
        let inside = CGRect(x: 320, y: 400, width: 200, height: 60)
        #expect(!PumpReader.isKeypadRow(inside, widest: total, siblings: [total, liters], cellAspect: 0.57))
    }
}
