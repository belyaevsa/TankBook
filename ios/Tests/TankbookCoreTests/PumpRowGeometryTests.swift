import CoreGraphics
import Foundation
import Testing
@testable import TankbookCore

/// PU.47 - the verifier's geometry verdict, one test per rule. The positives
/// and negatives are real corpus stills (`Spike/ReceiptSpike/fixtures/pump`),
/// sliced by the production slicer; the bounds themselves were chosen on the
/// train split only and are documented in `PumpRowGeometry` and the report.
///
/// The two named mutations (run by hand, red-then-green in the report):
/// - removing the pitch rule keeps the pump-215 keypad and turns `pitch` red;
/// - removing the blank-layout rule keeps pump-263's CLOSED and turns
///   `blankLayout` red.
@Suite("PU.47 row geometry", .pumpFixturesPresent)
struct PumpRowGeometryTests {

    private static let fixtures = "Spike/ReceiptSpike/fixtures/pump"

    private static func annotation(_ name: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: PumpReaderTestSupport.windowsURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ann = root[name] as? [String: Any] else { return nil }
        return ann
    }

    private static func upright(_ name: String) -> (PumpRGBImage, [String: Any])? {
        guard let ann = annotation(name),
              let image = PumpReaderTestSupport.loadRGB(
                url: PumpReaderTestSupport.pumpFixturesRoot.appendingPathComponent(name)) else { return nil }
        let rotation = (ann["rotationCW"] as? NSNumber)?.intValue ?? 0
        return (PumpPanelLocator.rotatedRGB(image, rotationCW: rotation), ann)
    }

    /// The cells of one annotated window, in the upright frame the verifier
    /// sees (the full slice, blanks included).
    private static func windowCells(_ name: String, field: String) -> [GlyphCell]? {
        guard let (image, ann) = upright(name) else { return nil }
        let rotation = (ann["rotationCW"] as? NSNumber)?.intValue ?? 0
        for raw in ann["windows"] as? [[String: Any]] ?? [] {
            guard (raw["field"] as? String) == field,
                  let quad = (raw["quad"] as? [[NSNumber]])?.map({ $0.map(\.doubleValue) }) else { continue }
            let px = PumpQuadWarp.readingOrder(
                PumpReaderTestSupport.quadPixels(quad, width: image.width, height: image.height), rotationCW: rotation)
            if let sliced = PumpReader.sliceDetectedOrOriginal(px, detected: false, in: image) {
                return sliced.fullCells
            }
        }
        return nil
    }

    private static func stripSizes(_ name: String, field: String) -> (Int, Int)? {
        guard let (image, ann) = upright(name) else { return nil }
        let rotation = (ann["rotationCW"] as? NSNumber)?.intValue ?? 0
        for raw in ann["windows"] as? [[String: Any]] ?? [] {
            guard (raw["field"] as? String) == field,
                  let quad = (raw["quad"] as? [[NSNumber]])?.map({ $0.map(\.doubleValue) }) else { continue }
            let px = PumpQuadWarp.readingOrder(
                PumpReaderTestSupport.quadPixels(quad, width: image.width, height: image.height), rotationCW: rotation)
            if let sliced = PumpReader.sliceDetectedOrOriginal(px, detected: false, in: image) {
                return (sliced.strip.width, sliced.strip.height)
            }
        }
        return nil
    }

    private static func geometry(_ name: String, field: String) -> PumpRowGeometry.Verdict? {
        guard let cells = windowCells(name, field: field),
              let (width, height) = stripSizes(name, field: field) else { return nil }
        return PumpRowGeometry.verdict(cells: cells, stripWidth: width, stripHeight: height)
    }

