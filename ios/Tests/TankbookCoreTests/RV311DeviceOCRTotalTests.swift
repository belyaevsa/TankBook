import Foundation
import Testing
@testable import TankbookCore

/// RV.311: five shots of one Circle K receipt as the phone's own Vision read
/// them (`fixtures/device-ocr/receipt-099-shots.json`). In shot 3 Vision read
/// the grand total "88,19 EUR" as "08,19 EUR" and the litres as "45,81l", both
/// at confidence 1.0; with the litres unresolved nothing checked the total and
/// 8.19 reached the form. The simulator's Vision does not reproduce a device
/// misread, so the lines themselves are the fixture.
@Suite("RV.311 a lone misread total the receipt contradicts")
struct RV311DeviceOCRTotalTests {
    private static let fixture = URL(fileURLWithPath: #filePath).standardizedFileURL
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Spike/ReceiptSpike/fixtures/device-ocr/receipt-099-shots.json")

    private static func shots() throws -> [[OCRLine]] {
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any] ?? [:]
        return (root["shots"] as? [[String: Any]] ?? []).map { shot in
            (shot["ocrLines"] as? [[String: Any]] ?? []).map { line in
                let box = line["box"] as? [Double] ?? [0, 0, 0, 0]
                return OCRLine(text: line["text"] as? String ?? "",
                               confidence: Float(line["confidence"] as? Double ?? 1),
                               boundingBox: CGRect(x: box[0], y: box[1], width: box[2], height: box[3]))
            }
        }
    }

    private static let extractor = FuelExtractor(
        bandProvider: DefaultFuelPriceBandProvider(pack: try! FuelPriceBandStore.bundledPack()))

    @Test("the misread shot never pre-fills 8.19")
    func misreadShotAbstains() throws {
        let shots = try Self.shots()
        #expect(shots.count == 5)
        let read = Self.extractor.extract(lines: shots[2])
        #expect(read.total != Decimal(string: "8.19"))
        #expect(read.total == nil || read.total == Decimal(string: "88.19"))
    }

    @Test("the shots Vision read right still read 46.81 / 1.884 / 88.19")
    func goodShotsUnchanged() throws {
        let shots = try Self.shots()
        for index in [0, 3, 4] {
            let read = Self.extractor.extract(lines: shots[index])
            #expect(read.liters == 46.81, "shot \(index + 1)")
            #expect(read.unitPrice == Decimal(string: "1.884"), "shot \(index + 1)")
            #expect(read.total == Decimal(string: "88.19"), "shot \(index + 1)")
        }
        #expect(Self.extractor.extract(lines: shots[1]).total == Decimal(string: "88.19"))
    }
}
