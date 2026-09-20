import Foundation
import Testing
@testable import TankbookCore

@Suite("Pump reader: one decimal mark per row")
struct PumpReaderDecimalMarkTests {
    @Test("two marks in a row keep only the stronger one")
    func strongerMarkWins() {
        let row = [
            PumpCellReading(certainDigit: 1, decimalPoint: true, confidence: 0.6),
            PumpCellReading(certainDigit: 9, decimalPoint: true, confidence: 0.95),
            PumpCellReading(certainDigit: 0, decimalPoint: false),
            PumpCellReading(certainDigit: 9, decimalPoint: false),
        ]
        let fixed = PumpReader.singleDecimalMark(row)
        #expect(fixed.map(\.decimalPoint) == [false, true, false, false])
        #expect(fixed.map { $0.ranked[0].digit } == [1, 9, 0, 9], "digits are untouched")
    }

    @Test("a row with one or no mark is returned as is")
    func singleMarkUntouched() {
        let one = [PumpCellReading(certainDigit: 3, decimalPoint: true), PumpCellReading(certainDigit: 6, decimalPoint: false)]
        #expect(PumpReader.singleDecimalMark(one) == one)
        let none = [PumpCellReading(certainDigit: 3, decimalPoint: false)]
        #expect(PumpReader.singleDecimalMark(none) == none)
    }
}
