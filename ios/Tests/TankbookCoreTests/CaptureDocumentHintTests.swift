import Foundation
import Testing
@testable import TankbookCore

/// A Fill-up capture that is not a fuel document (`CaptureDocumentHint`,
/// RV.319): a workshop invoice suggests Service, a shop receipt Expense, and
/// anything with fuel evidence suggests nothing.
@Suite("Capture document hint (RV.319)")
struct CaptureDocumentHintTests {
    private func lines(_ texts: [String]) -> [OCRLine] { texts.map { OCRLine(text: $0) } }

    @Test("a workshop invoice suggests Service")
    func invoice() {
        let tireman = InvoiceSplitterTableTests.tireman
        #expect(CaptureDocumentHint.suggestedForm(lines: tireman, extraction: FuelExtraction()) == .service)
        let order = lines(["ЗАКАЗ-НАРЯД Р-0000016611", "Диагностика 1 600,00", "Итого 1 600,00"])
        #expect(CaptureDocumentHint.suggestedForm(lines: order, extraction: nil) == .service)
    }

    @Test("a total alone suggests nothing - it is as often a fuel receipt whose fuel line went unread")
    func totalAlone() {
        let shop = lines(["Rimi Mustamäe", "Piim 1.29", "Leib 2.10", "KOKKU 3.39"])
        #expect(CaptureDocumentHint.suggestedForm(lines: shop, extraction: nil) == nil)
    }

    @Test("fuel evidence always wins: a fuel kind or a fuel word; a volume alone does not")
    func fuelWins() {
        var kind = FuelExtraction()
        kind.fuelKind = .diesel
        let invoiceLike = lines(["INVOICE", "Oil filter 12.40", "TOTAL 12.40"])
        #expect(CaptureDocumentHint.suggestedForm(lines: invoiceLike, extraction: kind) == nil)
        let fuelWord = lines(["Circle K", "95 miles 46,81 L", "Hind 1,884 EUR/L", "KOKKU 88,19"])
        #expect(CaptureDocumentHint.suggestedForm(lines: fuelWord, extraction: FuelExtraction()) == nil)
        let diesel = lines(["ДИЗЕЛЬНОЕ ТОПЛИВО", "ИТОГ 2 500,00"])
        #expect(CaptureDocumentHint.suggestedForm(lines: diesel, extraction: nil) == nil)
        // A station receipt with fuel AND motor oil: the fuel word wins over the oil row.
        let mixed = lines(["АИ-95 40,00 x 55,40", "Масло моторное 5W40 1 л 890,00", "ИТОГ 3 106,00"])
        #expect(CaptureDocumentHint.suggestedForm(lines: mixed, extraction: FuelExtraction()) == nil)
        var litres = FuelExtraction()
        litres.liters = 4
        let oilChange = lines(["Масло моторное 5W40 4 л 3 200,00", "ИТОГ 3 200,00"])
        #expect(CaptureDocumentHint.suggestedForm(lines: oilChange, extraction: litres) == .service)
    }

    @Test("a photo with no cost on it suggests nothing")
    func nothing() {
        #expect(CaptureDocumentHint.suggestedForm(lines: [], extraction: nil) == nil)
        #expect(CaptureDocumentHint.suggestedForm(lines: lines(["Hello", "World"]), extraction: nil) == nil)
    }

    @Test("the verify screen says not-fuel instead of couldn't-read, never on a pump photo")
    func notice() {
        let notices = CaptureVerifyNotice.resolve(provenance: .receiptScan, hasPhoto: true,
                                                  extraction: FuelExtraction(), pumpAlpha: false,
                                                  pumpCaution: nil, crossCheck: nil, reading: false,
                                                  documentHint: .service)
        #expect(notices == [.notFuel(suggested: .service)])
        let pump = CaptureVerifyNotice.resolve(provenance: .pumpPhoto, hasPhoto: true,
                                               extraction: FuelExtraction(), pumpAlpha: false,
                                               pumpCaution: nil, crossCheck: nil, reading: false,
                                               documentHint: .service)
        #expect(!pump.contains(.notFuel(suggested: .service)))
        let reading = CaptureVerifyNotice.resolve(provenance: .receiptScan, hasPhoto: true,
                                                  extraction: nil, pumpAlpha: false, pumpCaution: nil,
                                                  crossCheck: nil, reading: true, documentHint: .expense)
        #expect(reading.isEmpty)
    }
}
