import CoreGraphics
import Foundation
import Testing
@testable import TankbookCore

/// PU.53 - the reader finds its own orientation. The phone never knows a
/// display's rotation (a display can be sideways in an upright frame), so the
/// live path runs the detector at 0/90/270 and keeps the orientation whose
/// rows best pass `PumpRowGeometry`, 0 winning ties. These tests pin the
/// choice on a rotated still and an upright one, and the tie rule itself.
///
/// Named mutation (run by hand, red-then-green in the report): making
/// `bestRotation` always return 0 turns `searchPicksTheDisplaysRotation` red.
@Suite("PU.53 pump reader orientation search", .pumpFixturesPresent)
struct PumpReaderOrientationTests {

    private static let modelURL = PumpReaderTestSupport.repoRoot
        .appendingPathComponent("ios/App/Resources/PumpSegments.mlpackage")

    private static func reader() throws -> PumpReader {
        PumpReader(model: try PumpSegmentsModel(contentsOf: modelURL),
                   detector: PumpReaderTestSupport.makeDetector())
    }

    private static func image(_ name: String) -> PumpRGBImage? {
        PumpReaderTestSupport.loadRGB(
            url: PumpReaderTestSupport.pumpFixturesRoot.appendingPathComponent(name))
    }

    @Test("on pump-019 the search picks the display's own rotation, 90")
    func searchPicksTheDisplaysRotation() throws {
        let name = "pump-019-gilbarco-circlek-sikupilli-pump8-ee.jpg"
        let image = try #require(Self.image(name))
        let reader = try Self.reader()
        #expect(reader.bestOrientation(for: image) == 90)
        // The search's read is the explicit-90 read: it found the orientation,
        // it did not read anything the explicit run would not.
        let searched = try reader.readPhoto(image: image, currency: .eur, priceBand: nil)
        let explicit = try reader.readPhoto(image: image, rotationCW: 90, currency: .eur, priceBand: nil)
        #expect(searched == explicit)
    }

    @Test("on an upright still the search picks 0 and the read is unchanged")
    func searchKeepsUpright() throws {
        let name = "pump-032-gilbarco-circlek-ee-clean.jpg"
        let image = try #require(Self.image(name))
        let reader = try Self.reader()
        #expect(reader.bestOrientation(for: image) == 0)
        let searched = try reader.readPhoto(image: image, currency: .eur, priceBand: nil)
        let explicit = try reader.readPhoto(image: image, rotationCW: 0, currency: .eur, priceBand: nil)
        #expect(searched == explicit)
    }

    @Test("the tie rule: equal rows and ink pick 0")
    func tieRulePicksZero() {
        // 0 and 90 keep the same rows with the same ink: 0 wins.
        let tied = [PumpReader.OrientationScore(rotationCW: 0, keptRows: 2, inkBandArea: 100),
                    PumpReader.OrientationScore(rotationCW: 90, keptRows: 2, inkBandArea: 100),
                    PumpReader.OrientationScore(rotationCW: 270, keptRows: 1, inkBandArea: 40)]
        #expect(PumpReader.bestRotation(tied) == 0)
        // More kept rows wins regardless of order.
        let moreRows = [PumpReader.OrientationScore(rotationCW: 0, keptRows: 2, inkBandArea: 500),
                        PumpReader.OrientationScore(rotationCW: 90, keptRows: 3, inkBandArea: 10)]
        #expect(PumpReader.bestRotation(moreRows) == 90)
        // Equal rows, more ink wins.
        let moreInk = [PumpReader.OrientationScore(rotationCW: 0, keptRows: 2, inkBandArea: 10),
                       PumpReader.OrientationScore(rotationCW: 90, keptRows: 2, inkBandArea: 20)]
        #expect(PumpReader.bestRotation(moreInk) == 90)
    }

    @Test("a seed is the first candidate and wins its own tie")
    func seedWinsTie() {
        #expect(PumpReader.rotationCandidates(seed: nil) == [0, 90, 270])
        #expect(PumpReader.rotationCandidates(seed: 270) == [270, 0, 90])
        #expect(PumpReader.rotationCandidates(seed: 0) == [0, 90, 270])
    }

    @Test("a crop rect in the turned frame maps back to the original")
    func unrotatedCropRect() {
        // `rotatedRGB` turns an original point (u, v) into (1 - v, u), so a
        // 90-degree turn's top-left came from the original's bottom-left.
        let rect = CGRect(x: 0, y: 0, width: 0.1, height: 0.1)
        let back = PumpPanelLocator.unrotated(rect, rotationCW: 90)
        #expect(abs(back.minX) < 1e-9 && abs(back.minY - 0.9) < 1e-9
                && abs(back.width - 0.1) < 1e-9 && abs(back.height - 0.1) < 1e-9)
        // 0 and a full turn are the identity.
        #expect(PumpPanelLocator.unrotated(rect, rotationCW: 0) == rect)
        #expect(PumpPanelLocator.unrotated(rect, rotationCW: 360) == rect)
    }
}
