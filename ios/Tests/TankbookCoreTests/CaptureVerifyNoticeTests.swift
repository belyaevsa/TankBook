import Foundation
import Testing
@testable import TankbookCore

/// What the capture verify step says above its fields.
@Suite("Capture verify notices")
struct CaptureVerifyNoticeTests {
    private func resolve(_ provenance: Provenance = .receiptScan, extraction: FuelExtraction?, alpha: Bool = false,
                         caution: PumpReadingCaution? = nil, crossCheck: CrossCheckState? = nil,
                         reading: Bool = false) -> [CaptureVerifyNotice] {
        CaptureVerifyNotice.resolve(provenance: provenance, hasPhoto: true, extraction: extraction,
                                    pumpAlpha: alpha, pumpCaution: caution, crossCheck: crossCheck,
                                    reading: reading)
    }

    @Test("nothing is said while recognition runs")
    func silentWhileReading() {
        #expect(resolve(.pumpPhoto, extraction: nil, alpha: true, reading: true).isEmpty)
    }

    @Test("a pump display with no number read admits it, and makes no alpha claim")
    func pumpNothingRead() {
        #expect(resolve(.pumpPhoto, extraction: FuelExtraction(currency: .eur), alpha: true) == [.pumpNothingRead])
    }

    @Test("a receipt with no number read says so; a guessed currency is no reading")
    func receiptNothingRead() {
        #expect(resolve(extraction: FuelExtraction(currency: .rub)) == [.nothingRead])
    }

    @Test("a partial pump reading carries the alpha notice, the price caution and a disagreement")
    func pumpNoticesStack() {
        let caution = PumpReadingCaution.shownPriceDiffers(shown: 1.919, implied: 1.839)
        let notices = resolve(.pumpPhoto, extraction: FuelExtraction(liters: 30.21), alpha: true, caution: caution,
                              crossCheck: .mismatch(field: .total))
        #expect(notices == [.pumpAlpha, .pumpPriceDiffers(shown: 1.919, implied: 1.839), .numbersDisagree])
    }

    @Test("a receipt read in full says nothing")
    func cleanReceipt() {
        #expect(resolve(extraction: FuelExtraction(liters: 42.3, unitPrice: 1.679, total: 71.02),
                        crossCheck: .verified).isEmpty)
    }
}