    private static func geometryHand(_ name: String, x0: Double, y0: Double, x1: Double, y1: Double)
        -> PumpRowGeometry.Verdict? {
        guard let (image, _) = upright(name) else { return nil }
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let quad = [CGPoint(x: x0 * width, y: y0 * height), CGPoint(x: x1 * width, y: y0 * height),
                    CGPoint(x: x1 * width, y: y1 * height), CGPoint(x: x0 * width, y: y1 * height)]
        guard let sliced = PumpReader.sliceDetectedOrOriginal(quad, detected: false, in: image) else { return nil }
        return PumpRowGeometry.verdict(cells: sliced.fullCells, stripWidth: sliced.strip.width,
                                       stripHeight: sliced.strip.height)
    }

    @Test("a display's pitch-to-band is kept; a keypad's square keys are not")
    func pitch() throws {
        let good = try #require(Self.geometry("pump-032-gilbarco-circlek-ee-clean.jpg", field: "total"))
        #expect(good.kept)
        #expect(!good.reasons.contains(.pitch))
        // pump-215's keypad: the black 4x4 key grid at the right of the still.
        // No annotation window covers it, so the quad is hand-written over the
        // "1 2 3" row (x 0.680-0.795, y 0.555-0.590); its keys are square
        // (pitch/band 1.36), where the display's cells are narrower than tall.
        let keypad = try #require(Self.geometryHand(
            "pump-215-gilbarco-veederroot-lukoil-zero-padded-1511l-5358-board-ru.jpg",
            x0: 0.680, y0: 0.555, x1: 0.795, y1: 0.590))
        #expect(!keypad.kept)
        #expect(keypad.reasons.contains(.pitch))
    }

    @Test("a decimal mark the law can place is kept; one implying too many decimals is not")
    func decimalMark() throws {
        // pump-001's liters "67.00": the mark on cell 1 of 4, two decimals.
        let good = try #require(Self.geometry("pump-001.heic", field: "liters"))
        #expect(good.kept)
        #expect(!good.reasons.contains(.decimalMark))
        // pump-045's total "0029,31": the slicer puts the mark on cell 0 of 6,
        // which implies five decimals - no placement the law reads.
        let misplaced = try #require(Self.geometry(
            "pump-045-gilbarco-circlek-ee-1799-zeropad.jpg", field: "total"))
        #expect(!misplaced.kept)
        #expect(misplaced.reasons.contains(.decimalMark))
    }

    @Test("a display's leading blank run is kept; an interior run is not")
    func blankLayout() throws {
        // pump-215's total "00809,59" is zero-padded, so every cell is lit and
        // the leading run is empty; the rule passes it. (pump-032's total is
        // the still with a real leading run of three unlit cells, also kept.)
        let good = try #require(Self.geometry(
            "pump-215-gilbarco-veederroot-lukoil-zero-padded-1511l-5358-board-ru.jpg", field: "total"))
        #expect(good.kept)
        #expect(!good.reasons.contains(.blankLayout))
        // pump-263's CLOSED sum window: five occupied runs with interior gaps
        // of 88, 3 and 41 cells - spaced text, not a number row.
        let closed = try #require(Self.geometry(
            "pump-263-wayne-circlek-pump4-closed-text-negative-ee.jpg", field: "total"))
        #expect(!closed.kept)
        #expect(closed.reasons.contains(.blankLayout))
    }

    @Test("a display's ink band is kept; a thin text line is not")
    func inkBand() throws {
        let good = try #require(Self.geometry("pump-032-gilbarco-circlek-ee-clean.jpg", field: "total"))
        #expect(good.kept)
        #expect(!good.reasons.contains(.inkBand))
        // The CLOSED sum window's band is 2 px of the 96 px strip (0.021); the
        // still's Vision rows are character-box rows as tall as their glyphs,
        // so the thin-band case is the CLOSED window, not a Vision line.
        let closed = try #require(Self.geometry(
            "pump-263-wayne-circlek-pump4-closed-text-negative-ee.jpg", field: "total"))
        #expect(!closed.kept)
        #expect(closed.reasons.contains(.inkBand))
    }
}
