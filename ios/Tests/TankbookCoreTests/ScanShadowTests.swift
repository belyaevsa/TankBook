import Foundation
import Testing
@testable import TankbookCore

/// The beta's unshown routes (`ScanShadow`): the pump parser over the capture's
/// own OCR text, and the currency the display prints beside the reader's.
@Suite("Scan shadow")
struct ScanShadowTests {
    private static let bands = DefaultFuelPriceBandProvider(pack: try! FuelPriceBandStore.bundledPack())

    @Test("the Vision route reads pump-001's text and says it closes; the display's currency is EUR")
    func visionRouteAndCurrency() {
        let lines = ["7€", "SUMMA", "12522", "LIITRIT", "67.00", "1869 HIND/1L"].map { OCRLine(text: $0) }
        let shadow = ScanShadow.compute(lines: lines, bandProvider: Self.bands,
                                        readerCurrency: CurrencyCode(rawValue: "RUB"), closedUnder: nil)
        #expect(shadow.visionLiters == 67.00)
        #expect(shadow.visionUnitPrice == Decimal(string: "1.869"))
        #expect(shadow.visionTotal == Decimal(string: "125.22"))
        #expect(shadow.visionCloses)
        #expect(shadow.displayCurrency == "EUR")
        #expect(shadow.readerCurrency == "RUB")
        #expect(shadow.readerClosedUnder == nil)
    }

    @Test("a partial or non-closing read does not close")
    func closes() {
        var read = FuelExtraction()
        read.liters = 10.90
        read.unitPrice = Decimal(string: "2.039")
        read.total = Decimal(string: "22.23")
        #expect(ScanShadow.closes(read))
        read.total = Decimal(string: "22.83")
        #expect(!ScanShadow.closes(read))
        read.total = nil
        #expect(!ScanShadow.closes(read))
    }

    @Test("the record carries the shadow as JSON")
    func recorded() throws {
        var record = ScanRecord(capturedAt: Date(timeIntervalSince1970: 0), requestedSource: nil,
                                resolvedSource: .pump, provenance: "pumpPhoto", durationMs: 1,
                                extraction: FuelExtraction())
        record.shadow = ScanShadow(visionLiters: 10.9, visionUnitPrice: nil, visionTotal: nil, visionCloses: false,
                                   displayCurrency: "EUR", readerCurrency: "EUR", readerClosedUnder: "EUR")
        let body = try #require(JSONSerialization.jsonObject(with: record.data) as? [String: Any])
        let shadow = try #require(body["shadow"] as? [String: [String: Any]])
        #expect(shadow["vision"]?["liters"] as? Double == 10.9)
        #expect(shadow["vision"]?["unitPrice"] is NSNull)
        #expect(shadow["currency"]?["display"] as? String == "EUR")
    }
}
