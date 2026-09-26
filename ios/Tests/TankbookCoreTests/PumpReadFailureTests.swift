import Foundation
import Testing
@testable import TankbookCore

/// Confirm admits a pump photo nothing was read from.
@Suite("Pump read failure")
struct PumpReadFailureTests {
    @Test("a pump photo with none of the three numbers is a read failure; a guessed currency is no reading")
    func nothingReadIsAFailure() {
        #expect(PumpReadFailure.applies(provenance: .pumpPhoto, extraction: FuelExtraction(currency: .eur),
                                        hasPhoto: true))
        #expect(PumpReadFailure.applies(provenance: .pumpPhoto, extraction: nil, hasPhoto: true))
    }

    @Test("one number read, a receipt, or no photo is not a pump read failure")
    func anythingReadIsNot() {
        #expect(!PumpReadFailure.applies(provenance: .pumpPhoto, extraction: FuelExtraction(liters: 38.32),
                                         hasPhoto: true))
        #expect(!PumpReadFailure.applies(provenance: .receiptScan, extraction: FuelExtraction(), hasPhoto: true))
        #expect(!PumpReadFailure.applies(provenance: .pumpPhoto, extraction: FuelExtraction(), hasPhoto: false))
    }
}
