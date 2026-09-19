import Foundation
import Testing
@testable import TankbookCore

/// RV.296: the one per100 -> display conversion. The four units round-trip
/// the golden D1 figure; the inverted units say so; the displayed percent is
/// the display figure's own percent, not per100's.
struct ConsumptionDisplayTests {
    /// The D1 golden headline (docs/SCHEMA.md): 6.0 L/100km.
    private let per100 = 6.0

    @Test("the four units convert the golden figure")
    func fourUnits() {
        #expect(ConsumptionDisplay.value(per100: per100, unit: .consumption(.lPer100)) == 6.0)
        #expect(ConsumptionDisplay.rounded(per100: per100, unit: .consumption(.mpgUS)) == 39.2)
        #expect(ConsumptionDisplay.rounded(per100: per100, unit: .consumption(.mpgUK)) == 47.1)
        #expect(ConsumptionDisplay.rounded(per100: per100, unit: .consumption(.kmPerL)) == 16.7)
        #expect(ConsumptionDisplay.value(per100: 18.0, unit: .energyPer100) == 18.0, "kWh/100 is per100 as is")
        #expect(ConsumptionDisplay.value(per100: 0, unit: .consumption(.mpgUS)) == 0, "no infinity for a zero")
    }

    @Test("MPG and km/L are inverted; L/100 and kWh/100 are not")
    func inversion() {
        #expect(!ConsumptionDisplay.isInverted(.consumption(.lPer100)))
        #expect(!ConsumptionDisplay.isInverted(.energyPer100))
        #expect(ConsumptionDisplay.isInverted(.consumption(.mpgUS)))
        #expect(ConsumptionDisplay.isInverted(.consumption(.mpgUK)))
        #expect(ConsumptionDisplay.isInverted(.consumption(.kmPerL)))
    }

    @Test("the displayed percent is the display figure's, so a 20% drop in L/100 is a 25% rise in MPG")
    func displayedPercent() {
        let lPer100 = ConsumptionDisplay.displayedPercentChange(fromPer100: 10, toPer100: 8,
                                                                unit: .consumption(.lPer100))
        #expect(lPer100.map { ($0 * 10).rounded() / 10 } == 20.0)
        let mpg = ConsumptionDisplay.displayedPercentChange(fromPer100: 10, toPer100: 8, unit: .consumption(.mpgUS))
        #expect(mpg.map { ($0 * 10).rounded() / 10 } == 25.0)
        #expect(ConsumptionDisplay.displayedPercentChange(fromPer100: 0, toPer100: 8,
                                                          unit: .consumption(.mpgUS)) == nil)
    }
}
