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

    @Test("a slicer mark outranks the classifier's bit on every cell of its row")
    func slicerMarkWins() {
        // video-003: the classifier fired on cell 0 (0.8), the slicer marked cell 2.
        #expect(PumpReader.markProbability(classifier: 0.8, cellMarked: false, rowMarked: true) < 0.5)
        #expect(PumpReader.markProbability(classifier: 0.1, cellMarked: true, rowMarked: true) >= 0.9)
        // No slicer mark on the row: the classifier's bit stands either way.
        #expect(PumpReader.markProbability(classifier: 0.8, cellMarked: false, rowMarked: false) == 0.8)
        #expect(PumpReader.markProbability(classifier: 0.2, cellMarked: false, rowMarked: false) == 0.2)
    }

    @Test("a row with one or no mark is returned as is")
    func singleMarkUntouched() {
        let one = [PumpCellReading(certainDigit: 3, decimalPoint: true), PumpCellReading(certainDigit: 6, decimalPoint: false)]
        #expect(PumpReader.singleDecimalMark(one) == one)
        let none = [PumpCellReading(certainDigit: 3, decimalPoint: false)]
        #expect(PumpReader.singleDecimalMark(none) == none)
    }
}
